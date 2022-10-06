// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.t.sol";
import "../../src/interfaces/ILockeERC20.sol";

contract TestExit is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);
        (startTime, endStream, endDepositLock, endRewardLock) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
        writeBalanceOf(address(this), address(testTokenA), 1 << 128);
        testTokenA.approve(address(stream), type(uint256).max);
        uint112 amt = 1337;
        stream.fundStream(amt);

        testTokenA.approve(address(indefinite), type(uint256).max);
        amt = 1337;
        indefinite.fundStream(amt);
    }

    function test_exitZeroRevert() public {
        testTokenB.approve(address(stream), 100);
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.exit();
        checkState();
    }

    function test_exit() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        checkState();

        stream.exit();
        checkState();

        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 0);
        (, uint112 depositTokenAmount) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 0);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint176 tokens,
                uint32 lastUpdate,
                bool merkleAccess,
                uint112 rewards
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
        checkState();

        vm.warp(startTime + streamDuration / 2); // move to half done

        stream.exit();
        checkState();

        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 50);
        (, uint112 depositTokenAmount) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 50);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint176 tokens,
                uint32 lastUpdate,
                bool merkleAccess,
                uint112 rewards
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 6681286111111111111);
            assertEq(virtualBalance, 0);
            assertEq(rewards, 668);
            assertEq(tokens, 0);
            assertEq(lastUpdate, startTime + streamDuration / 2);
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
        (, uint112 depositTokenAmount) = indefinite.tokenAmounts();
        assertEq(depositTokenAmount, 50);

        {
            uint112 unstreamed = indefinite.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint176 tokens,
                uint32 lastUpdate,
                bool merkleAccess,
                uint112 rewards
            ) = indefinite.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 6685000000000000000);
            assertEq(virtualBalance, 0);
            assertEq(rewards, 668);
            assertEq(tokens, 0);
            assertEq(lastUpdate, startTime + streamDuration / 2);
            assertTrue(!merkleAccess);
        }
    }
}
