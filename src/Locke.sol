// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";

// ====== Governance =====
contract Governed {
    address public gov;
    address public pendingGov;
    address public emergency_gov;

    event NewGov(address oldGov, address newGov);
    event NewPendingGov(address oldPendingGov, address newPendingGov);

    constructor(address _governor, address _emergency_governor) public {
        if (_governor != address(0)) {
            // set governor
            gov = _governor;
        } 
        if (_emergency_governor != address(0)) {
            // set e_governor
            emergency_gov = _emergency_governor;
        } 
    }

    /// Update pending governor
    function setPendingGov(address newPendingGov) governed public {
        address old = pendingGov;
        pendingGov = newPendingGov;
        emit NewPendingGov(old, newPendingGov);
    }

    /// Accepts governorship
    function acceptGov() public {
        require(pendingGov == msg.sender, "gov:!pending");
        address old = gov;
        gov = pendingGov;
        emit NewGov(old, pendingGov);
    }

    /// Remove governor
    function __abdicate() governed public {
        address old = gov;
        gov = address(0);
        emit NewGov(old, address(0));
    }

    // ====== Modifiers =======
    /// Governed function
    modifier governed {
        require(msg.sender == gov, "!gov");
        _;
    }

    /// Emergency governed function
    modifier emergency_governed {
        require(msg.sender == gov || msg.sender == emergency_gov, "!e_gov");
        _;
    }
}

interface IGoverned {
    function gov() public view returns (address);
    function emergency_gov() public view returns (address);
}

contract ExternallyGoverned {
    IGoverned public gov;

    constructor(address iGovernor) public {
        gov = IGoverned(governor);
    }

    // ====== Modifiers =======
    /// Governed function
    modifier externallyGoverned {
        require(msg.sender == gov.gov(), "!gov");
        _;
    }

    /// Emergency governed function
    modifier externallyEmergencyGoverned {
        require(msg.sender == gov.gov() || msg.sender == gov.emergency_gov(), "!e_gov");
        _;
    }
}

// ====== Stream =====
contract Stream is ERC20, ExternallyGoverned {
    
    // ======= Structs ========
    struct StreamParams {
        uint32 startTime;
        uint32 streamDuration;
        uint32 depositLockDuration;
        uint32 rewardLockDuration;
    }


    // ======= Storage ========
    uint112 private rewardTokenAmount;
    uint112 private depositTokenAmount;
    uint16 private feePercent;
    bool private feeEnabled;
    bool private isSale;

    uint112 private rewardTokenFeeAmount;

    StreamParams public streamParams;


    event StreamFunded(uint256 amount);
    constructor(
        uint64 streamId,
        address creator,
        address rewardToken,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        uint16 feePercent,
        bool feeEnabled,
        bool isSale
    )
        ERC20(depositToken, streamId, startTime + streamDuration)
        public 
    {
        require(feePercent < 10000, "rug:fee");
    }

    function tokenAmounts() public view returns (uint112, uint112, uint112) {
        return (rewardTokenAmount, depositTokenAmount, rewardTokenFeeAmount);
    }

    /**
     * @dev Allows _anyone_ to fund this stream
    **/
    function fundStream(uint112 amount) public {
        require(amount > 0, "amt");
        require(block.timestamp < startTime, ">time");
        uint256 amt;
        // if fee is enabled, take a fee
        if (feeEnabled) {
            // Safety:
            //  1. feePercent & y are casted up to u256, so cannot overflow when multiplying
            //  2. downcast is safe because (x*y)/MAX_X is guaranteed to be smaller than y which is uint112
            //  3. amount is guaranteed to be greater than feeAmt
            unchecked {
                uint112 feeAmt = uint112(uint256(feePercent) * uint256(amount) / 10000); 
                amt = amount - feeAmt;
            }

            // since this operation can be repeated, we cannot assume no overflow so use checked math
            rewardTokenFeeAmount += feeAmt;
            rewardTokenAmount += amt;
        } else {
            amt = amount;
            rewardTokenAmount += amount;
        }
        // transfer from sender
        ERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        emit StreamFunded(amt)
    }

    function stake(uint256 amount) public {
        require(amount > 0, "stake:poor");
        require(now < startTime + streamDuration, "stake:!stream");
        
        if (!isSale) {
            // not a straight sale, so give the user some receipt tokens
        } else {

        }

        // transfer tokens over
        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
    }


    function recoverTokens(address token, address receipient) externallyGoverned public {
        // ░░░░░░░░▄▄██▀▀▀▀▀▀▀████▄▄▄▄░░░░░░░░░░░░░
        // ░░░░░▄██▀░░░░░░░░░░░░░░░░░▀▀██▄▄░░░░░░░░
        // ░░░░██░░░░░░░░░░░░░░░░░░░░░░░░▀▀█▄▄░░░░░
        // ░░▄█▀░░░░░░░░░░░░░░░░░░░░░░░░░░░░▀▀█▄░░░
        // ░▄█▀░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█▄░░
        // ░█▀░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▀█░
        // ▄█░░░░░░░░░░░░░░░░░░▄░░░░░░░░░░░░░░░░░██
        // █▀░░░░░░██▄▄▄▄▄░░░░▄█░░░░░░░░░░░░░░░░░░█
        // █░░░░░░░█▄░░▀██████▀░░░▄▄░░░░░░░░░░██░░█
        // █░░░░░░░░▀█▄▄▄█▀░░░░░░░██▀▀██▄▄▄▄▄▄█░░▄█
        // █░░░░░░░░░░░░░░░░░░░░░░░▀▄▄▄▀▀▀██▀░░░░█▀
        // █▄░░░░░▄▄░░░░░░░░░░░░░░░░░░▀▀▀▀▀░░░░▄█▀░
        // ░█▄░░░░█░░░░▄▄▄▄░░░░░░░░░░░░░░░░░░░▄█░░░
        // ░░█▄░░▀█▄░░▀▀▀███████▄▄▄░░░▄░░░░░▄█▀░░░░
        // ░░░█▄░░░░░░░░░░░░░▀▀▀░░█░░░█░░░░██░░░░░░
        // ░░░░▀█▄▄░░░░░░░░░░░░░░░░░██░░░▄█▀░░░░░░░
        // ░░░░░░▀▀█▄▄▄░░░░░░░░░░░░░▄▄▄█▀▀░░░░░░░░░
        // ░░░░░░░░░░▀▀█▀▀███▄▄▄███▀▀▀░░░░░░░░░░░░░
        // ░░░░░░░░░░░█▀░░░░░░░░░░░░░░░░░░░░░░░░░░░
        if (token == depositToken) {
            if (block.timestamp > startTime + streamDuration + depositLockDuration) {
                if (!isSale) {
                    // is not a sale and this contract is done so the deposit token can be saved
                    uint256 bal = ERC20(token).balanceOf(address(this));
                    ERC20(token).safeTransfer(bal, recipient);
                    return;
                } else {
                    // is a sale. check current balance vs internal balance
                    uint256 bal = ERC20(token).balanceOf(address(this));
                    uint256 excess = bal - totalDeposits;
                    ERC20(token).safeTransfer(excess, recipient);
                    return;
                }
            } else {
                // the stream isnt done, can't touch deposit tokens
                revert("rug:recoverTime"); 
            }
        }
        
        if (token == rewardToken) {
            // check current balance vs internal balance
            //
            // NOTE: if a token rebases, i.e. changes balance out from under us,
            // most of this contract breaks and rugs depositors. this isn't exclusive
            // to this function but this function would in theory allow someone to rug
            // and recover the excess (if it is worth anything)
            uint256 bal = ERC20(token).balanceOf(address(this));
            uint256 excess = bal - (rewardTokenAmount + rewardTokenFeeAmount);
            ERC20(token).safeTransfer(excess, recipient);
            return;
        }

        // not reward token nor deposit token, free to transfer
        uint256 bal = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransfer(bal, recipient);
    }
}

contract StreamFactory is Governed {

    // ======= Structs ========
    struct GovernableStreamParams {
        uint32 maxDepositLockDuration;
        uint32 maxRewardLockDuration;
        uint32 maxStreamDuration;
        uint32 minStreamDuration;
    }

    struct GovernableFeeParams {
        uint16 feePercent;
        bool feeEnabled;
    }

    uint16 constant MAX_FEE_PERCENT = 500; // 500/10000 == 5%
    
    // ======= Storage ========
    GovernableStreamParams public streamParams;
    GovernableFeeParams public feeParams;
    uint128 public currStreamId; 


    // =======  Events  =======
    event StreamCreated(uint256 indexed stream_id, address stream_addr);
    event StreamParametersUpdated(GovernableStreamParams oldParams, GovernableStreamParams newParams);
    event FeeParametersUpdated(GovernableFeeParams oldParams, GovernableFeeParams newParams);

    constructor(address _governor, address _emergency_governor) public Governed(_governor, _emergency_governor) {
        streamParams = GovernableStreamParams({
            maxDepositLockDuration: 1 years,
            maxRewardLockDuration: 1 years,
            maxStreamDuration: 2 weeks,
            minStreamDuration: 1 hours
        });
    }

    /**
     * @dev Deploys a minimal contract pointing to streaming logic. This contract will also be the token contract
     * for the receipt token. It custodies the depositTokens until depositLockDuration is complete. After
     * lockDuration is completed, the depositTokens can be claimed by the original depositors
     * 
    **/
    function createStream(
        address rewardToken,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        bool isSale,
    )
        public
        returns (Stream)
    {
        // perform checks
        require(startTime >= block.timestamp, "rug:past");
        require(streamDuration >= minStreamDuration && streamDuration <= maxStreamDuration, "rug:streamDuration");
        require(depositLockDuration <= maxDepositLockDuration, "rug:lockDuration");
        require(rewardLockDuration <= maxRewardLockDuration, "rug:rewardDuration");

        // TODO: figure out sane salt, i.e. streamid + x? streamid guaranteed to be unique
        uint128 that_stream = currStreamId;
        bytes32 salt = bytes32(uint256(that_stream));

        Stream stream = new Stream{salt: salt}(
            msg.sender,
            rewardToken,
            depositToken,
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration,
            feeParams.feePercent,
            feeParams.feeEnabled,
            isSale,
        );

        // bump stream id
        currStreamId += 1;

        // emit
        emit StreamCreated(that_stream, stream_addr);

        return stream;
    }

    function updateStreamParams(GovernableStreamParams memory newParams) governed public {
        // DATA VALIDATION:
        //  there is no real concept of "sane" limits here, and if misconfigured its ultimated
        //  not a massive deal so no data validation is done
        GovernableStreamParams memory old = streamParams;
        streamParams = newParams;
        emit StreamParametersUpdated(old, newParams);
    }

    function updateFeeParams(GovernableFeeParams memory newFeeParams) governed public {
        require(newFeeParams.feePercent <= MAX_FEE_PERCENT, "rug:fee");
        GovernableFeeParams memory old = feeParams;
        feeParams = newFeeParams;
        emit FeeParametersUpdated(old, newFeeParams);
    }
}
