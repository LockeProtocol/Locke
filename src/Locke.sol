// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./LockeERC20.sol";
import "./SharedState.sol";

import "./interfaces/ILockeCallee.sol";
import "./interfaces/IStream.sol";

import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC20.sol";

// ====== Stream =====
contract Stream is LockeERC20, IStream {
    using SafeTransferLib for ERC20;

    // ======= Structs ========
    struct TokenStream {
        uint256 lastCumulativeRewardPerToken;
        uint256 virtualBalance;
        // tokens is amount (uint112) scaled by 10**18 (which fits in 2**64), so 112 + 64 == 176.
        uint176 tokens;
        uint32 lastUpdate;
        bool merkleAccess;
        uint112 rewards;
    }

    // ======= Storage ========
    // ==== Immutables =====
    /// @dev Stream start time
    uint32 private immutable startTime;
    /// @dev Length of stream
    uint32 private immutable streamDuration;

    /// @dev End of stream
    uint32 private immutable endStream;

    /// @dev End of deposit lock
    uint32 private immutable endDepositLock;

    /// @dev End of reward lock
    uint32 private immutable endRewardLock;

    /// @dev Reward token's address
    address public immutable override rewardToken;
    /// @dev Deposited token's address
    address public immutable override depositToken;

    /// @dev This stream's id
    uint64 public immutable override streamId;

    /// @dev If set, then users do not get their staked tokens back
    bool public immutable override isIndefinite;

    /// @dev The stream creator
    address public immutable override streamCreator;
    /// @dev Amount of tokens that is equal to one token
    uint112 private immutable depositDecimalsOne;
    // ============

    //  == sloc a ==
    /// @dev Internal reward token amount to be given to depositors
    uint112 private rewardTokenAmount;
    /// @dev Internal deposit token amount locked/to be claimable by stream creator
    uint112 private depositTokenAmount;
    // ============

    // == slot b ==
    /// @dev Accumulator for reward tokens allocated
    uint256 private cumulativeRewardPerToken;
    // ============

    // == slot c ==
    /// @dev Total virtual balance
    uint256 public totalVirtualBalance;
    // ============

    // == slot d ==
    /// @dev Unstreamed deposit tokens
    uint112 public unstreamed;
    /// @dev Total claimed deposit tokens (either by depositors or stream creator)
    uint112 public override redeemedDepositTokens;
    /// @dev Whether stream creator has claimed deposit tokens
    bool private claimedDepositTokens;
    /// @dev Reentrancy lock
    uint8 private unlocked = 1;
    // ============

    // == slot e ==
    /// @dev Number of reward tokens redeemed
    uint112 private redeemedRewardTokens;
    /// @dev Last time state was updated
    uint32 public override lastUpdate;
    /// @dev Number of seconds during the stream in which there were no depositors
    uint32 public unaccruedSeconds;
    // ============

    /// @dev Mapping of address to a User's state, including number of tokens not yet streamed over
    mapping(address => TokenStream) public override tokenStreamForAccount;

    struct Incentive {
        uint112 amt;
        bool flag;
    }

    /// @dev External incentives for the stream creator
    mapping(address => Incentive) public override incentives;

    // ======= Modifiers ========
    modifier updateStream() {
        // save bytecode space by making it a jump instead of inlining at cost of gas
        updateStreamInternal();
        _;
    }

    function updateStreamInternal() internal {
        if (block.timestamp >= endStream) {
            revert NotStream();
        }
        TokenStream storage ts = tokenStreamForAccount[msg.sender];

        if (block.timestamp < startTime) {
            if (ts.lastUpdate == 0) {
                ts.lastUpdate = startTime;
            }
        } else {
            // block.timestamp >= startTime

            // only do one cast
            //
            // Safety:
            //  1. Timestamp wont cross this point until Feb 7th, 2106.
            uint32 timestamp = uint32(block.timestamp);

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
                    if (ts.tokens > 0) {
                        // Safety:
                        //  1. endStream guaranteed to be greater than the current timestamp, see first line in this modifier
                        //  2. (endStream - timestamp) * ts.tokens: (endStream - timestamp) is uint32, ts.tokens is uint176, cannot overflow uint256
                        //  3. endStream - ts.lastUpdate: We are guaranteed to not update ts.lastUpdate after endStream
                        //  4. downcast is safe as we had a uint32 * uint176, which is uint208, followed by a division by a uint32, bringing us
                        //     back down to 176 max
                        ts.tokens = uint176(uint256(endStream - timestamp) * ts.tokens / (endStream - ts.lastUpdate));
                    }
                    ts.lastUpdate = timestamp;
                }

                // handle global unstreamed
                // Safety:
                //  1. timestamp - lastUpdate: lastUpdate is guaranteed to be <= current timestamp when timestamp >= startTime
                uint32 tdelta = timestamp - lastUpdate;
                // stream tokens over
                if (tdelta > 0) {
                    if (totalVirtualBalance == 0) {
                        // Safety:
                        //  1. Σ tdelta guaranteed to be < uint32.max because its upper bound is streamDuration which is a uint32
                        unaccruedSeconds += uint32(tdelta);
                    }
                    if (unstreamed > 0) {
                        // Safety:
                        //  1. tdelta*unstreamed: uint32 * uint112 guaranteed to fit into uint256 so no overflow or zeroed bits
                        //  2. endStream - lastUpdate: lastUpdate guaranteed to be less than endStream in this codepath
                        //  3. tdelta*unstreamed/(endStream - lastUpdate): guaranteed to be less than unstreamed as its a % of unstreamed
                        unstreamed = uint112(uint256(endStream - timestamp) * unstreamed / (endStream - lastUpdate));
                    }
                }

                // already ensure that blocktimestamp is less than endStream so guaranteed ok here
                lastUpdate = timestamp;
            }
        }
    }

    modifier lock() {
        if (unlocked != 1) {
            revert Reentrant();
        }
        unlocked = 2;
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
        uint32 _rewardLockDuration
    )
        LockeERC20(
            _depositToken,
            _streamId,
            _startTime + _streamDuration + _depositLockDuration,
            _startTime + _streamDuration,
            _isIndefinite
        )
    {
        // No error code or msg to reduce bytecode size
        require(_rewardToken != _depositToken);

        // store streamParams
        startTime = _startTime;
        streamDuration = _streamDuration;

        // set in shared state
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

        uint256 one = ERC20(depositToken).decimals();
        if (one > 33) revert BadERC20Interaction();

        unchecked {
            depositDecimalsOne = uint112(10 ** one);
        }

        // check reward token is sane
        if (ERC20(rewardToken).decimals() > 33) revert BadERC20Interaction();

        // set lastUpdate to startTime to reduce codesize and first users gas
        lastUpdate = startTime;
    }

    /**
     * @dev Returns relevant internal token amounts
     *
     */
    function tokenAmounts() external view override returns (uint112, uint112 /*, uint112, uint112*/ ) {
        return (rewardTokenAmount, depositTokenAmount);
    }

    /**
     * @dev Returns stream parameters
     *
     */
    function streamParams() external view override returns (uint32, uint32, uint32, uint32) {
        return (startTime, endStream, endDepositLock, endRewardLock);
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

    function rewardPerToken() public view override returns (uint256) {
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
                rewards = (uint256(lastApplicableTime() - lastUpdate) * rewardTokenAmount * depositDecimalsOne)
                    / streamDuration / (totalVirtualBalance / 10 ** 18);
            }
            return cumulativeRewardPerToken + rewards;
        }
    }

    function dilutedBalance(uint176 tokens_amount) internal view returns (uint256) {
        // duration / timeRemaining * amount
        uint32 timeRemaining;
        // Safety:
        //  1. dilutedBalance is only called in stake and _withdraw, which requires that time < endStream
        unchecked {
            timeRemaining = endStream - uint32(block.timestamp);
        }
        // stream duration is always guaranteed to be greater than timeRemaining
        // therefore diluted has a bounded minimum of 10**18, and by extension totalVirtualBalance cannot be lower than 10**18
        uint256 diluted = uint256(streamDuration) * tokens_amount / timeRemaining;

        // if amount is greater than diluted, the stream hasnt started yet
        return tokens_amount < diluted ? diluted : tokens_amount;
    }

    function getEarned(address who) external view override returns (uint256) {
        TokenStream storage ts = tokenStreamForAccount[who];
        return earned(ts, rewardPerToken());
    }

    function earned(TokenStream storage ts, uint256 currCumRewardPerToken) internal view returns (uint112) {
        uint256 rewardDelta;
        // Safety:
        //  1. currCumRewardPerToken - ts.lastCumulativeRewardPerToken: currCumRewardPerToken will always be >= ts.lastCumulativeRewardPerToken
        unchecked {
            rewardDelta = currCumRewardPerToken - ts.lastCumulativeRewardPerToken;
        }

        // TODO: Think more about the bounds on ts.virtualBalance. This mul may be able to be unchecked?
        // NOTE: This can cause small rounding issues that will leave dust in the contract
        uint112 reward = uint112(ts.virtualBalance * rewardDelta / depositDecimalsOne / 10 ** 18);
        return reward + ts.rewards;
    }

    /**
     * @dev Allows _anyone_ to fund this stream, if its before the stream start time
     *
     */
    function fundStream(uint112 amount) external override lock {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (block.timestamp >= startTime) {
            revert NotBeforeStream();
        }

        // transfer from sender
        uint256 prevBal = ERC20(rewardToken).balanceOf(address(this));
        ERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(rewardToken).balanceOf(address(this));
        if (newBal > type(uint112).max || newBal <= prevBal) {
            revert BadERC20Interaction();
        }

        uint256 amt;
        // Safety:
        //  1. newBal already checked above
        unchecked {
            amt = newBal - prevBal;
        }

        // downcast is safe as we already ensure < 2**112
        rewardTokenAmount += uint112(amt);

        // protect against rewardPerToken overflow revert
        // this will revert with overflow if it would cause `rewardPerToken` to revert
        uint256 _safeAmtCheck_ = uint256(streamDuration) * rewardTokenAmount * depositDecimalsOne;
        _safeAmtCheck_; // compiler shhh
        emit StreamFunded(amt);
    }

    /**
     * @dev Deposits depositTokens into this stream
     *
     * additionally, updates tokenStreamForAccount
     */
    function stake(uint112 amount) external virtual override lock updateStream {
        _stake(amount);
    }

    function _stake(uint112 amount) internal {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (rewardTokenAmount == 0) {
            revert NotFunded();
        }

        // checked in updateStream
        // require(block.timestamp < endStream, "stake:!stream");

        // transfer tokens over
        uint256 prevBal = ERC20(depositToken).balanceOf(address(this));
        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(depositToken).balanceOf(address(this));
        if (newBal > type(uint112).max || newBal <= prevBal) {
            revert BadERC20Interaction();
        }

        uint112 trueDepositAmt;
        // Safety:
        //  1. we already ensured newBal > prevBal
        unchecked {
            trueDepositAmt = uint112(newBal - prevBal);
        }

        depositTokenAmount += trueDepositAmt;

        uint176 tokensAmt = uint176(uint256(trueDepositAmt) * 10 ** 18);

        TokenStream storage ts = tokenStreamForAccount[msg.sender];
        ts.tokens += tokensAmt;

        uint256 virtualBal = dilutedBalance(tokensAmt);
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
     * @dev Allows a stream depositor to withdraw a specific amount of depositTokens during a stream,
     * up to their tokenStreamForAccount amount
     *
     * additionally, updates tokenStreamForAccount
     */
    function withdraw(uint112 amount) external override lock updateStream {
        TokenStream storage ts = tokenStreamForAccount[msg.sender];
        uint176 tokensAmt = uint176(uint256(amount) * 10 ** 18);
        if (ts.tokens < tokensAmt) {
            revert BalanceError();
        }

        _withdraw(tokensAmt, amount, ts);
    }

    function _withdraw(uint176 tokensAmt, uint112 amt, TokenStream storage ts) internal {
        if (tokensAmt == 0) {
            revert ZeroAmount();
        }

        ts.tokens -= tokensAmt;

        uint256 virtualBal = dilutedBalance(tokensAmt);
        uint256 currVbal = ts.virtualBalance;

        // saturating subtraction - this is to account for
        // small rounding errors induced by small durations
        if (currVbal < virtualBal || ts.tokens == 0) {
            // if we zero out virtual balance, force the user to take
            // the remaining tokens back
            ts.virtualBalance = 0;
            amt += uint112(ts.tokens / 10 ** 18);
            ts.tokens = 0;
            totalVirtualBalance -= currVbal;
        } else {
            ts.virtualBalance -= virtualBal;
            totalVirtualBalance -= virtualBal;
        }

        depositTokenAmount -= amt;

        // Given how we calculate an individual's tokens vs global unstreamed tokens,
        // there can be rounding such that these are slightly off from each other
        // in that case, just do saturating subtraction
        if (amt > unstreamed) {
            unstreamed = 0;
        } else {
            unstreamed -= amt;
        }

        if (!isIndefinite) {
            _burn(msg.sender, amt);
        }

        // do the transfer
        ERC20(depositToken).safeTransfer(msg.sender, amt);

        emit Withdrawn(msg.sender, amt);
    }

    /**
     * @dev Allows a stream depositor to exit their entire remaining tokens that haven't streamed
     * and burns receiptTokens if its not an indefinite lock.
     *
     * additionally, updates tokenStreamForAccount
     */
    function exit() external override lock updateStream {
        // checked in updateStream
        // is the stream still going on? thats the only time a depositer can withdraw
        // require(block.timestamp < endStream, "withdraw:!stream");
        TokenStream storage ts = tokenStreamForAccount[msg.sender];
        uint112 amount = uint112(ts.tokens / 10 ** 18);
        if (amount == 0) {
            revert ZeroAmount();
        }
        _withdraw(ts.tokens, amount, ts);
    }

    /**
     * @dev Allows anyone to incentivize this stream with extra tokens
     * and requires the incentive to not be the reward or deposit token
     */
    function createIncentive(address token, uint112 amount) external override lock {
        if (token == rewardToken || token == depositToken) {
            revert BadERC20Interaction();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 prevBal = ERC20(token).balanceOf(address(this));
        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 newBal = ERC20(token).balanceOf(address(this));
        if (newBal > type(uint112).max || newBal <= prevBal) {
            revert BadERC20Interaction();
        }

        uint112 amt;
        unchecked {
            amt = uint112(newBal - prevBal);
        }
        Incentive storage incentive = incentives[token];
        if (!incentive.flag) {
            incentive.flag = true;
        }
        incentive.amt += amt;
        emit StreamIncentivized(token, amt);
    }

    /**
     * @dev Allows the stream creator to claim an incentive once the stream is done
     */
    function claimIncentive(address token) external override lock {
        // creator is claiming
        if (msg.sender != streamCreator) {
            revert NotCreator();
        }
        // stream ended
        if (block.timestamp < endStream) {
            revert StreamOngoing();
        }
        uint112 amount = incentives[token].amt;
        if (amount == 0) {
            revert ZeroAmount();
        }
        // we dont reset the incentive flag
        incentives[token].amt = 0;
        ERC20(token).safeTransfer(msg.sender, amount);
        emit StreamIncentiveClaimed(token, amount);
    }

    /**
     * @dev Allows a receipt token holder to reclaim deposit tokens if the deposit lock is done & their receiptToken amount
     * is greater than the requested amount
     */
    function claimDepositTokens(uint112 amount) external override lock {
        if (isIndefinite) {
            revert StreamTypeError();
        }
        // NOTE: given that endDepositLock is strictly *after* the last time withdraw or exit is callable
        // we dont need to updateStream(msg.sender)
        if (amount == 0) {
            revert ZeroAmount();
        }

        // is the stream over + the deposit lock period over? thats the only time receiptTokens can be burned for depositTokens after stream is over
        if (block.timestamp <= endDepositLock) {
            revert LockOngoing();
        }

        // burn the receiptTokens
        _burn(msg.sender, amount);

        redeemedDepositTokens += amount;

        // send the receipt token holder back the funds
        ERC20(depositToken).safeTransfer(msg.sender, amount);

        emit DepositTokensReclaimed(msg.sender, amount);
    }

    /**
     * @dev Allows an original depositor to claim their rewardTokens
     */
    function claimReward() external override lock {
        if (block.timestamp < endRewardLock) {
            revert LockOngoing();
        }

        uint112 rewardAmt;
        if (block.timestamp < endStream) {
            updateStreamInternal();
            rewardAmt = tokenStreamForAccount[msg.sender].rewards;
            tokenStreamForAccount[msg.sender].rewards = 0;
        } else {
            TokenStream storage ts = tokenStreamForAccount[msg.sender];
            // accumulate reward per token info
            if (lastUpdate < endStream) {
                cumulativeRewardPerToken = rewardPerToken();
            }

            // update user rewards
            rewardAmt = earned(ts, cumulativeRewardPerToken);

            // delete the user
            // if its indefinite, they have no more claim over any tokens in the pool
            // if its not, we use the receipt token balance for token claims and there is no
            // way to have any remaining rewards because the stream is over
            delete tokenStreamForAccount[msg.sender];

            // if we havent updated since endStream, update lastupdate and unaccrued seconds
            uint32 tdelta = endStream - lastUpdate;
            if (totalVirtualBalance == 0 && tdelta != 0) {
                unaccruedSeconds += tdelta;
            }

            lastUpdate = endStream;
        }

        if (rewardAmt == 0) {
            revert ZeroAmount();
        }

        redeemedRewardTokens += rewardAmt;

        // transfer the tokens
        ERC20(rewardToken).safeTransfer(msg.sender, rewardAmt);

        emit RewardsClaimed(msg.sender, rewardAmt);
    }

    /**
     * @dev Allows a creator to claim tokens if the stream has ended & this contract is indefinite
     */
    function creatorClaim(address destination) external override lock {
        // only can claim once
        if (claimedDepositTokens) {
            revert CreatorClaimedError();
        }
        // creator is claiming
        if (msg.sender != streamCreator) {
            revert NotCreator();
        }
        // stream ended
        if (block.timestamp < endStream) {
            revert StreamOngoing();
        }

        uint32 tdelta = endStream - lastUpdate;
        if (tdelta != 0) {
            // make sure we update cumulative reward per token, so that `claimReward` is effecient & correct
            cumulativeRewardPerToken = rewardPerToken();

            // update unaccrued seconds
            if (totalVirtualBalance == 0) {
                unaccruedSeconds += tdelta;
            }

            // set last update to end of stream
            lastUpdate = endStream;
        }

        // handle unaccounted for reward tokens
        uint256 actualStreamedTime = uint256(streamDuration - unaccruedSeconds);
        uint256 actualRewards = actualStreamedTime * rewardTokenAmount / streamDuration;
        uint256 totalRewardTokenNotGiven = rewardTokenAmount - actualRewards;
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

    // ======== Non-protocol functions ========

    /**
     * @dev Allows the stream creator to save tokens
     * There are some limitations to this:
     * 1. if its deposit token:
     * - DepositLock is fully done
     * - There are excess deposit tokens (balance - depositTokenAmount)
     * 2. if its the reward token:
     * - RewardLock is fully done
     * - Excess defined as balance - (rewardTokenAmount + rewardTokenFeeAmount)
     * 3. if incentivized:
     * - excesss defined as bal - incentives[token]
     */
    function recoverTokens(address token, address recipient) external override lock {
        // NOTE: it is the stream creators responsibility to save
        // tokens on behalf of their users.
        if (msg.sender != streamCreator) {
            revert NotCreator();
        }
        if (token == depositToken) {
            if (block.timestamp <= endDepositLock) {
                revert LockOngoing();
            }
            // get the balance of this contract
            // check what isnt claimable by either party
            uint256 excess = ERC20(token).balanceOf(address(this)) - (depositTokenAmount - redeemedDepositTokens);
            // allow saving of the token
            ERC20(token).safeTransfer(recipient, excess);

            emit RecoveredTokens(token, recipient, excess);
            return;
        }

        if (token == rewardToken) {
            if (block.timestamp < endStream) {
                revert StreamOngoing();
            }
            // check current balance vs internal balance
            //
            // NOTE: if a token rebases, i.e. changes balance out from under us,
            // most of this contract breaks and rugs depositors. this isn't exclusive
            // to this function but this function would in theory allow someone to rug
            // and recover the excess (if it is worth anything)

            // check what isnt claimable by depositors and governance
            uint256 excess = ERC20(token).balanceOf(address(this)) - (rewardTokenAmount - redeemedRewardTokens);
            ERC20(token).safeTransfer(recipient, excess);

            emit RecoveredTokens(token, recipient, excess);
            return;
        }

        if (incentives[token].amt > 0) {
            if (block.timestamp < endStream) {
                revert StreamOngoing();
            }
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
     * @dev Allows anyone to flashloan reward or deposit token for free
     */
    function flashloan(address token, address to, uint112 amount, bytes calldata data) external override lock {
        if (token != depositToken && token != rewardToken) {
            revert BadERC20Interaction();
        }

        uint256 preTokenBalance = ERC20(token).balanceOf(address(this));

        ERC20(token).safeTransfer(to, amount);

        // the `to` contract should have a public function with the signature:
        // function lockeCall(address initiator, address token, uint256 amount, bytes memory data);
        ILockeCallee(to).lockeCall(msg.sender, token, amount, data);

        uint256 postTokenBalance = ERC20(token).balanceOf(address(this));

        // uint112 feeAmt = amount * 10 / 10000; // 10bps fee

        if (preTokenBalance > postTokenBalance) {
            revert BalanceError();
        }

        emit Flashloaned(token, msg.sender, amount);
    }
}
