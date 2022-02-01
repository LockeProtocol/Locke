// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

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
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        stream.fundStream(0);
    }

    function test_fundStreamFundAfterStart() public {
        vm.warp(block.timestamp + minStartDelay + minStreamDuration);
        vm.expectRevert(abi.encodeWithSignature("NotBeforeStream()"));
        stream.fundStream(100);
    }

    function test_fundStreamNoFees() public {
        testTokenA.approve(address(stream), type(uint256).max);
        uint112 amt = 1337;

        uint256 gas_left = gasleft();
        stream.fundStream(amt);
        emit_log_named_uint(Color.Cyan, "gas_fundStream:         cold_no_fee", gas_left - gasleft());
        {
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount, ) = stream.tokenAmounts();
            assertEq(rewardTokenAmount, amt);
            assertEq(rewardTokenFeeAmount, 0);
            assertEq(testTokenA.balanceOf(address(stream)), amt);
        }
        

        // log gas usage for a second fund stream
        gas_left = gasleft();
        stream.fundStream(1337);
        emit_log_named_uint(Color.Cyan, "gas_fundStream: warm_nonzero_no_fee", gas_left - gasleft());
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

        uint256 gas_left = gasleft();
        fee.fundStream(amt);
        emit_log_named_uint(Color.Cyan, "gas_fundStream:         cold", gas_left - gasleft());
        {
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount, ) = fee.tokenAmounts();
            assertEq(rewardTokenAmount, amt - feeAmt);
            assertEq(rewardTokenFeeAmount, feeAmt);
            assertEq(testTokenA.balanceOf(address(fee)), 1337);
        }

        // log gas usage for a second fund stream
        gas_left = gasleft();
        fee.fundStream(amt);
        emit_log_named_uint(Color.Cyan, "gas_fundStream: warm_nonzero", gas_left - gasleft());

        {
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount, ) = fee.tokenAmounts();
            assertEq(rewardTokenAmount, 2*(amt - feeAmt));
            assertEq(rewardTokenFeeAmount, 2*feeAmt);
            assertEq(testTokenA.balanceOf(address(fee)), 2*amt);
        }
    }
}

contract TestWithdraw is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration
        ) = stream.streamParams();

        writeBalanceOf(address(this), address(testTokenB), 1<<128);
    }

    function test_withdrawZeroRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        stream.withdraw(0);
    }

    function test_withdrawBalanceRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.expectRevert(abi.encodeWithSignature("BalanceError()"));
        stream.withdraw(105);
    }

    function test_withdraw() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        uint256 gas_left = gasleft();
        stream.withdraw(100);
        emit_log_named_uint(Color.Cyan, "gas_withdraw: cold", gas_left - gasleft());
        
        LockeERC20 asLERC = LockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 0);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount, ) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 0);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance,               0);
            assertEq(rewards,                      0);
            assertEq(tokens,                       0);
            assertEq(lastUpdate,                   startTime);
            assertTrue(!merkleAccess);
        }
    }

    function test_withdrawTimePassed() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        vm.warp(startTime + streamDuration / 2); // move to half done
        

        uint256 gas_left = gasleft();
        stream.withdraw(10);
        emit_log_named_uint(Color.Cyan, "gas_withdraw: cold", gas_left - gasleft());
        
        LockeERC20 asLERC = LockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 90);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount, ) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 90);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 100*50/100-10);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance,               80);
            assertEq(rewards,                      0);
            assertEq(tokens,                       40);
            assertEq(lastUpdate,                   startTime + streamDuration / 2);
            assertTrue(!merkleAccess);
        }
    }
}

contract TestExit is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);
        (
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration
        ) = stream.streamParams();

        writeBalanceOf(address(this), address(testTokenB), 1<<128);
    }

    function test_exitZeroRevert() public {
        testTokenB.approve(address(stream), 100);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        stream.exit();
    }

    function test_exit() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        uint256 gas_left = gasleft();
        stream.exit();
        emit_log_named_uint(Color.Cyan, "gas_exit: cold", gas_left - gasleft());
        
        LockeERC20 asLERC = LockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 0);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount, ) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 0);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance,               0);
            assertEq(rewards,                      0);
            assertEq(tokens,                       0);
            assertEq(lastUpdate,                   startTime);
            assertTrue(!merkleAccess);
        }
    }

    function test_exitTimePassed() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        vm.warp(startTime + streamDuration / 2); // move to half done
        

        uint256 gas_left = gasleft();
        stream.exit();
        emit_log_named_uint(Color.Cyan, "gas_withdraw: cold", gas_left - gasleft());
        
        LockeERC20 asLERC = LockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 50);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount, ) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 50);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance,               0);
            assertEq(rewards,                      0);
            assertEq(tokens,                       0);
            assertEq(lastUpdate,                   startTime + streamDuration / 2);
            assertTrue(!merkleAccess);
        }
    }

    function test_exitTimePassedIndefinite() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.warp(startTime + streamDuration / 2); // move to half done
        

        uint256 gas_left = gasleft();
        indefinite.exit();
        emit_log_named_uint(Color.Cyan, "gas_withdraw: cold", gas_left - gasleft());
        
        LockeERC20 asLERC = LockeERC20(indefinite);
        assertEq(asLERC.balanceOf(address(this)), 0);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount, ) = indefinite.tokenAmounts();
        assertEq(depositTokenAmount, 50);

        {
            uint112 unstreamed = indefinite.unstreamed();
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = indefinite.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance,               0);
            assertEq(rewards,                      0);
            assertEq(tokens,                       0);
            assertEq(lastUpdate,                   startTime + streamDuration / 2);
            assertTrue(!merkleAccess);
        }
    }
}

contract TestStake is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration
        ) = stream.streamParams();
        endStream = startTime+streamDuration;

        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);
        writeBalanceOf(address(this), address(testTokenA), 1<<128);
        writeBalanceOf(address(this), address(testTokenB), 1<<128);
        writeBalanceOf(alice, address(testTokenB), 1<<128);
        writeBalanceOf(bob, address(testTokenB), 1<<128);
    }

    function test_multiUserStakeRewards() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);
        uint256 gas_left = gasleft();
        stream.stake(100);
        emit_log_named_uint(Color.Cyan, "gas_stake:         cold", gas_left - gasleft());
        vm.stopPrank();
        
        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);
        gas_left = gasleft();
        stream.stake(100);
        emit_log_named_uint(Color.Cyan, "gas_stake: partial_warm", gas_left - gasleft());
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream

        vm.prank(alice);
        gas_left = gasleft();
        stream.claimReward();
        emit_log_named_uint(Color.Cyan, "gas_claimReward:   cold", gas_left - gasleft());
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 500);

        vm.prank(bob);
        gas_left = gasleft();
        stream.claimReward();
        emit_log_named_uint(Color.Cyan, "gas_claimReward:   warm", gas_left - gasleft());
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 500);
        // we leave dust :shrug:
    }

    function test_multiUserStakeRewardsHalf() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration / 2); // move to half done
        
        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream

        vm.prank(alice);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 666);

        vm.prank(bob);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 333);
        // we leave dust :shrug:
    }

    function test_multiUserStakeRewardsWithWithdraw() public {
        testTokenA.approve(address(stream), type(uint256).max);
        stream.fundStream(1000);

        uint256 alicePreBal = testTokenA.balanceOf(alice);
        vm.startPrank(alice);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();


        vm.warp(startTime + minStreamDuration / 2); // move to half done
        
        uint256 bobPreBal = testTokenA.balanceOf(bob);
        vm.startPrank(bob);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.stopPrank();

        vm.warp(startTime + minStreamDuration / 2 + minStreamDuration / 10);

        vm.prank(alice);
        uint256 gas_left = gasleft();
        stream.exit();
        emit_log_named_uint(Color.Cyan, "gas_exit: cold", gas_left - gasleft());

        vm.warp(startTime + minStreamDuration + 1); // warp to end of stream


        vm.prank(alice);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(alice), alicePreBal + 533);

        vm.prank(bob);
        stream.claimReward();
        assertEq(testTokenA.balanceOf(bob), bobPreBal + 466);
    }

    function test_stakeAmtRevert() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        stream.stake(0);
    }

    function test_stakeTimeRevert() public {
        vm.warp(endStream);
        vm.expectRevert(abi.encodeWithSignature("NotStream()"));
        stream.stake(100);
    }

    function test_stakeERCRevert() public {
        vm.warp(block.timestamp + minStartDelay);
        writeBalanceOf(address(stream), address(testTokenB), 2**112 + 1);
        
        testTokenB.approve(address(stream), 100);
        vm.expectRevert(abi.encodeWithSignature("BadERC20Interaction()"));
        stream.stake(100);
    }

    function test_stakeNoMerkle() public {
        testTokenB.approve(address(stream), 102);
        uint256 gas_left = gasleft();
        stream.stake(100);
        emit_log_named_uint(Color.Cyan, "gas_stake: cold", gas_left - gasleft());
        LockeERC20 asLERC = LockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 100);
        (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount, ) = stream.tokenAmounts();
        assertEq(depositTokenAmount, 100);

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 100);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance,               100);
            assertEq(rewards,                      0);
            assertEq(tokens,                       100);
            assertEq(lastUpdate,                   startTime);
            assertTrue(!merkleAccess);
        }

        // move forward 1/10th of sd
        // round up to next second
        vm.warp(startTime + minStreamDuration / 10 + 1);
        uint256 rewardPerToken = stream.rewardPerToken();
        gas_left = gasleft();
        stream.stake(1);
        emit_log_named_uint(Color.Cyan, "gas_stake: warm", gas_left - gasleft());

        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 91);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, rewardPerToken);
            assertEq(virtualBalance,               101);
            assertEq(rewards,                      0);
            assertEq(tokens,                       91);
            assertEq(lastUpdate,                   block.timestamp);
            assertTrue(!merkleAccess);
        }

        // move forward again
        vm.warp(startTime + (2*minStreamDuration) / 10 + 1);
        rewardPerToken = stream.rewardPerToken();
        stream.stake(1);


        {
            uint112 unstreamed = stream.unstreamed();
            assertEq(unstreamed, 82);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, rewardPerToken);
            assertEq(virtualBalance,               102);
            assertEq(rewards,                      0);
            assertEq(tokens,                       82);
            assertEq(lastUpdate,                   block.timestamp);
            assertTrue(!merkleAccess);
        }
    }

    function test_stakeIndefiniteNoMerkle() public {
        testTokenB.approve(address(indefinite), type(uint256).max);
        uint256 gas_left = gasleft();
        indefinite.stake(100);
        emit_log_named_uint(Color.Cyan, "gas_stake_indefinite: cold", gas_left - gasleft());
        LockeERC20 asLERC = LockeERC20(indefinite);
        // no tokens wen indefinite
        assertEq(asLERC.balanceOf(address(this)), 0);

        (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount, ) = indefinite.tokenAmounts();
        assertEq(depositTokenAmount, 100);
        {
            uint112 unstreamed = indefinite.unstreamed();
            assertEq(unstreamed, 100);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = indefinite.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance,               100);
            assertEq(rewards,                      0);
            assertEq(tokens,                       100);
            assertEq(lastUpdate,                   startTime);
            assertTrue(!merkleAccess);
        }

        gas_left = gasleft();
        indefinite.stake(100);
        emit_log_named_uint(Color.Cyan, "gas_stake_indefinite: warm", gas_left - gasleft());
    }
}

contract TestIncentive is BaseTest {
    function setUp() public {
        tokenABC();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);

        writeBalanceOf(address(this), address(testTokenC), 1<<128);
    }

    function test_createIncentiveWithZeroAmt() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        stream.createIncentive(address(testTokenC), 0);
    }

    function test_createIncentiveWithToken() public {
        vm.expectRevert(abi.encodeWithSignature("BadERC20Interaction()"));
        stream.createIncentive(address(testTokenA), 0);
    }

    function test_createIncentive() public {
        testTokenC.approve(address(stream), 100);
        uint256 gas_left = gasleft();
        stream.createIncentive(address(testTokenC), 100);
        emit_log_named_uint(Color.Cyan, "gas_createIncentive: cold", gas_left - gasleft());
        (uint112 amt, bool flag) = stream.incentives(address(testTokenC));
        assertTrue(flag);
        assertEq(amt, 100);
    }

    function test_claimIncentiveCreatorRevert() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotCreator()"));
        stream.claimIncentive(address(testTokenC));
    }

    function test_claimIncentiveStreamRevert() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);

        vm.expectRevert(abi.encodeWithSignature("StreamOngoing()"));
        stream.claimIncentive(address(testTokenC));
    }

    function test_claimIncentiveAmt() public {
        vm.warp(block.timestamp + minStartDelay + minStreamDuration);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        stream.claimIncentive(address(testTokenC));
    }

    function test_claimIncentive() public {
        testTokenC.approve(address(stream), 100);
        stream.createIncentive(address(testTokenC), 100);

        vm.warp(block.timestamp + minStartDelay + minStreamDuration);

        uint256 preBal = testTokenC.balanceOf(address(this));
        uint256 gas_left = gasleft();
        stream.claimIncentive(address(testTokenC));
        emit_log_named_uint(Color.Cyan, "gas_claimIncentive: cold", gas_left - gasleft());

        assertEq(testTokenC.balanceOf(address(this)), preBal + 100);
    }
}

contract TestDeposit is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);

        (
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration
        ) = stream.streamParams();
        endStream = startTime + streamDuration;
        endDepositLock = endStream + depositLockDuration;

        writeBalanceOf(address(this), address(testTokenB), 1<<128);
    }

    function test_claimDepositIndefiniteRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);
        vm.warp(endDepositLock);
        vm.expectRevert(abi.encodeWithSignature("StreamTypeError()"));
        indefinite.claimDepositTokens(100);
    }

    function test_claimDepositAmtRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.warp(endDepositLock);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        stream.claimDepositTokens(0);
    }

    function test_claimDepositLockRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        vm.expectRevert(abi.encodeWithSignature("LockOngoing()"));
        stream.claimDepositTokens(100);
    }

    function test_claimDeposit() public {
        testTokenB.approve(address(stream), 105);
        stream.stake(105);

        vm.warp(endDepositLock + 1);

        uint256 preBal = testTokenB.balanceOf(address(this));

        uint256 gas_left = gasleft();
        stream.claimDepositTokens(100);
        emit_log_named_uint(Color.Cyan, "gas_claimDeposit: cold", gas_left - gasleft());

        LockeERC20 asLERC = LockeERC20(stream);
        assertEq(asLERC.balanceOf(address(this)), 5);

        uint256 redeemed = uint256(vm.load(address(stream), bytes32(uint256(10)))) >> 112;
        assertEq(redeemed, 100);

        assertEq(testTokenB.balanceOf(address(this)), preBal + 100);

        gas_left = gasleft();
        stream.claimDepositTokens(5);
        emit_log_named_uint(Color.Cyan, "gas_claimDeposit: warm", gas_left - gasleft());
    }
}

contract TestCreatorClaimTokens is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);

        (
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration
        ) = stream.streamParams();
        endStream = startTime + streamDuration;
        endDepositLock = endStream + depositLockDuration;

        writeBalanceOf(address(this), address(testTokenB), 1<<128);
    }

    function test_creatorClaimTokensNotIndefiniteRevert() public {
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        vm.warp(endDepositLock + 1);
        vm.expectRevert(abi.encodeWithSignature("StreamTypeError()"));
        stream.creatorClaim(address(this));
    }

    function test_creatorClaimTokensDoubleClaimRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.warp(endDepositLock + 1);
        indefinite.creatorClaim(address(this));

        vm.expectRevert(abi.encodeWithSignature("BalanceError()"));
        indefinite.creatorClaim(address(this));
    }

    function test_creatorClaimTokensCreatorRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.warp(endDepositLock + 1);

        vm.expectRevert(abi.encodeWithSignature("NotCreator()"));
        vm.prank(alice);
        indefinite.creatorClaim(address(this));
    }

    function test_creatorClaimTokensStreamRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.expectRevert(abi.encodeWithSignature("StreamOngoing()"));
        indefinite.creatorClaim(address(this));
    }

    function test_creatorClaimTokens() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.warp(endDepositLock + 1);

        uint256 preBal = testTokenB.balanceOf(address(this));
        uint256 gas_left = gasleft();
        indefinite.creatorClaim(address(this));
        emit_log_named_uint(Color.Cyan, "gas_creatorClaim: cold", gas_left - gasleft());

        assertEq(testTokenB.balanceOf(address(this)), preBal + 100);

        uint256 redeemed = uint256(vm.load(address(indefinite), bytes32(uint256(10)))) >> 112;
        assertEq(redeemed, 100);

        uint8 claimed = uint8(uint256(vm.load(address(indefinite), bytes32(uint256(7)))) >> (112 + 112 + 8));
        assertEq(claimed, 1);
    }
}

contract TestFees is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);
        defaultStreamFactory.updateFeeParams(StreamFactory.GovernableFeeParams({
            feePercent: 100,
            feeEnabled: true
        }));
        fee = streamSetupIndefinite(block.timestamp + minStartDelay);

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
    }

    function test_claimFeesStreamRevert() public {
        vm.expectRevert(abi.encodeWithSignature("StreamOngoing()"));
        stream.claimFees(address(this));
    }

    function test_claimFeesGovRevert() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NotGov()"));
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

        uint256 gas_left = gasleft();
        fee.claimFees(address(this));
        emit_log_named_uint(Color.Cyan, "gas_claimFeesRewardToken: cold", gas_left - gasleft());

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
        uint256 gas_left = gasleft();
        fee.claimFees(address(this));
        emit_log_named_uint(Color.Cyan, "gas_claimFeesDepositToken: cold", gas_left - gasleft());

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

        uint256 gas_left = gasleft();
        fee.claimFees(address(this));
        emit_log_named_uint(Color.Cyan, "gas_claimFeesBoth: cold", gas_left - gasleft());

        assertEq(testTokenA.balanceOf(address(this)), preBal + feeAmt);
        assertEq(testTokenB.balanceOf(address(this)), preBalDeposit + feeAmtDeposit);

        (, , rewardTokenFeeAmount, ) = fee.tokenAmounts();
        assertEq(rewardTokenFeeAmount, 0);

        (, , , uint112 depositTokenFees) = fee.tokenAmounts();
        assertEq(depositTokenFees, 0);
    }
}

contract TestFlashloan is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);

        writeBalanceOf(address(this), address(testTokenB), 1<<128);
    }

    function test_flashloanTokenRevert() public {
        vm.expectRevert(abi.encodeWithSignature("BadERC20Interaction()"));
        stream.flashloan(address(123), address(0), 100, "");
    }

    function test_flashloanFeeRevert() public {
        testTokenB.approve(address(stream), 1337);
        stream.stake(1337);

        uint256 currBal = testTokenB.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSignature("BalanceError()"));
        stream.flashloan(address(testTokenB), address(this), 1337, abi.encode(false, currBal));
    }

    function test_flashloan() public {
        testTokenB.approve(address(stream), 1337);
        stream.stake(1337);

        uint256 currBal = testTokenB.balanceOf(address(this));

        uint256 gas_left = gasleft();
        stream.flashloan(address(testTokenB), address(this), 1337, abi.encode(true, currBal));
        emit_log_named_uint(Color.Cyan, "gas_flashloan: cold", gas_left - gasleft());
        
        assertTrue(enteredFlashloan);
    }
}

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
        vm.expectRevert(abi.encodeWithSignature("StreamOngoing()"));
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
        vm.expectRevert(abi.encodeWithSignature("NotGov()"));
        stream.arbitraryCall(address(1), "");
    }

    function test_arbitraryCallTokenRevert() public {
        vm.expectRevert(abi.encodeWithSignature("BadERC20Interaction()"));
        stream.arbitraryCall(address(testTokenA), "");

        vm.expectRevert(abi.encodeWithSignature("BadERC20Interaction()"));
        stream.arbitraryCall(address(testTokenB), "");
    }

    function test_arbitraryCallTransferRevert() public {
        vm.expectRevert(abi.encodeWithSignature("BadERC20Interaction()"));
        stream.arbitraryCall(address(testTokenC), abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), address(this), 100000));
    }
}



    // function test_recoverTokens() public {
    //     (
    //         uint32 maxDepositLockDuration,
    //         uint32 maxRewardLockDuration,
    //         uint32 maxStreamDuration,
    //         uint32 minStreamDuration
    //     ) = defaultStreamFactory.streamCreationParams();

    //     uint32 startTime = uint32(block.timestamp + minStartDelay);

    //     uint32 endStream = startTime + minStreamDuration;
    //     uint32 endDepositLock = endStream + maxDepositLockDuration;
    //     uint32 endRewardLock = endStream + 0;
    //     {
    //         Stream stream = defaultStreamFactory.createStream(
    //             address(testTokenA),
    //             address(testTokenB),
    //             startTime,
    //             minStreamDuration,
    //             maxDepositLockDuration,
    //             0,
    //             false
    //         );

    //         testTokenA.approve(address(stream), type(uint256).max);
    //         stream.fundStream(1000000);
    //         bob.doStake(stream, address(testTokenB), 1000000);

    //         bytes4 sig = sigs("recoverTokens(address,address)");
    //         expect_revert_with(
    //             address(stream),
    //             sig,
    //             abi.encode(address(testTokenB), address(this)),
    //             "time"
    //         );
    //         uint256 bal = testTokenB.balanceOf(address(this));
    //         testTokenB.transfer(address(stream), 100);
    //         vm.warp(endDepositLock + 1);
    //         stream.recoverTokens(address(testTokenB), address(this));
    //         assertEq(testTokenB.balanceOf(address(this)), bal);
    //         vm.warp(startTime - 10);
    //     }

    //     {
    //         Stream stream = defaultStreamFactory.createStream(
    //             address(testTokenA),
    //             address(testTokenB),
    //             startTime,
    //             minStreamDuration,
    //             maxDepositLockDuration,
    //             0,
    //             false
    //         );

    //         testTokenA.approve(address(stream), type(uint256).max);
    //         stream.fundStream(1000000);
    //         bob.doStake(stream, address(testTokenB), 1000000);

    //         bytes4 sig = sigs("recoverTokens(address,address)");
    //         expect_revert_with(
    //             address(stream),
    //             sig,
    //             abi.encode(address(testTokenA), address(this)),
    //             "time"
    //         );
    //         uint256 bal = testTokenA.balanceOf(address(this));
    //         testTokenA.transfer(address(stream), 100);
    //         vm.warp(endRewardLock + 1);
    //         stream.recoverTokens(address(testTokenA), address(this));
    //         assertEq(testTokenA.balanceOf(address(this)), bal);
    //         vm.warp(startTime - 10);
    //     }

    //     {
    //         Stream stream = defaultStreamFactory.createStream(
    //             address(testTokenA),
    //             address(testTokenB),
    //             startTime,
    //             minStreamDuration,
    //             maxDepositLockDuration,
    //             0,
    //             false
    //         );

    //         testTokenA.approve(address(stream), type(uint256).max);
    //         stream.fundStream(1000000);
    //         bob.doStake(stream, address(testTokenB), 1000000);


    //         testTokenC.approve(address(stream), type(uint256).max);
    //         stream.createIncentive(address(testTokenC), 100);

    //         bytes4 sig = sigs("recoverTokens(address,address)");
    //         expect_revert_with(
    //             address(stream),
    //             sig,
    //             abi.encode(address(testTokenC), address(this)),
    //             "stream"
    //         );
    //         uint256 bal = testTokenC.balanceOf(address(this));
    //         testTokenC.transfer(address(stream), 100);
    //         vm.warp(endStream + 1);
    //         stream.recoverTokens(address(testTokenC), address(this));
    //         uint256 newbal = testTokenC.balanceOf(address(this));
    //         assertEq(newbal, bal);
    //         stream.claimIncentive(address(testTokenC));
    //         assertEq(testTokenC.balanceOf(address(this)), newbal + 100);
    //         vm.warp(startTime - 10);
    //     }

    //     {
    //         Stream stream = defaultStreamFactory.createStream(
    //             address(testTokenA),
    //             address(testTokenB),
    //             startTime,
    //             minStreamDuration,
    //             maxDepositLockDuration,
    //             0,
    //             false
    //         );

    //         testTokenA.approve(address(stream), type(uint256).max);
    //         stream.fundStream(1000000);
    //         bob.doStake(stream, address(testTokenB), 1000000);

    //         uint256 bal = testTokenC.balanceOf(address(this));
    //         testTokenC.transfer(address(stream), 100);
    //         vm.warp(endStream);
    //         stream.recoverTokens(address(testTokenC), address(this));
    //         assertEq(testTokenC.balanceOf(address(this)), bal);
    //         vm.warp(startTime - 10);
    //     }
    // }




contract StreamFactoryTest is BaseTest {
    // function test_createStream() public {

    //     // ===  EXPECTED FAILURES ===
    //     (
    //         uint32 maxDepositLockDuration,
    //         uint32 maxRewardLockDuration,
    //         uint32 maxStreamDuration,
    //         uint32 minStreamDuration
    //     ) = defaultStreamFactory.streamCreationParams();

    //     {
    //         // Fails
    //         bytes4 sig = sigs("createStream(address,address,uint32,uint32,uint32,uint32,bool)");
    //         expect_revert_with(
    //             address(defaultStreamFactory),
    //             sig,
    //             abi.encode(
    //                 address(0),
    //                 address(0),
    //                 block.timestamp - 10,
    //                 0,
    //                 0,
    //                 0,
    //                 false
    //                 // false,
    //                 // bytes32(0)
    //             ),
    //             "past"
    //         );

    //         if (minStreamDuration > 0) {
    //             expect_revert_with(
    //                 address(defaultStreamFactory),
    //                 sig,
    //                 abi.encode(
    //                     address(0),
    //                     address(0),
    //                     block.timestamp,
    //                     minStreamDuration - 1,
    //                     0,
    //                     0,
    //                     false
    //                     // false,
    //                     // bytes32(0)
    //                 ),
    //                 "stream"
    //             );
    //         }

    //         expect_revert_with(
    //             address(defaultStreamFactory),
    //             sig,
    //             abi.encode(
    //                 address(0),
    //                 address(0),
    //                 block.timestamp,
    //                 maxStreamDuration + 1,
    //                 0,
    //                 0,
    //                 false
    //                 // false,
    //                 // bytes32(0)
    //             ),
    //             "stream"
    //         );

    //         expect_revert_with(
    //             address(defaultStreamFactory),
    //             sig,
    //             abi.encode(
    //                 address(0),
    //                 address(0),
    //                 block.timestamp,
    //                 minStreamDuration,
    //                 maxDepositLockDuration + 1,
    //                 0,
    //                 false
    //                 // false,
    //                 // bytes32(0)
    //             ),
    //             "lock"
    //         );

    //         expect_revert_with(
    //             address(defaultStreamFactory),
    //             sig,
    //             abi.encode(
    //                 address(0),
    //                 address(0),
    //                 block.timestamp,
    //                 minStreamDuration,
    //                 maxDepositLockDuration,
    //                 maxRewardLockDuration + 1,
    //                 false
    //                 // false,
    //                 // bytes32(0)
    //             ),
    //             "reward"
    //         );
    //     }
    //     // ===   ===
        

    //     // === Successful ===
    //     {
    //         // No Fees
    //         Stream stream = defaultStreamFactory.createStream(
    //             address(testTokenA),
    //             address(testTokenB),
    //             uint32(block.timestamp + minStartDelay), // 10 seconds in future
    //             minStreamDuration,
    //             maxDepositLockDuration,
    //             0,
    //             false
    //             // false,
    //             // bytes32(0)
    //         );

    //         (uint16 feePercent, bool feeEnabled) = defaultStreamFactory.feeParams();

    //         // time stuff
    //         (uint32 startTime, uint32 streamDuration, uint32 depositLockDuration, uint32 rewardLockDuration) = stream.streamParams();
    //         assertEq(startTime, block.timestamp + minStartDelay);
    //         assertEq(streamDuration, minStreamDuration);
    //         assertEq(depositLockDuration, maxDepositLockDuration);
    //         assertEq(rewardLockDuration, 0);

    //         // tokens
    //         assertEq(stream.rewardToken(), address(testTokenA));
    //         assertEq(stream.depositToken(), address(testTokenB));

    //         // address
    //         // assertEq(address(uint160(uint(hash))), address(stream));

    //         // id
    //         assertEq(stream.streamId(), 0);

    //         // factory
    //         assertEq(defaultStreamFactory.currStreamId(), 1);

    //         // token
    //         assertEq(stream.name(), "lockeTest Token B: 0");
    //         assertEq(stream.symbol(), "lockeTTB0");

    //         // others
    //         (feePercent, feeEnabled) = stream.feeParams();
    //         assertEq(feePercent, 0);
    //         assertTrue(!feeEnabled);
    //         assertTrue(!stream.isIndefinite());
    //     }
        
    //     {
    //         // With Fees
    //         defaultStreamFactory.updateFeeParams(StreamFactory.GovernableFeeParams({
    //             feePercent: 100,
    //             feeEnabled: true
    //         }));
    //         Stream stream = defaultStreamFactory.createStream(
    //             address(testTokenA),
    //             address(testTokenB),
    //             uint32(block.timestamp + minStartDelay), // 10 seconds in future
    //             minStreamDuration,
    //             maxDepositLockDuration,
    //             0,
    //             false
    //             // false,
    //             // bytes32(0)
    //         );

    //         (uint16 feePercent, bool feeEnabled) = defaultStreamFactory.feeParams();

    //         // time stuff
    //         (uint32 startTime, uint32 streamDuration, uint32 depositLockDuration, uint32 rewardLockDuration) = stream.streamParams();
    //         assertEq(startTime, block.timestamp + minStartDelay);
    //         assertEq(streamDuration, minStreamDuration);
    //         assertEq(depositLockDuration, maxDepositLockDuration);
    //         assertEq(rewardLockDuration, 0);

    //         // tokens
    //         assertEq(stream.rewardToken(), address(testTokenA));
    //         assertEq(stream.depositToken(), address(testTokenB));

    //         // address
    //         // assertEq(address(uint160(uint(hash))), address(stream));

    //         // id
    //         assertEq(stream.streamId(), 1);

    //         // factory
    //         assertEq(defaultStreamFactory.currStreamId(), 2);

    //         // token
    //         assertEq(stream.name(), "lockeTest Token B: 1");
    //         assertEq(stream.symbol(), "lockeTTB1");

    //         // other
    //         (feePercent, feeEnabled) = stream.feeParams();
    //         assertEq(feePercent, 100);
    //         assertTrue(feeEnabled);
    //         assertTrue(!stream.isIndefinite());
    //     }
    //     // ===   ===
    // }


    // function test_updateStreamParams() public {
    //     // set the gov to none
    //     write_flat(address(defaultStreamFactory), "gov()", address(0));
    //     StreamFactory.GovernableStreamParams memory newParams = StreamFactory.GovernableStreamParams({
    //         maxDepositLockDuration: 1337 weeks,
    //         maxRewardLockDuration: 1337 weeks,
    //         maxStreamDuration: 1337 weeks,
    //         minStreamDuration: 1337 hours
    //     });
    //     expect_revert_with(
    //         address(defaultStreamFactory),
    //         sigs("updateStreamParams((uint32,uint32,uint32,uint32))"),
    //         abi.encode(newParams),
    //         "!gov"
    //     );

    //     // get back gov and set and check
    //     write_flat(address(defaultStreamFactory), "gov()", address(this));
    //     defaultStreamFactory.updateStreamParams(newParams);

    //     (
    //         uint32 maxDepositLockDuration,
    //         uint32 maxRewardLockDuration,
    //         uint32 maxStreamDuration,
    //         uint32 minStreamDuration
    //     ) = defaultStreamFactory.streamCreationParams();
    //     assertEq(maxDepositLockDuration, 1337 weeks);
    //     assertEq(maxRewardLockDuration, 1337 weeks);
    //     assertEq(maxStreamDuration, 1337 weeks);
    //     assertEq(minStreamDuration, 1337 hours);
    // }

    // function test_updateFeeParams() public {
    //     // set the gov to none
    //     write_flat(address(defaultStreamFactory), "gov()", address(0));
        
    //     uint16 max = 500;
    //     StreamFactory.GovernableFeeParams memory newParams = StreamFactory.GovernableFeeParams({
    //         feePercent: max + 1,
    //         feeEnabled: true
    //     });
    //     expect_revert_with(
    //         address(defaultStreamFactory),
    //         sigs("updateFeeParams((uint16,bool))"),
    //         abi.encode(newParams),
    //         "!gov"
    //     );

    //     // get back gov and set and check
    //     write_flat(address(defaultStreamFactory), "gov()", address(this));
        
    //     expect_revert_with(
    //         address(defaultStreamFactory),
    //         sigs("updateFeeParams((uint16,bool))"),
    //         abi.encode(newParams),
    //         "fee"
    //     );

    //     newParams.feePercent = 137;

    //     defaultStreamFactory.updateFeeParams(newParams);
    //     (
    //         uint16 feePercent,
    //         bool feeEnabled
    //     ) = defaultStreamFactory.feeParams();
    //     assertEq(feePercent, 137);
    //     assertTrue(feeEnabled);
    // }
}