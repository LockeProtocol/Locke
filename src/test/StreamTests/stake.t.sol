// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import "../utils/LockeTest.sol";
import "../../interfaces/ILockeERC20.sol";

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

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);

        stream.stake(100);
        vm.stopPrank();

        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);

        stream.stake(100);
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream

        vm.prank(alice);

        stream.claimReward();
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 500);

        vm.prank(bob);

        stream.claimReward();
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 500); // we leave dust :shrug:
    }

    function test_multiUserStakeRewardsHalf() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration / 2); // move to half done

        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream

        vm.prank(alice);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 666);

        vm.prank(bob);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 333); // we leave dust :shrug:
    }

    function test_multiUserStakeRewardsWithWithdraw() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration / 2); // move to half done

        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration / 2 + minStreamDuration / 10);

        vm.prank(alice);

        stream.exit();

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream

        vm.prank(alice);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 533);

        vm.prank(bob);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 466);
    }

    function test_stakeAmtRevert() public {
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.stake(0);
    }

    function test_stakeTimeRevert() public {
        vm.warp(endStream);
        vm.expectRevert(IStream.NotStream.selector);
        stream.stake(100);
    }

    function test_stakeERCRevert() public {
        vm.warp(block.timestamp + minStartDelay);
        writeBalanceOf(address(stream), address(testTokenB), 2 ** 112 + 1);

        testTokenB.approve(address(stream), 100);
        vm.expectRevert(IStream.BadERC20Interaction.selector);
        stream.stake(100);
    }

    function test_stakeNoMerkle() public {
        testTokenB.approve(address(stream), 102);

        stream.stake(100);
        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 100);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 100);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 100);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));
            checkState();
            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 100);
            assertEq(rewards, 0);
            assertEq(tokens, 100);
            assertEq(lastUpdate, startTime);
            assertTrue(!merkleAccess);
        }

        // move forward 1/10th of sd
        // round up to next second
        vm.warp(startTime + minStreamDuration / 10 + 1);
        uint256 rewardPerToken = stream.rewardPerToken();

        stream.stake(1);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 91);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            checkState();
            assertEq(lastCumulativeRewardPerToken, rewardPerToken);
            assertEq(virtualBalance, 101);
            assertEq(rewards, 0);
            assertEq(tokens, 91);
            assertEq(lastUpdate, block.timestamp);
            assertTrue(!merkleAccess);
        }

        // move forward again
        vm.warp(startTime + (2 * minStreamDuration) / 10 + 1);
        rewardPerToken = stream.rewardPerToken();
        stream.stake(1);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 82);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            checkState();
            assertEq(lastCumulativeRewardPerToken, rewardPerToken);
            assertEq(virtualBalance, 102);
            assertEq(rewards, 0);
            assertEq(tokens, 82);
            assertEq(lastUpdate, block.timestamp);
            assertTrue(!merkleAccess);
        }
    }

    function test_stakeIndefiniteNoMerkle() public {
        testTokenB.approve(address(indefinite), type(uint256).max);

        indefinite.stake(100);
        ILockeERC20 asLERC = ILockeERC20(indefinite);
        // no tokens wen indefinite
        assertEq(asLERC.balanceOf(address(this)), 0);

        (uint112 rewardTokenAmount, uint112 depositTokenAmount) = indefinite.tokenAmounts();
        assertEq(depositTokenAmount, 100);
        {
            uint112 unstreamed = indefinite.unstreamed();
            assertEq(unstreamed, 100);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = indefinite.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 100);
            assertEq(rewards, 0);
            assertEq(tokens, 100);
            assertEq(lastUpdate, startTime);
            assertTrue(!merkleAccess);
        }

        indefinite.stake(100);
    }
}
