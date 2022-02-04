// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import "../utils/LockeTest.sol";

contract TestDeposit is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);

        (
            startTime,
            endStream,
            endDepositLock,
            endRewardLock
        ) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenB), 1<<128);
    }

    function test_claimDepositIndefiniteRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);
        vm.warp(endDepositLock);
        vm.expectRevert(IStream.StreamTypeError.selector);
        indefinite.claimDepositTokens(100);
    }

    function test_claimDepositAmtRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.warp(endDepositLock);
        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.claimDepositTokens(0);
    }

    function test_claimDepositLockRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        vm.expectRevert(IStream.LockOngoing.selector);
        stream.claimDepositTokens(100);
    }

    function test_claimDeposit() public {
        testTokenB.approve(address(stream), 105);
        stream.stake(105);

        vm.warp(endDepositLock + 1);

        uint256 preBal = testTokenB.balanceOf(address(this));


        stream.claimDepositTokens(100);
        
        ILockeERC20 asLERC = ILockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 5);

        uint256 redeemed = uint256(vm.load(address(stream), bytes32(uint256(10)))) >> 112;
        assertEq(redeemed, 100);

        assertEq(testTokenB.balanceOf(address(this)), preBal + 100);



        stream.claimDepositTokens(5);
    }
}