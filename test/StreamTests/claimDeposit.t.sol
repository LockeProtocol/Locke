// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.t.sol";

contract TestDeposit is BaseTest {
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
        indefinite.fundStream(amt);
    }

    function test_claimDepositIndefiniteRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);
        checkState();

        vm.warp(endDepositLock);
        vm.expectRevert(IStream.StreamTypeError.selector);
        indefinite.claimDepositTokens(100);
        checkState();
    }

    function test_claimDepositAmtRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        checkState();

        vm.warp(endDepositLock);
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.claimDepositTokens(0);
        checkState();
    }

    function test_claimDepositLockRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        checkState();

        stream.maturity();
        vm.expectRevert(IStream.LockOngoing.selector);
        stream.claimDepositTokens(100);
        checkState();
    }

    function test_claimDeposit() public {
        testTokenB.approve(address(stream), 105);
        stream.stake(105);
        checkState();

        ILockeERC20 asLERC = ILockeERC20(stream);
        vm.expectRevert(ILockeERC20.NotTransferableYet.selector);
        asLERC.transfer(address(1), 1);
        assertEq(asLERC.balanceOf(address(this)), 105);

        vm.warp(endDepositLock + 1);

        uint256 preBal = testTokenB.balanceOf(address(this));

        stream.claimDepositTokens(100);
        checkState();

        asLERC.transfer(address(1), 1);
        assertEq(asLERC.balanceOf(address(this)), 4);

        // uint256 redeemed =
        //     uint256(vm.load(address(stream), bytes32(uint256(9)))) >> 112;
        uint256 redeemed = (uint256(vm.load(address(stream), bytes32(uint256(9)))) << 32) >> (112 + 32);
        assertEq(redeemed, 100);

        assertEq(testTokenB.balanceOf(address(this)), preBal + 100);

        stream.claimDepositTokens(4);
        checkState();
    }
}
