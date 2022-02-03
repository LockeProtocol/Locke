pragma solidity 0.8.11;

import "../utils/LockeTest.sol";

contract TestArbitraryCall is BaseTest {
    function setUp() public {
        tokenABC();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration
        ) = stream.streamParams();
        endStream = startTime + streamDuration;
        endDepositLock = endStream + depositLockDuration;

        writeBalanceOf(address(this), address(testTokenC), 1<<128);
    }

    function test_arbitraryCallIncRevert() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);
        vm.expectRevert(Stream.StreamOngoing.selector);
        stream.arbitraryCall(address(testTokenC), "");
    }

    function test_arbitraryCallIncCall() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);
        
        vm.warp(endStream + 30 days + 1);
        uint256 preBal = testTokenC.balanceOf(address(this));
        stream.arbitraryCall(address(testTokenC), abi.encodeWithSignature("transfer(address,uint256)", address(this), 100));
    }

    function test_arbitraryCallGovRevert() public {
        vm.prank(bob);
        vm.expectRevert(MinimallyGoverned.NotGov.selector);
        stream.arbitraryCall(address(1), "");
    }

    function test_arbitraryCallTokenRevert() public {
        vm.expectRevert(Stream.BadERC20Interaction.selector);
        stream.arbitraryCall(address(testTokenA), "");

        vm.expectRevert(Stream.BadERC20Interaction.selector);
        stream.arbitraryCall(address(testTokenB), "");
    }

    function test_arbitraryCallTransferRevert() public {
        vm.expectRevert(Stream.BadERC20Interaction.selector);
        stream.arbitraryCall(address(testTokenC), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), address(this), 100000));
    }
}