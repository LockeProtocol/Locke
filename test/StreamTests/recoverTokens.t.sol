// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.t.sol";

contract TestRecovery is BaseTest {
    function setUp() public {
        tokenABC();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (startTime, endStream, endDepositLock, endRewardLock) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenA), 1 << 128);
        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
        writeBalanceOf(address(this), address(testTokenC), 1 << 128);
    }

    function test_recoverRevertRewardTime() public {
        testTokenA.transfer(address(stream), 100);
        vm.expectRevert(IStream.StreamOngoing.selector);
        stream.recoverTokens(address(testTokenA), address(this));
        checkState();
    }

    function test_recoverReward() public {
        testTokenA.transfer(address(stream), 100);
        vm.warp(endStream);
        stream.recoverTokens(address(testTokenA), address(this));
        checkState();
        assertEq(testTokenA.balanceOf(address(this)), 1 << 128);
    }

    function test_recoverRewardMinusRedeemed() public {
        testTokenA.approve(address(stream), 1000);
        stream.fundStream(1000);
        checkState();

        testTokenB.approve(address(stream), 1);
        stream.stake(1);
        checkState();

        testTokenA.transfer(address(stream), 100);
        vm.warp(endStream);

        stream.claimReward();
        checkState();

        stream.recoverTokens(address(testTokenA), address(this));
        checkState();
        assertEq(testTokenA.balanceOf(address(this)), 1 << 128);
    }
}
