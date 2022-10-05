// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.sol";
import "../../interfaces/ILockeERC20.sol";

contract TestWithdraw is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (startTime, endStream, endDepositLock, endRewardLock) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenA), 1 << 128);
        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
        testTokenA.approve(address(stream), type(uint256).max);
        uint112 amt = 1337;
        stream.fundStream(amt);
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

    function test_unstreamed() public {
        writeBalanceOf(alice, address(testTokenB), 1 << 128);
        writeBalanceOf(bob, address(testTokenB), 1 << 128);
        startTime = uint32(block.timestamp + minStartDelay);
        stream = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            8888,
            maxDepositLockDuration,
            0,
            false
        );
        // false,
        // bytes32(0)

        testTokenA.approve(address(stream), type(uint256).max);
        uint112 amt = 1337;
        stream.fundStream(amt);
        vm.label(address(stream), "Stream");

        vm.warp(startTime);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), type(uint256).max);
        stream.stake(1052);
        vm.stopPrank();

        checkState();

        vm.warp(startTime + 99);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), type(uint256).max);
        stream.stake(6733);
        vm.stopPrank();

        checkState();

        vm.warp(startTime + 136);
        vm.prank(alice);
        stream.exit();
        vm.prank(bob);
        stream.exit();

        checkState();

        assertEq(stream.unstreamed(), 1);
        assertEq(stream.totalVirtualBalance(), 0);
    }

    function test_withdraw() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        checkState();

        stream.withdraw(100);
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

    function test_withdrawTimePassed() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        checkState();

        vm.warp(startTime + streamDuration / 2); // move to half done

        stream.withdraw(10);
        checkState();

        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 90);
        (, uint112 depositTokenAmount) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 90);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 100 * 50 / 100 - 10);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint176 tokens,
                uint32 lastUpdate,
                bool merkleAccess,
                uint112 rewards
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 6685000000000000000);
            assertEq(virtualBalance, 80 * 10 ** 18);
            assertEq(rewards, 668);
            assertEq(tokens, 40 * 10 ** 18);
            assertEq(lastUpdate, startTime + streamDuration / 2);
            assertTrue(!merkleAccess);
        }
    }
}
