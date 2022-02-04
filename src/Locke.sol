// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.11;

import "./LockeERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC20.sol";

// ====== Governance =====
contract MinimallyGoverned {
    address public gov;
    address public pendingGov;

    error NotPending();
    error NotGov();

    event NewGov(address indexed oldGov, address indexed newGov);
    event NewPendingGov(address indexed oldPendingGov, address indexed newPendingGov);

    constructor(address _governor) {
        gov = _governor;
    }

    /// Update pending governor
    function setPendingGov(address newPendingGov) governed external {
        address old = pendingGov;
        pendingGov = newPendingGov;
        emit NewPendingGov(old, newPendingGov);
    }

    /// Accepts governorship
    function acceptGov() external {
        if (pendingGov != msg.sender) revert NotPending();
        address old = gov;
        gov = pendingGov;
        emit NewGov(old, pendingGov);
    }

    /// Remove governor
    function __abdicate() governed external {
        address old = gov;
        gov = address(0);
        emit NewGov(old, address(0));
    }

    // ====== Modifiers =======
    /// Governed function
    modifier governed {
        if (msg.sender != gov) revert NotGov();
        _;
    }
}

abstract contract MinimallyExternallyGoverned {
    MinimallyGoverned immutable gov;

    error NotGov();

    constructor(address governor) {
        gov = MinimallyGoverned(governor);
    }

    // ====== Modifiers =======
    /// Governed function
    modifier externallyGoverned {
        if (msg.sender != gov.gov()) revert NotGov();
        _;
    }
}

interface LockeCallee {
    function lockeCall(address initiator, address token, uint256 amount, bytes calldata data) external;
}

// ====== Stream =====
contract Stream is LockeERC20, MinimallyExternallyGoverned {
    using SafeTransferLib for ERC20;    
    // ======= Structs ========
    struct TokenStream {
        uint256 lastCumulativeRewardPerToken;
        uint256 virtualBalance;
        uint112 rewards;
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

    // deposits are not ever reclaimable by depositors
    bool public immutable isIndefinite;

    // stream creator
    address public immutable streamCreator;

    uint112 private immutable depositDecimalsOne;
    // ============

    //  == sloc a ==
    // internal reward token amount to be given to depositors
    uint112 private rewardTokenAmount;
    // internal deposit token amount locked/to be claimable by stream creator
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
    // ============

    // == slot d ==
    uint256 private totalVirtualBalance;
    // ============

    // == slot e ==
    uint112 public unstreamed;
    uint112 private redeemedDepositTokens;
    // ============

    // == slot f ==
    uint112 private redeemedRewardTokens;
    uint32 public lastUpdate;
    uint32 private unaccruedSeconds;
    // ============

    // mapping of address to number of tokens not yet streamed over
    mapping (address => TokenStream) public tokenStreamForAccount;

    struct Incentive {
        uint112 amt;
        bool flag;
    }

    // external incentives to stream creator
    mapping (address => Incentive) public incentives;

    // ======= Events ========
    event StreamFunded(uint256 amount);
    event Staked(address indexed who, uint256 amount);
    event Withdrawn(address indexed who, uint256 amount);
    event StreamIncentivized(address indexed token, uint256 amount);
    event StreamIncentiveClaimed(address indexed token, uint256 amount);
    event TokensClaimed(address indexed who, uint256 amount);
    event DepositTokensReclaimed(address indexed who, uint256 amount);
    event FeesClaimed(address indexed token, address indexed who, uint256 amount);
    event RecoveredTokens(address indexed token, address indexed recipient, uint256 amount);
    event RewardsClaimed(address indexed who, uint256 amount);
    event Flashloaned(address indexed token, address indexed who, uint256 amount, uint256 fee);

    // =======   Errors  ========
    error NotStream();
    error ZeroAmount();
    error BalanceError();
    error Reentrant();
    error NotBeforeStream();
    error BadERC20Interaction();
    error NotCreator();
    error StreamOngoing();
    error StreamTypeError();
    error LockOngoing();

    // ======= Modifiers ========
    modifier updateStream() {
        // save bytecode space by making it a jump instead of inlining at cost of gas
        updateStreamInternal();
        _;
    }

    function updateStreamInternal() internal {
        if (block.timestamp >= endStream) revert NotStream();
        TokenStream storage ts = tokenStreamForAccount[msg.sender];
        // only do one cast
        //
        // Safety:
        //  1. Timestamp wont cross this point until Feb 7th, 2106.
        uint32 timestamp = uint32(block.timestamp);

        if (block.timestamp >= startTime) {
            // set lastUpdates if need be
            if (ts.lastUpdate == 0) {    
                ts.lastUpdate = timestamp;
            }

            // accumulate reward per token info
            cumulativeRewardPerToken = rewardPerToken();

            // update user rewards
            ts.rewards = earned(ts, cumulativeRewardPerToken);
            // update users last cumulative reward per token
            ts.lastCumulativeRewardPerToken = cumulativeRewardPerToken;

            // update users unstreamed balance
            unchecked {
                // Safety:
                //  1. timestamp - ts.lastUpdate: ts.lastUpdate is guaranteed to be <= current timestamp when timestamp >= startTime        
                uint32 acctTimeDelta = timestamp - ts.lastUpdate;

                if (acctTimeDelta > 0) {
                    // some time has passed since this user last interacted
                    // update ts not yet streamed
                    // downcast is safe as guaranteed to be a % of uint112
                    if (ts.tokens > 0) {

                        // Safety:
                        //  1. acctTimeDelta * ts.tokens: acctTimeDelta is uint32, ts.tokens is uint112, cannot overflow uint256
                        //  2. endStream - ts.lastUpdate: We are guaranteed to not update ts.lastUpdate after endStream
                        //  3. streamAmt guaranteed to be a truncated (rounded down) % of ts.tokens
                        uint112 streamAmt = uint112(uint256(acctTimeDelta) * ts.tokens / (endStream - ts.lastUpdate));
                        if (streamAmt == 0) revert ZeroAmount();
                        ts.tokens -= streamAmt;

                    }
                    ts.lastUpdate = timestamp;
                }

                // handle global unstreamed
                // Safety:
                //  1. timestamp - lastUpdate: lastUpdate is guaranteed to be <= current timestamp when timestamp >= startTime
                uint256 tdelta = timestamp - lastUpdate;
                // stream tokens over
                if (tdelta > 0) {
                    if (unstreamed == 0) {
                        // Safety:
                        //  1. Σ tdelta guaranteed to be < uint32.max because its upper bound is streamDuration which is a uint32
                        unaccruedSeconds += uint32(tdelta);
                    } else {
                        // Safety:
                        //  1. tdelta*unstreamed: uint32 * uint112 guaranteed to fit into uint256 so no overflow or zeroed bits
                        //  2. endStream - lastUpdate: lastUpdate guaranteed to be less than endStream in this codepath
                        //  3. tdelta*unstreamed/(endStream - lastUpdate): guaranteed to be less than unstreamed as its a % of unstreamed
                        unstreamed -= uint112(tdelta * unstreamed / (endStream - lastUpdate));
                    }
                }

                // already ensure that blocktimestamp is less than endStream so guaranteed ok here
                lastUpdate = timestamp;
            }
        } else {
            if (ts.lastUpdate == 0) {
                ts.lastUpdate = startTime;
            }
        }
    }

    function lockInternal() internal {
        if (unlocked != 1) revert Reentrant();
        unlocked = 2;
    }
    modifier lock {
        lockInternal();
        _;
        unlocked = 1;
    }

    constructor(
        uint64 _streamId,
        address creator,
        bool _isIndefinite,
        address _rewardToken,
        address _depositToken,
        uint32 _startTime,
        uint32 _streamDuration,
        uint32 _depositLockDuration,
        uint32 _rewardLockDuration,
        uint16 _feePercent,
        bool _feeEnabled
    )
        LockeERC20(_depositToken, _streamId, _startTime + _streamDuration)
        MinimallyExternallyGoverned(msg.sender) // inherit factory governance 
    {
        // No error code or msg to reduce bytecode size
        require(_rewardToken != _depositToken);
        // set fee info
        feePercent = _feePercent;
        feeEnabled = _feeEnabled;

        // limit feePercent
        require(feePercent < 10000);
    
        // store streamParams
        startTime = _startTime;
        streamDuration = _streamDuration;
        endStream = startTime + streamDuration;
        endDepositLock = endStream + _depositLockDuration;
        endRewardLock = startTime + _rewardLockDuration;
    
        // set tokens
        depositToken = _depositToken;
        rewardToken = _rewardToken;

        // set streamId
        streamId = _streamId;

        // set indefinite info
        isIndefinite = _isIndefinite;
    
        streamCreator = creator;

        depositDecimalsOne = uint112(10**ERC20(depositToken).decimals());

        // set lastUpdate to startTime to reduce codesize and first users gas
        lastUpdate = startTime;
    }

    /**
     * @dev Returns relevant internal token amounts
    **/
    function tokenAmounts() external view returns (uint112, uint112, uint112, uint112) {
        return (rewardTokenAmount, depositTokenAmount, rewardTokenFeeAmount, depositTokenFlashloanFeeAmount);
    }

    /**
     * @dev Returns fee parameters
    **/
    function feeParams() external view returns (uint16, bool) {
        return (feePercent, feeEnabled);
    }

    /**
     * @dev Returns stream parameters
    **/
    function streamParams() external view returns (uint32,uint32,uint32,uint32) {
        return (
            startTime,
            endStream,
            endDepositLock,
            endRewardLock
        );
    }

    function lastApplicableTime() internal view returns (uint32) {
        if (block.timestamp <= endStream) {
            if (block.timestamp <= startTime) {
                return startTime;
            } else {
                return uint32(block.timestamp);
            }
        } else {
            return endStream;
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalVirtualBalance == 0) {
            return cumulativeRewardPerToken;
        } else {
            // ∆time*rewardTokensPerSecond*oneDepositToken / totalVirtualBalance
            uint256 rewards;
            // Safety:
            //  1. lastApplicableTime has the same bounds as lastUpdate for minimum, current, and max
            //  2. lastApplicableTime() - lastUpdate guaranteed to be <= streamDuration
            //  3. streamDuration*rewardTokenAmount*depositDecimalOne is guaranteed to not overflow in `fundStream`
            //  4. streamDuration and totalVirtualBalance guaranteed to not be 0
            // NOTE: this causes rounding down. This leaves a bit of dust in the contract
            // because when we do rewardDelta calculation for users, its basically (currUnderestimateRPT - storedUnderestimateRPT) 
            unchecked {
                rewards = (uint256(lastApplicableTime() - lastUpdate) * rewardTokenAmount * depositDecimalsOne) / streamDuration / totalVirtualBalance;
            }
            return cumulativeRewardPerToken + rewards;
        }
    }

    function dilutedBalance(uint112 amount) internal view returns (uint256) {
        // duration / timeRemaining * amount
        uint32 timeRemaining;
        // Safety:
        //  1. dilutedBalance is only called in stake and _withdraw, which requires that time < endStream
        unchecked {
            timeRemaining = endStream - uint32(block.timestamp);
        }
        uint256 diluted = uint256(streamDuration) * amount / timeRemaining;

        // if amount is greater than diluted, the stream hasnt started yet
        return amount < diluted ? diluted : amount;
    }

    function getEarned(address who) external view returns (uint256) {
        TokenStream storage ts = tokenStreamForAccount[who];
        return earned(ts, rewardPerToken());
    }

    function earned(TokenStream storage ts, uint256 currCumRewardPerToken) internal view returns (uint112) {
        uint256 rewardDelta;
        // Safety:
        //  1. currCumRewardPerToken - ts.lastCumulativeRewardPerToken: currCumRewardPerToken will always be >= ts.lastCumulativeRewardPerToken
        unchecked { rewardDelta = currCumRewardPerToken - ts.lastCumulativeRewardPerToken; }

        // TODO: Think more about the bounds on ts.virtualBalance. This mul may be able to be unchecked?
        // NOTE: This can cause small rounding issues that will leave dust in the contract
        uint112 reward = uint112(ts.virtualBalance * rewardDelta / depositDecimalsOne);
        return reward + ts.rewards;
    }

    /**
     * @dev Allows _anyone_ to fund this stream, if its before the stream start time
    **/
    function fundStream(uint112 amount) external lock {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp >= startTime) revert NotBeforeStream();

        // transfer from sender
        uint256 prevBal = ERC20(rewardToken).balanceOf(address(this));
        ERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(rewardToken).balanceOf(address(this));
        if (newBal > type(uint112).max || newBal <= prevBal) revert BadERC20Interaction();

        uint256 amt;
        // Safety:
        //  1. newBal already checked above
        unchecked {
            amt = newBal - prevBal;
        }

        // if fee is enabled, take a fee
        if (feeEnabled) {
            // Safety:
            //  1. amt is u256 but max possible value is 2**112, so cannot overflow when multiplying
            //  2. amt is guaranteed to be greater than feeAmt
            uint256 feeAmt;
            unchecked {
                feeAmt = amt * feePercent / 10000; 
                amt = amt - feeAmt;
            }

            // since this operation can be repeated, we cannot assume no overflow so use checked math
            // downcast is safe because (x*y)/MAX_X is guaranteed to be smaller than y which is at most uint112
            rewardTokenFeeAmount += uint112(feeAmt);
            rewardTokenAmount += uint112(amt);
        } else {
            // downcast is safe as we already ensure < 2**112
            rewardTokenAmount += uint112(amt);
        }

        // protect against rewardPerToken overflow revert
        // this will revert with overflow if it would cause `rewardPerToken` to revert
        uint256 _safeAmtCheck_ = uint256(streamDuration) * rewardTokenAmount * depositDecimalsOne;
        
        emit StreamFunded(amt);
    }

    /**
     *  @dev Deposits depositTokens into this stream
     * 
     *  additionally, updates tokenStreamForAccount
    */ 
    function stake(uint112 amount) external virtual lock updateStream {
        _stake(amount);
    }

    function _stake(uint112 amount) internal {
        if (amount == 0) revert ZeroAmount();

        // checked in updateStream
        // require(block.timestamp < endStream, "stake:!stream");

        // transfer tokens over
        uint256 prevBal = ERC20(depositToken).balanceOf(address(this));
        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(depositToken).balanceOf(address(this));
        if (newBal > type(uint112).max || newBal <= prevBal) revert BadERC20Interaction();
        

        uint112 trueDepositAmt;
        // Safety:
        //  1. we already ensured newBal > prevBal
        unchecked {
            trueDepositAmt = uint112(newBal - prevBal);
        }

        depositTokenAmount += trueDepositAmt;

        TokenStream storage ts = tokenStreamForAccount[msg.sender];
        ts.tokens += trueDepositAmt;

        uint256 virtualBal = dilutedBalance(trueDepositAmt);
        ts.virtualBalance += virtualBal;
        totalVirtualBalance += virtualBal;
        unstreamed += trueDepositAmt;

        if (!isIndefinite) {
            // not indefinite, so give the user some receipt tokens
            _mint(msg.sender, trueDepositAmt);
        }

        emit Staked(msg.sender, trueDepositAmt);
    }

    /**
     *  @dev Allows a stream depositor to withdraw a specific amount of depositTokens during a stream,
     *  up to their tokenStreamForAccount amount
     * 
     *  additionally, updates tokenStreamForAccount
    */ 
    function withdraw(uint112 amount) external lock updateStream {
        TokenStream storage ts = tokenStreamForAccount[msg.sender];
        if (ts.tokens < amount) revert BalanceError();
        _withdraw(amount, ts);
    }

    function _withdraw(uint112 amount, TokenStream storage ts) internal {
        if (amount == 0) revert ZeroAmount();

        ts.tokens -= amount;

        uint256 virtualBal = dilutedBalance(amount);
        uint256 currVbal = ts.virtualBalance;


        // saturating subtraction - this is to account for
        // small rounding errors induced by small durations
        if (currVbal < virtualBal) {
            // if we zero out virtual balance, force the user to take
            // the remaining tokens back
            ts.virtualBalance = 0;
            amount += ts.tokens;
            ts.tokens = 0;
            totalVirtualBalance -= currVbal;
        } else {
            ts.virtualBalance -= virtualBal;
            totalVirtualBalance -= virtualBal;
        }
        
        depositTokenAmount -= amount;

        // Given how we calculate an individual's tokens vs global unstreamed tokens,
        // there can be rounding such that these are slightly off from each other
        // in that case, just do saturating subtraction
        if (amount > unstreamed) {
            unstreamed = 0;
        } else {
            unstreamed -= amount;
        }
        
        if (!isIndefinite) {
            _burn(msg.sender, amount);
        }

        // do the transfer
        ERC20(depositToken).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     *  @dev Allows a stream depositor to exit their entire remaining tokens that haven't streamed
     *  and burns receiptTokens if its not an indefinite lock.
     * 
     *  additionally, updates tokenStreamForAccount
    */ 
    function exit() external lock updateStream {
        // checked in updateStream
        // is the stream still going on? thats the only time a depositer can withdraw
        // require(block.timestamp < endStream, "withdraw:!stream");
        TokenStream storage ts = tokenStreamForAccount[msg.sender];
        uint112 amount = ts.tokens;
        _withdraw(amount, ts);
    }

    /**
     *  @dev Allows anyone to incentivize this stream with extra tokens
     *  and requires the incentive to not be the reward or deposit token
    */ 
    function createIncentive(address token, uint112 amount) external lock {
        if (token == rewardToken || token == depositToken) revert BadERC20Interaction();
        if (amount == 0) revert ZeroAmount();
        
        uint256 prevBal = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(token).balanceOf(address(this));
        if (newBal > type(uint112).max || newBal <= prevBal) revert BadERC20Interaction();

        uint112 amt = uint112(newBal - prevBal);
        Incentive storage incentive = incentives[token];
        if (!incentive.flag) { incentive.flag = true; }
        incentive.amt += amt;
        emit StreamIncentivized(token, amt);
    }

    /**
     *  @dev Allows the stream creator to claim an incentive once the stream is done
    */ 
    function claimIncentive(address token) external lock {
        // creator is claiming
        if (msg.sender != streamCreator) revert NotCreator();
        // stream ended
        if (block.timestamp < endStream) revert StreamOngoing();
        uint112 amount = incentives[token].amt;
        if (amount == 0) revert ZeroAmount();
        // we dont recent the incentive flag
        incentives[token].amt = 0;
        ERC20(token).safeTransfer(msg.sender, amount);
        emit StreamIncentiveClaimed(token, amount);
    }

    /**
     *  @dev Allows a receipt token holder to reclaim deposit tokens if the deposit lock is done & their receiptToken amount
     *  is greater than the requested amount
    */ 
    function claimDepositTokens(uint112 amount) external lock {
        if (isIndefinite) revert StreamTypeError();
        // NOTE: given that endDepositLock is strictly *after* the last time withdraw or exit is callable
        // we dont need to updateStream(msg.sender)
        if (amount == 0) revert ZeroAmount();

        // is the stream over + the deposit lock period over? thats the only time receiptTokens can be burned for depositTokens after stream is over
        if (block.timestamp <= endDepositLock) revert LockOngoing();

        // burn the receiptTokens
        _burn(msg.sender, amount);

        redeemedDepositTokens += amount;

        // send the receipt token holder back the funds
        ERC20(depositToken).safeTransfer(msg.sender, amount);

        emit DepositTokensReclaimed(msg.sender, amount);
    }

    /**
     *  @dev Allows an original depositor to claim their rewardTokens
    */ 
    function claimReward() external lock {
        if (block.timestamp < endRewardLock) revert LockOngoing();
        
        emit StreamFunded(totalVirtualBalance);

        uint112 rewardAmt;
        if (block.timestamp < endStream) {
            updateStreamInternal();
            rewardAmt = tokenStreamForAccount[msg.sender].rewards;
            tokenStreamForAccount[msg.sender].rewards = 0;
        } else {
            TokenStream storage ts = tokenStreamForAccount[msg.sender];
            // accumulate reward per token info
            cumulativeRewardPerToken = rewardPerToken();

            // update user rewards
            rewardAmt = earned(ts, cumulativeRewardPerToken);

            // delete the user
            // if its indefinite, they have no more claim over any tokens in the pool
            // if its not, we use the receipt token balance for token claims and there is no
            // way to have any remaining rewards because the stream is over
            delete tokenStreamForAccount[msg.sender];


            // if we havent updated since endStream, update lastupdate and unaccrued seconds
            uint32 tdelta = lastApplicableTime() - lastUpdate;
            if (unstreamed == 0 && tdelta != 0) {
                unaccruedSeconds += tdelta;
            }

            lastUpdate = lastApplicableTime(); 
        }

        if (rewardAmt == 0) revert ZeroAmount();

        redeemedRewardTokens += rewardAmt;

        // transfer the tokens
        ERC20(rewardToken).safeTransfer(msg.sender, rewardAmt);

        emit RewardsClaimed(msg.sender, rewardAmt);
    }

    /**
     *  @dev Allows a creator to claim tokens if the stream has ended & this contract is indefinite
    */ 
    function creatorClaim(address destination) external lock {
        // only can claim once
        if (claimedDepositTokens) revert BalanceError();
        // creator is claiming
        if (msg.sender != streamCreator) revert NotCreator();
        // stream ended
        if (block.timestamp < endStream) revert StreamOngoing();

        uint32 tdelta = lastApplicableTime() - lastUpdate;
        if (unstreamed == 0 && tdelta != 0) {
            unaccruedSeconds += tdelta;
            lastUpdate = lastApplicableTime();
        }

        // handle unaccounted for reward tokens
        uint256 actualStreamedTime = uint256(streamDuration - unaccruedSeconds);
        uint256 actualRewards = actualStreamedTime * rewardTokenAmount / streamDuration;
        uint256 totalRewardTokenNotGiven = rewardTokenAmount - actualRewards;
        emit StreamFunded(unaccruedSeconds);
        emit StreamFunded(actualRewards);
        emit StreamFunded(rewardTokenAmount);
        if (totalRewardTokenNotGiven > 0) {
            ERC20(rewardToken).safeTransfer(streamCreator, totalRewardTokenNotGiven);
        }

        claimedDepositTokens = true;

        // can only claim when its an indefinite lockup
        if (isIndefinite) {
            uint112 amount = depositTokenAmount;
            redeemedDepositTokens = amount;

            ERC20(depositToken).safeTransfer(destination, amount);

            emit TokensClaimed(destination, amount);
        }
    }

    /**
     *  @dev Allows the governance contract of the factory to select a destination
     *  and transfer fees (in rewardTokens) to that address totaling the total fee amount
    */ 
    function claimFees(address destination) external lock externallyGoverned {
        // Stream is done
        if (block.timestamp < endStream) revert StreamOngoing();

        // reset fee amount
        uint112 fees = rewardTokenFeeAmount;
        if (fees > 0) {
            rewardTokenFeeAmount = 0;

            // transfer and emit event
            ERC20(rewardToken).safeTransfer(destination, fees);
            emit FeesClaimed(rewardToken, destination, fees);
        }

        fees = depositTokenFlashloanFeeAmount;
        if (fees > 0) {
            depositTokenFlashloanFeeAmount = 0;

            // transfer and emit event
            ERC20(depositToken).safeTransfer(destination, fees);

            emit FeesClaimed(depositToken, destination, fees);
        }
        
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
    function recoverTokens(address token, address recipient) external lock {
        // NOTE: it is the stream creators responsibility to save
        // tokens on behalf of their users.
        if (msg.sender != streamCreator) revert NotCreator();
        if (token == depositToken) {
            if (block.timestamp <= endDepositLock) revert LockOngoing();
            // get the balance of this contract
            // check what isnt claimable by either party
            uint256 excess = ERC20(token).balanceOf(address(this)) - (depositTokenAmount - redeemedDepositTokens) - depositTokenFlashloanFeeAmount;
            // allow saving of the token
            ERC20(token).safeTransfer(recipient, excess);

            emit RecoveredTokens(token, recipient, excess);
            return;
        }
        
        if (token == rewardToken) {
            if (block.timestamp < endStream) revert StreamOngoing();
            // check current balance vs internal balance
            //
            // NOTE: if a token rebases, i.e. changes balance out from under us,
            // most of this contract breaks and rugs depositors. this isn't exclusive
            // to this function but this function would in theory allow someone to rug
            // and recover the excess (if it is worth anything)

            // check what isnt claimable by depositors and governance
            uint256 excess = ERC20(token).balanceOf(address(this)) - (rewardTokenAmount - redeemedRewardTokens + rewardTokenFeeAmount);
            ERC20(token).safeTransfer(recipient, excess);

            emit RecoveredTokens(token, recipient, excess);
            return;
        }

        if (incentives[token].amt > 0) {
            if (block.timestamp < endStream) revert StreamOngoing();
            uint256 excess = ERC20(token).balanceOf(address(this)) - incentives[token].amt;
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
    function flashloan(address token, address to, uint112 amount, bytes calldata data) external lock {
        if (token != depositToken && token != rewardToken) revert BadERC20Interaction();

        uint256 preTokenBalance = ERC20(token).balanceOf(address(this));

        ERC20(token).safeTransfer(to, amount);

        // the `to` contract should have a public function with the signature:
        // function lockeCall(address initiator, address token, uint256 amount, bytes memory data);
        LockeCallee(to).lockeCall(msg.sender, token, amount, data);

        uint256 postTokenBalance = ERC20(token).balanceOf(address(this));

        uint112 feeAmt = amount * 10 / 10000; // 10bps fee

        if (preTokenBalance + feeAmt > postTokenBalance) revert BalanceError();
        if (token == depositToken) {
            depositTokenFlashloanFeeAmount += feeAmt;
        } else {
            rewardTokenFeeAmount += feeAmt;
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
    function arbitraryCall(address who, bytes calldata data) external lock externallyGoverned {
        if (block.timestamp <= endStream + 30 days) {
            // cannot have had an active incentive for the callee
            // before the creator has had *ample* time to claim
            if (incentives[who].flag) revert StreamOngoing();
        }
        
        // cannot be to deposit token nor reward token
        if (who == depositToken || who == rewardToken) revert BadERC20Interaction();
        // cannot call transferFrom. This stops malicious governance
        // from being able to transfer from users' wallets that performed
        // `createIncentive`
        //
        // selector: bytes4(keccak256("transferFrom(address,address,uint256)"))
        if (bytes4(data[0:4]) == bytes4(0x23b872dd)) revert BadERC20Interaction();

        // get token balances
        uint256 preDepositTokenBalance = ERC20(depositToken).balanceOf(address(this));
        uint256 preRewardTokenBalance = ERC20(rewardToken).balanceOf(address(this));

        (bool success, bytes memory _ret) = who.call(data);
        require(success);

        // require no change in balances
        uint256 postDepositTokenBalance = ERC20(depositToken).balanceOf(address(this));
        uint256 postRewardTokenBalance = ERC20(rewardToken).balanceOf(address(this));
        if (preDepositTokenBalance != postDepositTokenBalance || preRewardTokenBalance != postRewardTokenBalance) revert BalanceError();
    }
}