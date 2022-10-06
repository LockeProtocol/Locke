// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.t.sol";

contract TestIncentive is BaseTest {
    function setUp() public {
        tokenABC();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);

        writeBalanceOf(address(this), address(testTokenC), 1 << 128);
    }

    function test_createIncentiveWithZeroAmt() public {
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.createIncentive(address(testTokenC), 0);
        checkState();
    }

    function test_createIncentiveWithToken() public {
        vm.expectRevert(IStream.BadERC20Interaction.selector);
        stream.createIncentive(address(testTokenA), 0);
        checkState();
    }

    function test_createIncentive() public {
        testTokenC.approve(address(stream), 100);

        stream.createIncentive(address(testTokenC), 100);
        checkState();
        (uint112 amt, bool flag) = stream.incentives(address(testTokenC));
        assertTrue(flag);
        assertEq(amt, 100);
    }

    function test_claimIncentiveCreatorRevert() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);
        checkState();

        vm.prank(alice);
        vm.expectRevert(IStream.NotCreator.selector);
        stream.claimIncentive(address(testTokenC));
        checkState();
    }

    function test_claimIncentiveStreamRevert() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);
        checkState();

        vm.expectRevert(IStream.StreamOngoing.selector);
        stream.claimIncentive(address(testTokenC));
        checkState();
    }

    function test_claimIncentiveAmt() public {
        vm.warp(block.timestamp + minStartDelay + minStreamDuration);
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.claimIncentive(address(testTokenC));
        checkState();
    }

    function test_claimIncentive() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);
        checkState();

        vm.warp(block.timestamp + minStartDelay + minStreamDuration);

        uint256 preBal = testTokenC.balanceOf(address(this));

        stream.claimIncentive(address(testTokenC));
        checkState();

        assertEq(testTokenC.balanceOf(address(this)), preBal + 100);
    }
}
