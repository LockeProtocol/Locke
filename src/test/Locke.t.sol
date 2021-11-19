// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./utils/LockeTest.sol";

contract StreamTest is LockeTest {
    function test_fundStream() public {
        // === Setup ===
        (
            uint32 maxDepositLockDuration,
            uint32 maxRewardLockDuration,
            uint32 maxStreamDuration,
            uint32 minStreamDuration
        ) = defaultStreamFactory.streamParams();

        uint112 amt = 1337;
        emit log_named_uint("blocktime", block.timestamp);
        {
            uint64 nextStream = defaultStreamFactory.currStreamId();
            emit log_named_uint("nextStream", nextStream);
            Stream stream = defaultStreamFactory.createStream(
                address(testTokenA),
                address(testTokenB),
                uint32(block.timestamp + 10), // 10 seconds in future
                minStreamDuration,
                maxDepositLockDuration,
                0,
                false
            );


            
            testTokenA.approve(address(stream), type(uint256).max);
            // ===   ===


            // === Failures ===
            bytes4 sig = sigs("fundStream(uint112)");
            expect_revert_with(
                address(stream),
                sig,
                abi.encode(0),
                "fund:poor"
            );
            hevm.warp(block.timestamp + 11);
            expect_revert_with(
                address(stream),
                sig,
                abi.encode(amt),
                ">time"
            );
            hevm.warp(block.timestamp - 11);
            // ===   ===

            


            // === No Fees ===

            uint256 gas_left = gasleft();
            stream.fundStream(amt);
            emit log_named_uint("gas_usage_no_fee", gas_left - gasleft());
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount) = stream.tokenAmounts();
            assertEq(rewardTokenAmount, amt);
            assertEq(rewardTokenFeeAmount, 0);
            assertEq(testTokenA.balanceOf(address(stream)), 1337);
            // ===    ===
        }


        {
            // === Fees Enabled ====
            defaultStreamFactory.updateFeeParams(StreamFactory.GovernableFeeParams({
                feePercent: 100,
                feeEnabled: true
            }));
            uint256 nextStream = defaultStreamFactory.currStreamId();
            emit log_named_uint("nextStream2", nextStream);
            Stream stream = defaultStreamFactory.createStream(
                address(testTokenA),
                address(testTokenB),
                uint32(block.timestamp + 10), // 10 seconds in future
                minStreamDuration,
                maxDepositLockDuration,
                0,
                false
            );

            testTokenA.approve(address(stream), type(uint256).max);

            uint112 feeAmt = 13; // expected fee amt
            uint256 gas_left = gasleft();
            stream.fundStream(amt);
            emit log_named_uint("gas_usage_w_fee", gas_left - gasleft());
            (uint112 rewardTokenAmount, uint112 _unused, uint112 rewardTokenFeeAmount) = stream.tokenAmounts();
            assertEq(rewardTokenAmount, amt - feeAmt);
            assertEq(rewardTokenFeeAmount, feeAmt);
            assertEq(testTokenA.balanceOf(address(stream)), 1337);
        }
    }

    function test_stake() public {
        (
            uint32 maxDepositLockDuration,
            uint32 maxRewardLockDuration,
            uint32 maxStreamDuration,
            uint32 minStreamDuration
        ) = defaultStreamFactory.streamParams();

        uint32 startTime = uint32(block.timestamp + 10);
        Stream stream = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            startTime,
            minStreamDuration,
            maxDepositLockDuration,
            0,
            false
        );

        testTokenB.approve(address(stream), type(uint256).max);

        {
            // Failures
            bytes4 sig = sigs("stake(uint112)");
            expect_revert_with(
                address(stream),
                sig,
                abi.encode(0),
                "stake:poor"
            );

            // fast forward minStreamDuration
            hevm.warp(startTime + minStreamDuration);
            expect_revert_with(
                address(stream),
                sig,
                abi.encode(100),
                "stake:!stream"
            );
            hevm.warp(startTime - minStreamDuration);

            write_balanceOf(address(testTokenB), address(stream), 2**112 + 1);
            expect_revert_with(
                address(stream),
                sig,
                abi.encode(100),
                "rug:erc20"
            );
            write_balanceOf(address(testTokenB), address(stream), 0);
        }

        {
            // Successes
            stream.stake(100);
            LockeERC20 asLERC = LockeERC20(stream);
            assertEq(asLERC.balanceOf(address(this)), 100);

            (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount) = stream.tokenAmounts();
            assertEq(depositTokenAmount, 100);

            (uint112 tokens, uint32 lu) = stream.tokensNotYetStreamed(address(this));
            assertEq(tokens, 100);
        }
        {            
            // Sale test
            Stream stream = defaultStreamFactory.createStream(
                address(testTokenA),
                address(testTokenB),
                startTime,
                minStreamDuration,
                maxDepositLockDuration,
                0,
                true
            );
            testTokenB.approve(address(stream), type(uint256).max);
            stream.stake(100);
            LockeERC20 asLERC = LockeERC20(stream);
            // no tokens wen sale
            assertEq(asLERC.balanceOf(address(this)), 0);

            (uint112 rewardTokenAmount, uint112 depositTokenAmount, uint112 rewardTokenFeeAmount) = stream.tokenAmounts();
            assertEq(depositTokenAmount, 100);
            (uint112 tokens, uint32 lu) = stream.tokensNotYetStreamed(address(this));
            assertEq(tokens, 100);
        }
    }
}

contract StreamFactoryTest is LockeTest {
    function test_createStream() public {

        // ===  EXPECTED FAILURES ===
        (
            uint32 maxDepositLockDuration,
            uint32 maxRewardLockDuration,
            uint32 maxStreamDuration,
            uint32 minStreamDuration
        ) = defaultStreamFactory.streamParams();

        {
            // Fails
            bytes4 sig = sigs("createStream(address,address,uint32,uint32,uint32,uint32,bool)");
            expect_revert_with(
                address(defaultStreamFactory),
                sig,
                abi.encode(
                    address(0),
                    address(0),
                    block.timestamp - 10,
                    0,
                    0,
                    0,
                    false
                ),
                "rug:past"
            );

            if (minStreamDuration > 0) {
                expect_revert_with(
                    address(defaultStreamFactory),
                    sig,
                    abi.encode(
                        address(0),
                        address(0),
                        block.timestamp,
                        minStreamDuration - 1,
                        0,
                        0,
                        false
                    ),
                    "rug:streamDuration"
                );
            }

            expect_revert_with(
                address(defaultStreamFactory),
                sig,
                abi.encode(
                    address(0),
                    address(0),
                    block.timestamp,
                    maxStreamDuration + 1,
                    0,
                    0,
                    false
                ),
                "rug:streamDuration"
            );

            expect_revert_with(
                address(defaultStreamFactory),
                sig,
                abi.encode(
                    address(0),
                    address(0),
                    block.timestamp,
                    minStreamDuration,
                    maxDepositLockDuration + 1,
                    0,
                    false
                ),
                "rug:lockDuration"
            );

            expect_revert_with(
                address(defaultStreamFactory),
                sig,
                abi.encode(
                    address(0),
                    address(0),
                    block.timestamp,
                    minStreamDuration,
                    maxDepositLockDuration,
                    maxRewardLockDuration + 1,
                    false
                ),
                "rug:rewardDuration"
            );
        }
        // ===   ===
        

        // === Successful ===
        {
            // No Fees
            Stream stream = defaultStreamFactory.createStream(
                address(testTokenA),
                address(testTokenB),
                uint32(block.timestamp + 10), // 10 seconds in future
                minStreamDuration,
                maxDepositLockDuration,
                0,
                false
            );

            (uint16 feePercent, bool feeEnabled) = defaultStreamFactory.feeParams();
            bytes32 codehash = keccak256(
                abi.encodePacked(
                    // Deployment bytecode:
                    type(Stream).creationCode,
                    // Constructor arguments:
                    abi.encode(
                        0, //stream id
                        address(this), // msg.sender
                        testTokenA,
                        testTokenB,
                        block.timestamp + 10,
                        minStreamDuration,
                        maxDepositLockDuration,
                        0,
                        feePercent,
                        feeEnabled,
                        false
                    )
                )
            );
            bytes32 hash = keccak256(
                abi.encodePacked(
                    bytes1(0xff), 
                    address(defaultStreamFactory), 
                    bytes32(uint256(0)), // salt is the stream id which should have been 0
                    codehash
                )
            );


            // time stuff
            (uint32 startTime, uint32 streamDuration, uint32 depositLockDuration, uint32 rewardLockDuration) = stream.streamParams();
            assertEq(startTime, block.timestamp + 10);
            assertEq(streamDuration, minStreamDuration);
            assertEq(depositLockDuration, maxDepositLockDuration);
            assertEq(rewardLockDuration, 0);

            // tokens
            assertEq(stream.rewardToken(), address(testTokenA));
            assertEq(stream.depositToken(), address(testTokenB));

            // address
            assertEq(address(uint160(uint(hash))), address(stream));

            // id
            assertEq(stream.streamId(), 0);

            // factory
            assertEq(defaultStreamFactory.currStreamId(), 1);

            // token
            assertEq(stream.name(), "lockeTest Token B: 0");
            assertEq(stream.symbol(), "lockeTTB0");

            // others
            (feePercent, feeEnabled) = stream.feeParams();
            assertEq(feePercent, 0);
            assertTrue(!feeEnabled);
            assertTrue(!stream.isSale());
        }
        
        {
            // With Fees
            defaultStreamFactory.updateFeeParams(StreamFactory.GovernableFeeParams({
                feePercent: 100,
                feeEnabled: true
            }));
            Stream stream = defaultStreamFactory.createStream(
                address(testTokenA),
                address(testTokenB),
                uint32(block.timestamp + 10), // 10 seconds in future
                minStreamDuration,
                maxDepositLockDuration,
                0,
                false
            );

            (uint16 feePercent, bool feeEnabled) = defaultStreamFactory.feeParams();
            bytes32 codehash = keccak256(
                abi.encodePacked(
                    // Deployment bytecode:
                    type(Stream).creationCode,
                    // Constructor arguments:
                    abi.encode(
                        1, //stream id
                        address(this), // msg.sender
                        testTokenA,
                        testTokenB,
                        block.timestamp + 10,
                        minStreamDuration,
                        maxDepositLockDuration,
                        0,
                        feePercent,
                        feeEnabled,
                        false
                    )
                )
            );
            bytes32 hash = keccak256(
                abi.encodePacked(
                    bytes1(0xff), 
                    address(defaultStreamFactory), 
                    bytes32(uint256(1)), // salt is the stream id which should have been 0
                    codehash
                )
            );


            // time stuff
            (uint32 startTime, uint32 streamDuration, uint32 depositLockDuration, uint32 rewardLockDuration) = stream.streamParams();
            assertEq(startTime, block.timestamp + 10);
            assertEq(streamDuration, minStreamDuration);
            assertEq(depositLockDuration, maxDepositLockDuration);
            assertEq(rewardLockDuration, 0);

            // tokens
            assertEq(stream.rewardToken(), address(testTokenA));
            assertEq(stream.depositToken(), address(testTokenB));

            // address
            assertEq(address(uint160(uint(hash))), address(stream));

            // id
            assertEq(stream.streamId(), 1);

            // factory
            assertEq(defaultStreamFactory.currStreamId(), 2);

            // token
            assertEq(stream.name(), "lockeTest Token B: 1");
            assertEq(stream.symbol(), "lockeTTB1");

            // other
            (feePercent, feeEnabled) = stream.feeParams();
            assertEq(feePercent, 100);
            assertTrue(feeEnabled);
            assertTrue(!stream.isSale());
        }
        // ===   ===
    }


    function test_updateStreamParams() public {
        // set the gov to none
        write_flat(address(defaultStreamFactory), "gov()", address(0));
        StreamFactory.GovernableStreamParams memory newParams = StreamFactory.GovernableStreamParams({
            maxDepositLockDuration: 1337 weeks,
            maxRewardLockDuration: 1337 weeks,
            maxStreamDuration: 1337 weeks,
            minStreamDuration: 1337 hours
        });
        expect_revert_with(
            address(defaultStreamFactory),
            sigs("updateStreamParams((uint32,uint32,uint32,uint32))"),
            abi.encode(newParams),
            "!gov"
        );

        // get back gov and set and check
        write_flat(address(defaultStreamFactory), "gov()", address(this));
        defaultStreamFactory.updateStreamParams(newParams);

        (
            uint32 maxDepositLockDuration,
            uint32 maxRewardLockDuration,
            uint32 maxStreamDuration,
            uint32 minStreamDuration
        ) = defaultStreamFactory.streamParams();
        assertEq(maxDepositLockDuration, 1337 weeks);
        assertEq(maxRewardLockDuration, 1337 weeks);
        assertEq(maxStreamDuration, 1337 weeks);
        assertEq(minStreamDuration, 1337 hours);
    }

    function test_updateFeeParams() public {
        // set the gov to none
        write_flat(address(defaultStreamFactory), "gov()", address(0));
        
        uint16 max = 500;
        StreamFactory.GovernableFeeParams memory newParams = StreamFactory.GovernableFeeParams({
            feePercent: max + 1,
            feeEnabled: true
        });
        expect_revert_with(
            address(defaultStreamFactory),
            sigs("updateFeeParams((uint16,bool))"),
            abi.encode(newParams),
            "!gov"
        );

        // get back gov and set and check
        write_flat(address(defaultStreamFactory), "gov()", address(this));
        
        expect_revert_with(
            address(defaultStreamFactory),
            sigs("updateFeeParams((uint16,bool))"),
            abi.encode(newParams),
            "rug:fee"
        );

        newParams.feePercent = 137;

        defaultStreamFactory.updateFeeParams(newParams);
        (
            uint16 feePercent,
            bool feeEnabled
        ) = defaultStreamFactory.feeParams();
        assertEq(feePercent, 137);
        assertTrue(feeEnabled);
    }
}