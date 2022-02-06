// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./utils/LockeTest.sol";

contract Fuzz is BaseTest {
    function setUp() public {
        tokenABC();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (
            startTime,
            endStream,
            endDepositLock,
            endRewardLock
        ) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenA), type(uint112).max);
        writeBalanceOf(address(this), address(testTokenB), type(uint112).max);
        writeBalanceOf(address(this), address(testTokenC), type(uint256).max);

        writeBalanceOf(alice, address(testTokenB), type(uint96).max);
        writeBalanceOf(bob, address(testTokenB), type(uint96).max);
    }

    function bound(
        uint256 x,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256 result) {
        require(max >= min, "MAX_LESS_THAN_MIN");

        uint256 size = max - min;

        if (max != type(uint256).max) size++; // Make the max inclusive.
        if (size == 0) return min; // Using max would be equivalent as well.
        // Ensure max is inclusive in cases where x != 0 and max is at uint max.
        if (max == type(uint256).max && x != 0) x--; // Accounted for later.

        if (x < min) x += size * (((min - x) / size) + 1);
        result = min + ((x - min) % size);

        // Account for decrementing x to make max inclusive.
        if (max == type(uint256).max && x != 0) result++;
    }

    function randomAction(address who, uint112 amount, uint112 rewards, uint112 tokens) internal {
        if (block.timestamp % 5 == 0 && block.timestamp < endStream) {
            vm.startPrank(who);
            testTokenB.approve(address(stream), amount);
            stream.stake(amount);
            vm.stopPrank();
        } else if (block.timestamp % 5 == 1 && tokens > 0 && block.timestamp < endStream) {
            vm.prank(who);
            stream.exit();
        } else if (block.timestamp % 5 == 2 && rewards > 0 && block.timestamp > endRewardLock) {
            vm.prank(who);
            stream.claimReward();
        } else if (block.timestamp % 5 == 3 && tokens > 0 && block.timestamp < endStream) {
            uint112 amount = uint112(bound(amount, 1, lens.currDepositTokensNotYetStreamed(stream, who)));
            vm.prank(who);
            stream.withdraw(amount);
        } else if (block.timestamp % 5 == 4 && tokens > 0 && block.timestamp > endDepositLock) {
            uint256 max = bound(LockeERC20(address(stream)).balanceOf(who), 0, type(uint256).max);
            vm.prank(who);
            stream.claimDepositTokens(uint112(bound(amount, 1, max)));
        }
    }

    function willTakeAction(uint256 timestamp, address who, uint112 rewards, uint112 tokens) internal returns (bool) {
        if (timestamp % 5 == 0 && timestamp < endStream) {
            return true;
        } else if (timestamp % 5 == 1 && tokens > 0 && timestamp < endStream) {
            return true;
        } else if (timestamp % 5 == 2 && rewards > 0 && timestamp > endRewardLock) {
            return true;
        } else if (timestamp % 5 == 3 && tokens > 0 && timestamp < endStream) {
            return true;
        } else if (timestamp % 5 == 4 && tokens > 0 && timestamp > endDepositLock) {
            return true;
        }
        return false;
    }

    function testFuzz_recoverCorrect(
        uint112 amountA,
        uint112 amountB,
        uint256 fudgeAmtA,
        uint256 fudgeAmtB,
        uint256 fudgeAmtC
    ) public {
        writeBalanceOf(address(this), address(testTokenA), type(uint256).max);
        writeBalanceOf(address(this), address(testTokenB), type(uint256).max);
        amountA = uint112(bound(amountA, 1, type(uint112).max));
        amountB = uint112(bound(amountB, 1, type(uint112).max));

        testTokenA.approve(address(stream), amountA);
        stream.fundStream(amountA);

        testTokenB.approve(address(stream), amountB);
        stream.stake(amountB);

        testTokenA.transfer(address(stream), fudgeAmtA);
        testTokenB.transfer(address(stream), fudgeAmtB);
        testTokenC.transfer(address(stream), fudgeAmtC);

        vm.warp(endDepositLock + 1);
        stream.tokenStreamForAccount(address(this));
        stream.claimReward();
        stream.claimDepositTokens(amountB);
        stream.creatorClaim(address(this));

        stream.recoverTokens(address(testTokenA), address(this));
        stream.recoverTokens(address(testTokenB), address(this));
        stream.recoverTokens(address(testTokenC), address(this));

        // leave less than 0.01 tokens from rounding
        assertTrue(testTokenA.balanceOf(address(stream)) < 10**16);
        assertEq(testTokenB.balanceOf(address(this)), type(uint256).max);
        assertEq(testTokenC.balanceOf(address(this)), type(uint256).max);
    }

    function testFuzz_stake(
        uint32 predelay,
        uint112 amountB
    ) public {
        amountB = uint112(bound(amountB, 1, type(uint112).max));
        predelay = uint32(bound(predelay, 0, streamDuration - 1));
        vm.warp(startTime + predelay);

        uint256 timeRemaining;
        unchecked {
            timeRemaining = endStream - uint32(block.timestamp);
        }
        uint256 dilutedBal = dilutedBalance(amountB);

        testTokenB.approve(address(stream), amountB);
        stream.stake(amountB);

        (
            uint256 lastCumulativeRewardPerToken,
            uint256 virtualBalance,
            uint112 rewards,
            uint112 tokens,
            uint32 lastUpdate,
            bool merkleAccess
        ) = stream.tokenStreamForAccount(address(this));

        assertEq(lastCumulativeRewardPerToken, 0);
        assertEq(virtualBalance,               dilutedBal);
        assertEq(rewards,                      0);
        assertEq(tokens,                       amountB);
        assertEq(lastUpdate,                   startTime + predelay);
        assertTrue(!merkleAccess);
    }

    function testFuzz_exit(
        uint32 predelay,
        uint32 nextDelay,
        uint112 amountB
    ) public {
        vm.warp(startTime);
        amountB = uint112(bound(amountB, 1, type(uint112).max));
        predelay = uint32(bound(predelay, 0, streamDuration - 1));
        nextDelay = uint32(bound(nextDelay, predelay, streamDuration - 1));
        vm.warp(startTime + predelay);

        testTokenB.approve(address(stream), amountB);
        stream.stake(amountB);

        vm.warp(startTime + nextDelay);
        stream.exit();

        (
            uint256 lastCumulativeRewardPerToken,
            uint256 virtualBalance,
            uint112 rewards,
            uint112 tokens,
            uint32 lastUpdate,
            bool merkleAccess
        ) = stream.tokenStreamForAccount(address(this));

        assertEq(lastCumulativeRewardPerToken, 0);
        assertEq(virtualBalance,               0);
        assertEq(rewards,                      0);
        assertEq(tokens,                       0);
        assertEq(lastUpdate,                   startTime + nextDelay);
        assertTrue(!merkleAccess);
    }

    function dilutedBalance(uint112 amount) internal returns (uint256) {
        // duration / timeRemaining * amount
        uint32 timeRemaining;
        // Safety:
        //  1. dilutedBalance is only called in stake and _withdraw, which requires that time < endStream
        unchecked {
            timeRemaining = endStream - uint32(block.timestamp);
        }

        emit log_named_uint("time remaining", timeRemaining);

        uint256 diluted = uint256(streamDuration)* amount / timeRemaining;

        return amount < diluted ? diluted : amount;
    }

    function streamAccting(uint32 lu, uint112 amount) internal view returns (uint112) {
        uint32 acctTimeDelta = uint32(block.timestamp - lu);

        if (acctTimeDelta > 0) {
            // some time has passed since this user last interacted
            // update ts not yet streamed
            // downcast is safe as guaranteed to be a % of uint112
            if (amount > 0) {

                // Safety:
                //  1. acctTimeDelta * ts.tokens: acctTimeDelta is uint32, ts.tokens is uint112, cannot overflow uint256
                //  2. endStream - ts.lastUpdate: We are guaranteed to not update ts.lastUpdate after endStream
                //  3. streamAmt guaranteed to be a truncated (rounded down) % of ts.tokens
                uint112 streamAmt = uint112(uint256(acctTimeDelta) * amount / (endStream - lu));
                require(streamAmt != 0, "streamamt");
                amount -= streamAmt;

            }
        }

        return amount;
    }
}