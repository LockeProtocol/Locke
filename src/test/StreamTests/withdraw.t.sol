// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import "../utils/LockeTest.sol";
import "../../interfaces/ILockeERC20.sol";

contract TestWithdraw is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (startTime, endStream, endDepositLock, endRewardLock) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
    }

    function test_withdrawZeroRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.withdraw(0);
    }

    function test_withdrawBalanceRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.expectRevert(IStream.BalanceError.selector);
        stream.withdraw(105);
    }

    function test_withdraw() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        stream.withdraw(100);

        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 0);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount) = stream.tokenAmounts();
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

    function test_withdrawTimePassed() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        vm.warp(startTime + streamDuration / 2); // move to half done

        stream.withdraw(10);

        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 90);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 90);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 100 * 50 / 100 - 10);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 80);
            assertEq(rewards, 0);
            assertEq(tokens, 40);
            assertEq(lastUpdate, startTime + streamDuration / 2);
            assertTrue(!merkleAccess);
        }
    }
}
