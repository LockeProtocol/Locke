// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";


contract Governed {
    address public governor;
    address public emergency_governor;

    constructor(address _governor, address _emergency_governor) public {
        if (_governor != address(0)) {
            // set governor
            governor = _governor;
        } 
        if (_emergency_governor != address(0)) {
            // set e_governor
            emergency_governor = _emergency_governor;
        } 
    }

    // ====== Modifiers =======
    /// Governed function
    modifier governed {
        require(msg.sender == governor, "!gov");
        _;
    }

    /// Emergency governed function
    modifier emergency_governed {
        require(msg.sender == governor || msg.sender == emergency_governor, "!e_gov");
        _;
    }
}

contract Stream is ERC20 {
    
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

    StreamParams public streamParms;


    event StreamFunded(uint256 amount);
    constructor(
        uint64 streamId,
        address creator,
        address rewardToken,
        uint256 rewardTokenAmount,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        bool isSale,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        uint16 feePercent,
        bool feeEnabled
    )
        ERC20(depositToken, streamId, startTime + streamDuration)
        public 
    {
        require(feePercent < 10000, "rug:fee");
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
        // transfer tokens over
        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        if (!isSale) {
            // not a straight sale, so give the user some receipt tokens
        }
    }


    function recoverTokens(address token, address receipient) {
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
    GovernableStreamParams public streamParms;
    uint128 internal curr_stream; 


    // =======  Events  =======
    event StreamCreated(uint256 indexed stream_id, address stream_addr);
    event StreamParametersUpdated(GovernableStreamParams oldParams, GovernableStreamParams newParams);
    event FeeParametersUpdated(GovernableFeeParams oldParams, GovernableFeeParams newParams);

    constructor(address _governor, address _emergency_governor) public Governed(_governor, _emergency_governor) {
        streamParms = GovernableStreamParams {
            maxDepositLockDuration: 1 years,
            maxRewardLockDuration: 1 years,
            maxStreamDuration: 2 weeks,
            minStreamDuration: 1 hours
        };
    }

    /**
     * @dev Deploys a minimal contract pointing to streaming logic. This contract will also be the token contract
     * for the receipt token. It custodies the depositTokens until depositLockDuration is complete. After
     * lockDuration is completed, the depositTokens can be claimed by the original depositors
     * 
    **/
    function createStream(
        address rewardToken,
        uint256 rewardTokenAmount,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        bool isSale,
        uint32 depositLockDuration,
        uint32 rewardLockDuration
    )
        public
    {
        // perform checks
        require(streamDuration >= minStreamDuration && streamDuration <= maxStreamDuration, "rug:streamDuration");
        require(depositLockDuration <= maxDepositLockDuration, "rug:lockDuration");
        require(rewardLockDuration <= maxRewardLockDuration, "rug:rewardDuration");

        // TODO: figure out sane salt, i.e. streamid + x? streamid guaranteed to be unique
        uint128 that_stream = curr_stream;
        bytes32 salt = bytes32(uint256(that_stream));

        Stream stream = new Stream{salt: salt}(
            msg.sender,
            rewardToken,
            rewardTokenAmount,
            depositToken,
            startTime,
            streamDuration,
            isSale,
            depositLockDuration,
            rewardLockDuration
        );

        // bump stream id
        curr_stream += 1;

        // emit
        emit StreamCreated(that_stream, stream_addr); 
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
