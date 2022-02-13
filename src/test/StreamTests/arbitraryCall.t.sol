// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import "../utils/LockeTest.sol";
import "../../interfaces/IMinimallyGoverned.sol";

contract TestArbitraryCall is BaseTest {
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

        writeBalanceOf(address(this), address(testTokenC), 1<<128);
    }

    function test_arbitraryCallIncRevert() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);
        vm.expectRevert(IStream.StreamOngoing.selector);
        stream.arbitraryCall(address(testTokenC), "");
    }

    function test_arbitraryCallIncCall() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);
        checkState();
        vm.warp(endStream + 30 days + 1);
        uint256 preBal = testTokenC.balanceOf(address(this));
        stream.arbitraryCall(address(testTokenC), abi.encodeWithSignature("transfer(address,uint256)", address(this), 100));
        checkState();
    }

    function test_arbitraryCallGovRevert() public {
        vm.prank(bob);
        vm.expectRevert(IMinimallyGoverned.NotGov.selector);
        stream.arbitraryCall(address(1), "");
    }

    function test_arbitraryCallTokenRevert() public {
        vm.expectRevert(IStream.BadERC20Interaction.selector);
        stream.arbitraryCall(address(testTokenA), "");

        vm.expectRevert(IStream.BadERC20Interaction.selector);
        stream.arbitraryCall(address(testTokenB), "");
    }

    function test_arbitraryCallTransferRevert() public {
        vm.expectRevert(IStream.BadERC20Interaction.selector);
        stream.arbitraryCall(address(testTokenC), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), address(this), 100000));
    }
}