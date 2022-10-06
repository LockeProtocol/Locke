// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.t.sol";
import "../../src/interfaces/ILockeERC20.sol";

contract TestStake is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (startTime, endStream, endDepositLock, endRewardLock) = stream.streamParams();
        streamDuration = endStream - startTime;

        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);
        writeBalanceOf(address(this), address(testTokenA), 1 << 128);
        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
        writeBalanceOf(alice, address(testTokenB), 1 << 128);
        writeBalanceOf(bob, address(testTokenB), 1 << 128);
    }

    function test_multiUserStakeRewards() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);
        checkState();

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);

        stream.stake(100);
        vm.stopPrank();
        checkState();

        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);

        stream.stake(100);
        vm.stopPrank();
        checkState();

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream

        vm.prank(alice);

        stream.claimReward();
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 500);
        checkState();

        vm.prank(bob);

        stream.claimReward();
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 500); // we leave dust :shrug:
        checkState();
    }

    function test_multiUserStakeRewardsHalf() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);
        checkState();

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();
        checkState();

        vm.warp(startTime + minStreamDuration / 2); // move to half done

        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();
        checkState();

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream

        vm.prank(alice);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 666);
        checkState();

        vm.prank(bob);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 333); // we leave dust :shrug:
        checkState();
    }

    function test_multiUserStakeRewardsWithWithdraw() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);
        checkState();

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();
        checkState();

        vm.warp(startTime + minStreamDuration / 2); // move to half done

        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();
        checkState();

        vm.warp(startTime + minStreamDuration / 2 + minStreamDuration / 10);

        vm.prank(alice);

        stream.exit();
        checkState();

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream

        vm.prank(alice);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 533);
        checkState();

        vm.prank(bob);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 466);
        checkState();
    }

    function test_stakeAmtRevert() public {
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.stake(0);
    }

    function test_stakeTimeRevert() public {
        vm.warp(endStream);
        vm.expectRevert(IStream.NotStream.selector);
        stream.stake(100);
        checkState();
    }

    function test_stakeERCRevert() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);
        checkState();

        vm.warp(block.timestamp + minStartDelay);
        writeBalanceOf(address(stream), address(testTokenB), 2 ** 112 + 1);

        testTokenB.approve(address(stream), 100);
        vm.expectRevert(IStream.BadERC20Interaction.selector);
        stream.stake(100);
        checkState();
    }

    function test_stakeNoMerkle() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);
        checkState();
        testTokenB.approve(address(stream), 102);

        stream.stake(100);
        checkState();
        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 100);
        (, uint112 depositTokenAmount) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 100);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 100);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint176 tokens,
                uint32 lastUpdate,
                bool merkleAccess,
                uint112 rewards
            ) = stream.tokenStreamForAccount(address(this));
            checkState();
            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 100 * 10 ** 18);
            assertEq(rewards, 0);
            assertEq(tokens, 100 * 10 ** 18);
            assertEq(lastUpdate, startTime);
            assertTrue(!merkleAccess);
        }

        // move forward 1/10th of sd
        // round up to next second
        vm.warp(startTime + minStreamDuration / 10 + 1);
        uint256 rewardPerToken = stream.rewardPerToken();

        stream.stake(1);
        checkState();

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 90, "unstreamed");

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint176 tokens,
                uint32 lastUpdate,
                bool merkleAccess,
                uint112 rewards
            ) = stream.tokenStreamForAccount(address(this));

            checkState();
            assertEq(lastCumulativeRewardPerToken, rewardPerToken);
            assertEq(virtualBalance, 101111454152516208706);
            assertEq(rewards, 100);
            assertEq(tokens, 90972222222222222222);
            assertEq(lastUpdate, block.timestamp);
            assertTrue(!merkleAccess);
        }

        // move forward again
        vm.warp(startTime + (2 * minStreamDuration) / 10 + 1);
        rewardPerToken = stream.rewardPerToken();
        stream.stake(1);
        checkState();

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 80);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint176 tokens,
                uint32 lastUpdate,
                bool merkleAccess,
                uint112 rewards
            ) = stream.tokenStreamForAccount(address(this));

            checkState();
            assertEq(lastCumulativeRewardPerToken, rewardPerToken);
            assertEq(virtualBalance, 102361888331050421974);
            assertEq(rewards, 200);
            assertEq(tokens, 81861076806970601351);
            assertEq(lastUpdate, block.timestamp);
            assertTrue(!merkleAccess);
        }
    }

    function test_stakeIndefiniteNoMerkle() public {
        testTokenA.approve(address(indefinite), type(uint256).max);
        indefinite.fundStream(1000);
        testTokenB.approve(address(indefinite), type(uint256).max);

        indefinite.stake(100);
        ILockeERC20 asLERC = ILockeERC20(indefinite);
        // no tokens wen indefinite
        assertEq(asLERC.balanceOf(address(this)), 0);

        (, uint112 depositTokenAmount) = indefinite.tokenAmounts();
        assertEq(depositTokenAmount, 100);
        {
            uint112 unstreamed = indefinite.unstreamed();
            assertEq(unstreamed, 100);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint176 tokens,
                uint32 lastUpdate,
                bool merkleAccess,
                uint112 rewards
            ) = indefinite.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 100 * 10 ** 18);
            assertEq(rewards, 0);
            assertEq(tokens, 100 * 10 ** 18);
            assertEq(lastUpdate, startTime);
            assertTrue(!merkleAccess);
        }

        indefinite.stake(100);
    }
}
