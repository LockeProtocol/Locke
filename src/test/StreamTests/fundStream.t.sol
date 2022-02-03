pragma solidity 0.8.11;

import "./utils/LockeTest.sol";

contract TestFundStream is BaseTest {
    function setUp() public {
        tokenAB();

        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        defaultStreamFactory.updateFeeParams(StreamFactory.GovernableFeeParams({
            feePercent: 100,
            feeEnabled: true
        }));
        fee = streamSetup(block.timestamp + minStartDelay);
        writeBalanceOf(address(this), address(testTokenA), 1<<128);
    }

    function test_fundStreamZeroAmt() public {
        vm.expectRevert(Stream.ZeroAmount.selector);
        stream.fundStream(0);
    }

    function test_fundStreamFundAfterStart() public {
        vm.warp(block.timestamp + minStartDelay + minStreamDuration);
        vm.expectRevert(Stream.NotBeforeStream.selector);
        stream.fundStream(100);
    }

    function test_fundStreamNoFees() public {
        testTokenA.approve(address(stream), type(uint256).max);
        uint112 amt = 1337;


        stream.fundStream(amt);
                {
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount, ) = stream.tokenAmounts();
            assertEq(rewardTokenAmount, amt);
            assertEq(rewardTokenFeeAmount, 0);
            assertEq(testTokenA.balanceOf(address(stream)), amt);
        }
        

        // log gas usage for a second fund stream


        stream.fundStream(1337);
                {
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount, ) = stream.tokenAmounts();
            assertEq(rewardTokenAmount, 2*amt);
            assertEq(rewardTokenFeeAmount, 0);
            assertEq(testTokenA.balanceOf(address(stream)), 2*1337);
        }
    }

    function test_fundStreamFees() public {
        testTokenA.approve(address(fee), type(uint256).max);
        
        uint112 feeAmt = 13; // expected fee amt
        uint112 amt    = 1337;


        fee.fundStream(amt);
                {
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount, ) = fee.tokenAmounts();
            assertEq(rewardTokenAmount, amt - feeAmt);
            assertEq(rewardTokenFeeAmount, feeAmt);
            assertEq(testTokenA.balanceOf(address(fee)), 1337);
        }

        // log gas usage for a second fund stream


        fee.fundStream(amt);
        
        {
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount, ) = fee.tokenAmounts();
            assertEq(rewardTokenAmount, 2*(amt - feeAmt));
            assertEq(rewardTokenFeeAmount, 2*feeAmt);
            assertEq(testTokenA.balanceOf(address(fee)), 2*amt);
        }
    }
}