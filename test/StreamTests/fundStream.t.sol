// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.t.sol";
import "../../src/interfaces/IStreamFactory.sol";

contract TestFundStream is BaseTest {
    function setUp() public {
        tokenAB();

        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        writeBalanceOf(address(this), address(testTokenA), 1 << 128);
    }

    function test_fundStreamZeroAmt() public {
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.fundStream(0);
        checkState();
    }

    function test_fundStreamFundAfterStart() public {
        vm.warp(block.timestamp + minStartDelay + minStreamDuration);
        vm.expectRevert(IStream.NotBeforeStream.selector);
        stream.fundStream(100);
        checkState();
    }

    function test_fundStreamNoFees() public {
        testTokenA.approve(address(stream), type(uint256).max);
        uint112 amt = 1337;

        stream.fundStream(amt);
        checkState();
        {
            (uint112 rewardTokenAmount,) = stream.tokenAmounts();
            assertEq(rewardTokenAmount, amt);
            assertEq(testTokenA.balanceOf(address(stream)), amt);
        }

        // log gas usage for a second fund stream

        stream.fundStream(1337);
        checkState();
        {
            (uint112 rewardTokenAmount,) = stream.tokenAmounts();
            assertEq(rewardTokenAmount, 2 * amt);
            assertEq(testTokenA.balanceOf(address(stream)), 2 * 1337);
        }
    }
}
