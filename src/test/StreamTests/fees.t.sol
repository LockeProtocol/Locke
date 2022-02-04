// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import "../utils/LockeTest.sol";
import "../../interfaces/IStreamFactory.sol";
import "../../interfaces/IMinimallyGoverned.sol";

contract TestFees is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);
        defaultStreamFactory.updateFeeParams(IStreamFactory.GovernableFeeParams({
            feePercent: 100,
            feeEnabled: true
        }));
        fee = streamSetupIndefinite(block.timestamp + minStartDelay);

        (
            startTime,
            endStream,
            endDepositLock,
            endRewardLock
        ) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenA), 1<<128);
        writeBalanceOf(address(this), address(testTokenB), 1<<128);
    }

    function test_claimFeesStreamRevert() public {
        vm.expectRevert(IStream.StreamOngoing.selector);
        stream.claimFees(address(this));
    }

    function test_claimFeesGovRevert() public {
        vm.prank(bob);
        vm.expectRevert(IMinimallyGoverned.NotGov.selector);
        stream.claimFees(address(this));
    }


    function test_claimFeesReward() public {
        uint112 feeAmt = 13; // expected fee amt
        uint112 amt    = 1337;

        testTokenA.approve(address(fee), amt);
        fee.fundStream(amt);
        (, , uint112 rewardTokenFeeAmount, ) = fee.tokenAmounts();

        assertEq(rewardTokenFeeAmount, feeAmt);

        vm.warp(endStream);

        uint256 preBal = testTokenA.balanceOf(address(this));


        fee.claimFees(address(this));
        
        assertEq(testTokenA.balanceOf(address(this)), preBal + feeAmt);

        (, , rewardTokenFeeAmount, ) = fee.tokenAmounts();
        assertEq(rewardTokenFeeAmount, 0);
    }

    function test_claimFeesDeposit() public {
        uint112 amt    = 10**18;
        uint112 feeAmt = amt * 10 / 10000; // expected fee amt

        testTokenB.approve(address(fee), amt);
        fee.stake(amt);

        fee.flashloan(address(testTokenB), address(this), amt, abi.encode(true, testTokenB.balanceOf(address(this))));

        vm.warp(endStream);
        uint256 preBal = testTokenB.balanceOf(address(this));

        fee.claimFees(address(this));
        
        assertEq(testTokenB.balanceOf(address(this)), preBal + feeAmt);
        (, , , uint112 depositTokenFees) = fee.tokenAmounts();
        assertEq(depositTokenFees, 0);
    }

    function test_claimFeesBoth() public {        
        uint112 feeAmt = 13; // expected fee amt
        uint112 amt    = 1337;

        testTokenA.approve(address(fee), amt);
        fee.fundStream(amt);
        (, , uint112 rewardTokenFeeAmount, ) = fee.tokenAmounts();

        assertEq(rewardTokenFeeAmount, feeAmt);


        uint112 amtDeposit    = 10**18;
        uint112 feeAmtDeposit = amtDeposit * 10 / 10000; // expected fee amt

        testTokenB.approve(address(fee), amtDeposit);
        fee.stake(amtDeposit);

        fee.flashloan(address(testTokenB), address(this), amtDeposit, abi.encode(true, testTokenB.balanceOf(address(this))));

        vm.warp(endStream);

        uint256 preBal = testTokenA.balanceOf(address(this));
        uint256 preBalDeposit = testTokenB.balanceOf(address(this));


        fee.claimFees(address(this));
        
        assertEq(testTokenA.balanceOf(address(this)), preBal + feeAmt);
        assertEq(testTokenB.balanceOf(address(this)), preBalDeposit + feeAmtDeposit);

        (, , rewardTokenFeeAmount, ) = fee.tokenAmounts();
        assertEq(rewardTokenFeeAmount, 0);

        (, , , uint112 depositTokenFees) = fee.tokenAmounts();
        assertEq(depositTokenFees, 0);
    }
}