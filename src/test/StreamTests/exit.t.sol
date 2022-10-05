// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import "../utils/LockeTest.sol";
import "../../interfaces/ILockeERC20.sol";

contract TestExit is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);
        (startTime, endStream, endDepositLock, endRewardLock) =
            stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
    }

    function test_exitZeroRevert() public {
        testTokenB.approve(address(stream), 100);
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.exit();
    }

    function test_exit() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        stream.exit();

        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 0);
        (
            uint112 rewardTokenAmount,
            uint112 depositTokenAmount
        ) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 0);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 0);
            assertEq(rewards, 0);
            assertEq(tokens, 0);
            assertEq(lastUpdate, startTime);
            assertTrue(!merkleAccess);
        }
    }

    function test_exitTimePassed() public {
        vm.warp(startTime + 1);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        vm.warp(startTime + streamDuration / 2 + 1); // move to half done

        stream.exit();

        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 50);
        (
            uint112 rewardTokenAmount,
            uint112 depositTokenAmount
        ) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 50);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 0);
            assertEq(rewards, 0);
            assertEq(tokens, 0);
            assertEq(lastUpdate, startTime + streamDuration / 2 + 1);
            assertTrue(!merkleAccess);
        }
    }

    function test_exitTimePassedIndefinite() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.warp(startTime + streamDuration / 2); // move to half done

        indefinite.exit();

        ILockeERC20 asLERC = ILockeERC20(indefinite);
        assertEq(asLERC.balanceOf(address(this)), 0);
        (
            uint112 rewardTokenAmount,
            uint112 depositTokenAmount
        ) = indefinite.tokenAmounts();
        assertEq(depositTokenAmount, 50);

        {
            uint112 unstreamed = indefinite.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = indefinite.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 0);
            assertEq(rewards, 0);
            assertEq(tokens, 0);
            assertEq(lastUpdate, startTime + streamDuration / 2);
            assertTrue(!merkleAccess);
        }
    }
}
