pragma solidity 0.8.11;

import "../utils/LockeTest.sol";

contract TestRecovery is BaseTest {
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

        writeBalanceOf(address(this), address(testTokenA), 1<<128);
        writeBalanceOf(address(this), address(testTokenB), 1<<128);
        writeBalanceOf(address(this), address(testTokenC), 1<<128);
    }

    function test_recoverRevertRewardTime() public {
        testTokenA.transfer(address(stream), 100);
        vm.expectRevert(Stream.StreamOngoing.selector);
        stream.recoverTokens(address(testTokenA), address(this));
    }

    function test_recoverReward() public {
        testTokenA.transfer(address(stream), 100);
        vm.warp(endStream);
        stream.recoverTokens(address(testTokenA), address(this));
        assertEq(testTokenA.balanceOf(address(this)), 1<<128);
    }

    function test_recoverRewardMinusRedeemed() public {
        testTokenA.approve(address(stream), 1000);
        stream.fundStream(1000);

        testTokenB.approve(address(stream), 1);
        stream.stake(1);

        testTokenA.transfer(address(stream), 100);
        vm.warp(endStream);

        stream.claimReward();

        stream.recoverTokens(address(testTokenA), address(this));
        assertEq(testTokenA.balanceOf(address(this)), 1<<128);
    }
}