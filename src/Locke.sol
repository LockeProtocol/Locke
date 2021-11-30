// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import "./LockeERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC20.sol";

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
    function gov() external view returns (address);
    function emergency_gov() external view returns (address);
}

abstract contract ExternallyGoverned {
    IGoverned public gov;

    constructor(address governor) {
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

interface LockeCallee {
    function lockeCall(address initiator, uint256 amount, bytes calldata data) external;
}

// ====== Stream =====
contract Stream is LockeERC20, ExternallyGoverned {
    using SafeTransferLib for ERC20;    
    // ======= Structs ========
    struct TokenStream {
        uint256 lastCumulativeRewardPerToken;
        uint256 virtualBalance;
        uint112 tokens;
        uint32 lastUpdate;
        bool merkleAccess;
    }

    // ======= Storage ========
    // ==== Immutables =====
    // stream start time
    uint32 private immutable startTime;
    // length of stream
    uint32 private immutable streamDuration;
    // length of time depositTokens are locked after stream ends
    uint32 private immutable depositLockDuration;
    // length of time rewardTokens are locked after stream ends
    uint32 private immutable rewardLockDuration;

    // end of stream
    uint32 private immutable endStream;
    // end of deposit lock
    uint32 private immutable endDepositLock;
    // end of reward lock
    uint32 private immutable endRewardLock;

    // Token given to depositer
    address public immutable rewardToken;
    // Token deposited
    address public immutable depositToken;

    // This stream's id
    uint64 public immutable streamId;

    // fee percent on reward tokens
    uint16 private immutable feePercent;
    // are fees enabled
    bool private immutable feeEnabled;

    // deposits are basically a *sale* to the stream creator if true
    bool public immutable isSale;

    // stream creator
    address public immutable streamCreator;

    // allows for a merkle staking restriction
    bool private immutable merkleAccessOnly;
    bytes32 private immutable merkleRoot;

    uint112 private immutable depositDecimalsOne;
    // ============

    //  == sloc a ==
    // internal reward token amount to be given to depositors
    uint112 private rewardTokenAmount;
    // internal deposit token amount locked/to be sold to stream creator
    uint112 private depositTokenAmount;
    // ============

    // == slot b ==
    uint112 private rewardTokenFeeAmount;
    uint112 private depositTokenFlashloanFeeAmount;
    uint8 private unlocked = 1;
    bool private claimedDepositTokens;
    // ============

    // == slot c ==
    uint256 private cumulativeRewardPerToken;
    // =====

    // ===
    uint256 private totalVirtualBalance;
    // ==

    // ==
    uint112 public unstreamed;
    uint112 private redeemedDepositTokens;
    uint32 private lastUpdate;
    // ============

    uint256 priceTimeAccumulator;

    // mapping of address to number of depositTokens deposited if this was a sale
    // used for rewards calculation
    mapping (address => uint112) public rewards;

    // mapping of address to number of tokens not yet streamed over
    mapping (address => TokenStream) public tokensNotYetStreamed;

    // external incentives to stream creator
    mapping (address => uint112) public incentives;

    // ======= Events ========
    event StreamFunded(uint256 amount);
    event Staked(address indexed who, uint256 amount);
    event Withdrawn(address indexed who, uint256 amount);
    event StreamIncentivized(address indexed token, uint256 amount);
    event StreamIncentiveClaimed(address indexed token, uint256 amount);
    event SoldTokensClaimed(address who, uint256 amount);
    event DepositTokensReclaimed(address indexed who, uint256 amount);
    event FeesClaimed(address who, uint256 amount);
    event RecoveredTokens(address indexed token, address indexed recipient, uint256 amount);
    event RewardsClaimed(address indexed who, uint256 amount);
    event Flashloaned(address indexed token, address who, uint256 amount, uint256 fee);

    // ======= Modifiers ========
    modifier updateStream(address who) {
        require(block.timestamp < endStream , "!stream");
        TokenStream storage ts = tokensNotYetStreamed[msg.sender];

        if (block.timestamp >= startTime) {
            // set lastUpdates if need be
            if (ts.lastUpdate == 0) {
                ts.lastUpdate = uint32(block.timestamp);
            }
            if (lastUpdate == 0) {
                lastUpdate = uint32(block.timestamp);
            }

            // accumulate reward per token info
            cumulativeRewardPerToken = rewardPerToken();

            // update user rewards
            rewards[msg.sender] = earned(ts, cumulativeRewardPerToken);
            // update users last cumulative reward per token
            ts.lastCumulativeRewardPerToken = cumulativeRewardPerToken;

            // update users unstreamed balance
            uint32 acctTimeDelta = uint32(block.timestamp) - ts.lastUpdate;
            if (acctTimeDelta > 0) {
                if (ts.tokens > 0) {
                    // some time has passed since this user last interacted
                    // update ts not yet streamed
                    ts.tokens -= uint112(acctTimeDelta * ts.tokens / (endStream - ts.lastUpdate));
                    ts.lastUpdate = uint32(block.timestamp);
                }
            }

            // handle global unstreamed
            uint32 tdelta = uint32(block.timestamp - lastUpdate);
            // stream tokens over
            if (tdelta > 0) {
                if (unstreamed > 0) {
                    uint256 globalStreamingSpeedPerSecond = (uint256(unstreamed) * 10**6)/ (endStream - lastUpdate);
                    unstreamed -= uint112((uint256(tdelta) * globalStreamingSpeedPerSecond) / 10**6);
                }
            }
            lastUpdate = uint32(block.timestamp);
        } else {
            if (ts.lastUpdate == 0) {
                ts.lastUpdate = startTime;
            }
            if (lastUpdate == 0) {
                lastUpdate = startTime;
            }
        }
        _;
    }

    modifier lock {
        require(unlocked == 1, "rug:reentrant");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    constructor(
        uint64 _streamId,
        address creator,
        bool _isSale,
        StreamFactory.Tokens memory tkns,
        StreamFactory.StreamParams memory streamParams,
        StreamFactory.GovernableFeeParams memory feeParams,
        StreamFactory.MerkleParams memory merkleParams
    )
        LockeERC20(tkns.depositToken, _streamId, streamParams.startTime + streamParams.streamDuration)
        ExternallyGoverned(msg.sender) // inherit factory governance
        public 
    {
        // set fee info
        feePercent = feeParams.feePercent;
        feeEnabled = feeParams.feeEnabled;

        // limit feePercent
        require(feePercent < 10000, "rug:fee");
    
        // store streamParams
        startTime = streamParams.startTime;
        streamDuration = streamParams.streamDuration;
        depositLockDuration = streamParams.depositLockDuration;
        rewardLockDuration = streamParams.rewardLockDuration;

        endStream = startTime + streamDuration;
        endDepositLock = endStream + depositLockDuration;
        endRewardLock = endStream + rewardLockDuration;
    
        // set tokens
        depositToken = tkns.depositToken;
        rewardToken = tkns.rewardToken;

        // set streamId
        streamId = _streamId;

        // set sale info
        isSale = _isSale;
    
        streamCreator = creator;

        merkleAccessOnly = merkleParams.access;
        merkleRoot = merkleParams.root;

        depositDecimalsOne = uint112(10**ERC20(depositToken).decimals());
    }

    /**
     * @dev Returns relevant internal token amounts
    **/
    function tokenAmounts() public view returns (uint112, uint112, uint112) {
        return (rewardTokenAmount, depositTokenAmount, rewardTokenFeeAmount);
    }

    /**
     * @dev Returns fee parameters
    **/
    function feeParams() public view returns (uint16, bool) {
        return (feePercent, feeEnabled);
    }

    /**
     * @dev Returns stream parameters
    **/
    function streamParams() public view returns (uint32,uint32,uint32,uint32) {
        return (
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration
        );
    }

    function dilutedBalance(uint112 amount) public returns (uint256) {
        // duration / timeRemaining * amount
        if (block.timestamp < startTime) {
            return amount;
        } else {
            uint32 timeRemaining = endStream - uint32(block.timestamp);
            return ((uint256(streamDuration) * amount * 10**6) / timeRemaining) / 10**6;
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalVirtualBalance == 0) {
            return cumulativeRewardPerToken;
        } else {
            // ∆time*rewardTokensPerSecond*oneDepositToken / totalVirtualBalance
            return cumulativeRewardPerToken + (
                ((uint256(block.timestamp) - lastUpdate) * (rewardTokenAmount/streamDuration) * depositDecimalsOne) 
                / totalVirtualBalance
            );
        }
    }

    function earned(TokenStream storage ts, uint256 currCumRewardPerToken) internal view returns (uint112) {
        return uint112(ts.virtualBalance * (currCumRewardPerToken - ts.lastCumulativeRewardPerToken) / depositDecimalsOne) + rewards[msg.sender];
    }

    /**
     * @dev Allows _anyone_ to fund this stream, if its before the stream start time
    **/
    function fundStream(uint112 amount) public lock {
        require(amount > 0, "fund:poor");
        require(block.timestamp < startTime, ">time");
        uint112 amt;
        // if fee is enabled, take a fee
        if (feeEnabled) {
            // Safety:
            //  1. feePercent & y are casted up to u256, so cannot overflow when multiplying
            //  2. downcast is safe because (x*y)/MAX_X is guaranteed to be smaller than y which is uint112
            //  3. amount is guaranteed to be greater than feeAmt
            uint112 feeAmt;
            unchecked {
                feeAmt = uint112(uint256(feePercent) * uint256(amount) / 10000); 
                amt = amount - feeAmt;
            }

            // since this operation can be repeated, we cannot assume no overflow so use checked math
            rewardTokenFeeAmount += feeAmt;
            rewardTokenAmount += amt;
        } else {
            amt = amount;
            rewardTokenAmount += amt;
        }
        // transfer from sender
        uint256 prevBal = ERC20(rewardToken).balanceOf(address(this));
        ERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(rewardToken).balanceOf(address(this));
        require(newBal > prevBal, "rug:bal");

        if (newBal < prevBal + amount) {
            uint256 attempted = prevBal + amount;
            require(attempted <= type(uint112).max, "rug:erc20");
            // some kind of fee on transfer token, we got less than expected
            uint112 delta = uint112(attempted - newBal);
            // if the rewardToken takes a fee on transfer, likely
            // the rewarder is the one in control of the impl. We only charge their
            // rewards because of that fact
            rewardTokenAmount -= delta;
            amt -= delta;
        }
        
        emit StreamFunded(amt);
    }

    /**
     *  @dev Deposits depositTokens into this stream if user can prove they are in the list of approved depositors
     * 
     *  doesn't lock or update stream as that is handled in stake. Only needs to be called first time staking
    */ 
    function merkleStake(uint112 amount, bytes32[] calldata merkleProof) public {
        require(merkleAccessOnly, "stake:!merkle");
        bytes32 node = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "stake:!access");
        TokenStream storage ts = tokensNotYetStreamed[msg.sender];
        ts.merkleAccess = true;
        stake(amount);
    }

    /**
     *  @dev Deposits depositTokens into this stream
     * 
     *  additionally, updates tokensNotYetStreamed
    */ 
    function stake(uint112 amount) public lock updateStream(msg.sender) {
        if (merkleAccessOnly) {
            TokenStream storage ts = tokensNotYetStreamed[msg.sender];
            require(ts.merkleAccess, "stake:!access");
        }

        require(amount > 0, "stake:poor");

        // checked in updateStream
        // require(block.timestamp < endStream, "stake:!stream");

        // transfer tokens over
        uint256 prevBal = ERC20(depositToken).balanceOf(address(this));
        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(depositToken).balanceOf(address(this));
        require(newBal <= type(uint112).max, "rug:erc20");
        require(newBal > prevBal, "rug:bal");
        
        uint112 trueDepositAmt = uint112(newBal - prevBal);

        depositTokenAmount += trueDepositAmt;
        TokenStream storage ts = tokensNotYetStreamed[msg.sender];
        ts.tokens += trueDepositAmt;

        uint256 virtualBal = dilutedBalance(trueDepositAmt);
        ts.virtualBalance += virtualBal;
        totalVirtualBalance += virtualBal;
        unstreamed += trueDepositAmt;


        uint256 receiptTokenAmt = trueDepositAmt;

        if (!isSale) {
            // not a straight sale, so give the user some receipt tokens
            _mint(msg.sender, receiptTokenAmt);
        } else {
        }

        emit Staked(msg.sender, trueDepositAmt);
    }

    /**
     *  @dev Allows a stream depositor to withdraw a specific amount of depositTokens during a stream,
     *  up to their tokensNotYetStreamed amount
     * 
     *  additionally, updates tokensNotYetStreamed
    */ 
    function withdraw(uint112 amount) public lock updateStream(msg.sender) {
        require(amount > 0, "withdraw:poor");

        // checked in updateStream
        // is the stream still going on? thats the only time a depositer can withdraw
        // require(block.timestamp < endStream, "withdraw:!stream");
        TokenStream storage ts = tokensNotYetStreamed[msg.sender];

        require(ts.tokens >= amount, "withdraw:steal");
        ts.tokens -= amount;

        uint256 virtualBal = dilutedBalance(amount);
        ts.virtualBalance -= virtualBal;
        totalVirtualBalance -= virtualBal;
        depositTokenAmount -= amount;
        if (!isSale) {
            _burn(msg.sender, amount);
        } else {
        }

        // do the transfer
        ERC20(depositToken).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     *  @dev Allows a stream depositor to exit their entire remaining tokens that haven't streamed
     *  and burns receiptTokens if its not a sale.
     * 
     *  additionally, updates tokensNotYetStreamed
    */ 
    function exit() public lock updateStream(msg.sender) {
        // checked in updateStream
        // is the stream still going on? thats the only time a depositer can withdraw
        // require(block.timestamp < endStream, "withdraw:!stream");
        TokenStream storage ts = tokensNotYetStreamed[msg.sender];
        uint112 amount = ts.tokens;

        require(amount > 0, "withdraw:poor");
        
        ts.tokens = 0;
        totalVirtualBalance -= ts.virtualBalance;
        ts.virtualBalance = 0;

        depositTokenAmount -= amount;
        if (!isSale) {
            _burn(msg.sender, amount);
        } else {
        }

        // do the transfer
        ERC20(depositToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     *  @dev Allows anyone to incentivize this stream with extra tokens
     *  and requires the incentive to not be the reward or deposit token
    */ 
    function createIncentive(address token, uint112 amount) public lock {
        require(token != rewardToken && token != depositToken, "rug:incentive");
        incentives[token] += amount;

        uint112 amt = amount;
        uint256 prevBal = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(token).balanceOf(address(this));
        require(newBal <= type(uint112).max, "rug:erc20");
        require(newBal > prevBal, "rug:bal");

        if (newBal < prevBal + amount) {
            uint256 attempted = prevBal + amount;
            require(attempted <= type(uint112).max, "rug:erc20");
            // some kind of fee on transfer token, we got less than expected
            uint112 delta = uint112(attempted - newBal);
            incentives[token] -= delta;
            amt -= delta;
        }

        emit StreamIncentivized(token, amt);
    }

    /**
     *  @dev Allows the stream creator to claim an incentive once the stream is done
    */ 
    function claimIncentive(address token) public lock {
        // creator is claiming
        require(msg.sender == streamCreator, "claim:!creator");
        // stream ended
        require(block.timestamp >= endStream, "claim:stream");
        uint112 amount = incentives[token];
        require(amount > 0, "claim:poor");
        incentives[token] = 0;
        ERC20(token).safeTransfer(msg.sender, amount);
        emit StreamIncentiveClaimed(token, amount);
    }

    /**
     *  @dev Allows a receipt token holder to reclaim deposit tokens if the deposit lock is done & their receiptToken amount
     *  is greater than the requested amount
    */ 
    function claimDepositTokens(uint112 amount) public lock {
        require(!isSale, "claim:sale");
        // NOTE: given that endDepositLock is strictly *after* the last time withdraw or exit is callable
        // we dont need to updateStream(msg.sender)
        require(amount > 0, "claim:poor");

        // is the stream over + the deposit lock period over? thats the only time receiptTokens can be burned for depositTokens after stream is over
        require(block.timestamp > endDepositLock, "claim:lock");

        // burn the receiptTokens
        _burn(msg.sender, amount);

        redeemedDepositTokens += amount;

        // send the receipt token holder back the funds
        ERC20(depositToken).safeTransfer(msg.sender, amount);

        emit DepositTokensReclaimed(msg.sender, amount);
    }

    /**
     *  @dev Allows a receipt token holder (or original depositor in case of a sale) to claim their rewardTokens
    */ 
    function claimReward() public lock {
        require(block.timestamp > endRewardLock, "claim:lock");

        uint256 rewardAmt = rewards[msg.sender];
        rewards[msg.sender] = 0;

        require(rewardAmt > 0, "claim:poor");

        // transfer the tokens
        ERC20(rewardToken).safeTransfer(msg.sender, rewardAmt);

        emit RewardsClaimed(msg.sender, rewardAmt);
    }

    /**
     *  @dev Allows a creator to claim sold tokens if the stream has ended & this contract is a sale
    */ 
    function creatorClaimSoldTokens(address destination) public lock {
        // can only claim when its a sale
        require(isSale, "claim:!sale");

        // only can claim once
        require(!claimedDepositTokens, "claim:claimed");
        // creator is claiming
        require(msg.sender == streamCreator, "claim:!creator");
        // stream ended
        require(block.timestamp >= endStream, "claim:stream");
        
        uint112 amount = depositTokenAmount;
        claimedDepositTokens = true;

        ERC20(depositToken).safeTransfer(destination, amount);

        emit SoldTokensClaimed(destination, amount);
    }

    /**
     *  @dev Allows the governance contract of the factory to select a destination
     *  and transfer fees (in rewardTokens) to that address totaling the total fee amount
    */ 
    function claimFees(address destination) public lock externallyGoverned {
        // Stream is done
        require(block.timestamp >= endStream, "claim:stream");

        // reset fee amount
        uint112 fees = rewardTokenFeeAmount;
        rewardTokenFeeAmount = 0;

        // transfer and emit event
        ERC20(rewardToken).safeTransfer(destination, fees);
        emit FeesClaimed(destination, fees);
    }

    // ======== Non-protocol functions ========

    /**
     *  @dev Allows the stream creator to save tokens
     *  There are some limitations to this:
     *      1. if its deposit token:
     *          - DepositLock is fully done
     *          - There are excess deposit tokens (balance - depositTokenAmount)
     *      2. if its the reward token:
     *          - RewardLock is fully done
     *          - Excess defined as balance - (rewardTokenAmount + rewardTokenFeeAmount)
     *      3. if incentivized:
     *          - excesss defined as bal - incentives[token]
    */ 
    function recoverTokens(address token, address recipient) public lock {
        // NOTE: it is the stream creators responsibility to save
        // tokens on behalf of their users.
        require(msg.sender == streamCreator, "save:!creator");
        if (token == depositToken) {
            require(block.timestamp > endDepositLock, "rug:recoverTime");
            // get the balance of this contract
            uint256 bal = ERC20(token).balanceOf(address(this));
            // check what isnt claimable by either party
            uint256 excess = bal - (depositTokenAmount - redeemedDepositTokens);
            // allow saving of the token
            ERC20(token).safeTransfer(recipient, excess);

            emit RecoveredTokens(token, recipient, excess);
            return;
        }
        
        if (token == rewardToken) {
            require(block.timestamp > endRewardLock, "rug:recoverTime");
            // check current balance vs internal balance
            //
            // NOTE: if a token rebases, i.e. changes balance out from under us,
            // most of this contract breaks and rugs depositors. this isn't exclusive
            // to this function but this function would in theory allow someone to rug
            // and recover the excess (if it is worth anything)
            uint256 bal = ERC20(token).balanceOf(address(this));

            // check what isnt claimable by depositors and governance
            uint256 excess = bal - (rewardTokenAmount + rewardTokenFeeAmount);
            ERC20(token).safeTransfer(recipient, excess);

            emit RecoveredTokens(token, recipient, excess);
            return;
        }

        if (incentives[token] > 0) {
            require(block.timestamp >= endStream, "claim:stream");
            uint256 bal = ERC20(token).balanceOf(address(this));
            uint256 excess = bal - incentives[token];
            ERC20(token).safeTransfer(recipient, excess);
            emit RecoveredTokens(token, recipient, excess);
            return;
        }

        // not reward token nor deposit nor incentivized token, free to transfer
        uint256 bal = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransfer(recipient, bal);
        emit RecoveredTokens(token, recipient, bal);
    }

    /**
     *  @dev Allows anyone to flashloan reward or deposit token for a 10bps fee
    */
    function flashloan(address token, address to, uint112 amount, bytes memory data) public lock {
        require(token == depositToken || token == rewardToken, "rug:flashloan");

        uint256 preDepositTokenBalance = ERC20(depositToken).balanceOf(address(this));
        uint256 preRewardTokenBalance = ERC20(rewardToken).balanceOf(address(this));

        ERC20(token).safeTransfer(to, amount);

        // the `to` contract should have a public function with the signature:
        // function lockeCall(address initiator, uint256 amount, bytes memory data);
        LockeCallee(to).lockeCall(msg.sender, amount, data);

        uint256 postDepositTokenBalance = ERC20(depositToken).balanceOf(address(this));
        uint256 postRewardTokenBalance = ERC20(rewardToken).balanceOf(address(this));

        uint112 feeAmt = amount * 10 / 10000; // 10bps fee

        if (token == depositToken) {
            depositTokenFlashloanFeeAmount += feeAmt;
            require(preDepositTokenBalance + feeAmt <= postDepositTokenBalance, "rug:flashloan");
            require(preRewardTokenBalance <= postRewardTokenBalance, "rug:flashloan");
        } else {
            rewardTokenFeeAmount += feeAmt;
            require(preDepositTokenBalance <= postDepositTokenBalance, "rug:flashloan");
            require(preRewardTokenBalance + feeAmt <= postRewardTokenBalance, "rug:flashloan");
        }

        emit Flashloaned(token, msg.sender, amount, feeAmt);
    }

    /**
     *  @dev Allows inherited governance contract to call functions on behalf of this contract
     *  This is a potentially dangerous function so to ensure trustlessness, *all* balances
     *  that may matter are guaranteed to not change.
     * 
     *  The primary usecase is for claiming potentially airdrops that may have accrued on behalf of this contract
    */
    function arbitraryCall(address who, bytes memory data) public lock externallyGoverned {
        // cannot have an active incentive for the callee
        require(incentives[who] == 0, "rug:incentives");
        // cannot be to deposit token nor reward token
        require(who != depositToken && who != rewardToken, "rug:token");

        // get token balances
        uint256 preDepositTokenBalance = ERC20(depositToken).balanceOf(address(this));
        uint256 preRewardTokenBalance = ERC20(rewardToken).balanceOf(address(this));

        (bool success, bytes memory _ret) = who.call(data);
        require(success);

        // require no change in balances
        uint256 postDepositTokenBalance = ERC20(depositToken).balanceOf(address(this));
        uint256 postRewardTokenBalance = ERC20(rewardToken).balanceOf(address(this));
        require(preDepositTokenBalance == postDepositTokenBalance && preRewardTokenBalance == postRewardTokenBalance, "rug:token");
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
    
    struct StreamParams {
        uint32 startTime;
        uint32 streamDuration;
        uint32 depositLockDuration;
        uint32 rewardLockDuration;
    }
    
    struct MerkleParams {
        bool access;
        bytes32 root;
    }

    struct Tokens {
        address depositToken;
        address rewardToken;
    }

    // ======= Storage ========
    GovernableStreamParams public streamParams;
    GovernableFeeParams public feeParams;
    uint64 public currStreamId; 

    uint16 constant MAX_FEE_PERCENT = 500; // 500/10000 == 5%

    // =======  Events  =======
    event StreamCreated(uint256 indexed stream_id, address stream_addr);
    event StreamParametersUpdated(GovernableStreamParams oldParams, GovernableStreamParams newParams);
    event FeeParametersUpdated(GovernableFeeParams oldParams, GovernableFeeParams newParams);

    constructor(address _governor, address _emergency_governor) public Governed(_governor, _emergency_governor) {
        streamParams = GovernableStreamParams({
            maxDepositLockDuration: 52 weeks,
            maxRewardLockDuration: 52 weeks,
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
        bool merkleAccess,
        bytes32 merkleRoot
    )
        public
        returns (Stream)
    {
        // perform checks

        StreamParams memory sp = StreamParams({
            startTime: startTime,
            streamDuration: streamDuration,
            depositLockDuration: depositLockDuration,
            rewardLockDuration: rewardLockDuration
        });

        MerkleParams memory mp =MerkleParams({
            access: merkleAccess,
            root: merkleRoot
        });

        Tokens memory tkns = Tokens({
            depositToken: depositToken,
            rewardToken: rewardToken
        });

        {
            require(sp.startTime >= block.timestamp, "rug:past");
            require(sp.streamDuration >= streamParams.minStreamDuration && sp.streamDuration <= streamParams.maxStreamDuration, "rug:streamDuration");
            require(sp.depositLockDuration <= streamParams.maxDepositLockDuration, "rug:lockDuration");
            require(sp.rewardLockDuration <= streamParams.maxRewardLockDuration, "rug:rewardDuration");
            if (mp.access) {
                require(mp.root != bytes32(0), "merkle");
            }
        }
        

        // TODO: figure out sane salt, i.e. streamid + x? streamid guaranteed to be unique
        uint64 that_stream = currStreamId;
        currStreamId += 1;
        bytes32 salt = bytes32(uint256(that_stream));

        Stream stream = new Stream{salt: salt}(
            that_stream,
            msg.sender,
            isSale,
            tkns,
            sp,
            feeParams,
            mp
        );

        // emit
        emit StreamCreated(that_stream, address(stream));

        // return stream;
        return stream;
    }

    function updateStreamParams(GovernableStreamParams memory newParams) public governed {
        // DATA VALIDATION:
        //  there is no real concept of "sane" limits here, and if misconfigured its ultimated
        //  not a massive deal so no data validation is done
        GovernableStreamParams memory old = streamParams;
        streamParams = newParams;
        emit StreamParametersUpdated(old, newParams);
    }

    function updateFeeParams(GovernableFeeParams memory newFeeParams) public governed {
        require(newFeeParams.feePercent <= MAX_FEE_PERCENT, "rug:fee");
        GovernableFeeParams memory old = feeParams;
        feeParams = newFeeParams;
        emit FeeParametersUpdated(old, newFeeParams);
    }
}
