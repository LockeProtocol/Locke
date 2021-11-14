// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./utils/LockeTest.sol";

contract StreamTest is LockeTest {
    function test_fundStream() public {
        // === Setup ===
        Stream stream = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            block.timestamp + 10, // 10 seconds in future
            4 weeks,
            26 weeks, // 6 months
            0,
            false
        );

        uint112 amt = 1337;
        testTokenA.approve(address(stream), type(uint256).max);
        // ===   ===


        // === Failures ===
        bytes4 sig = sigs("fundStream(uint112)");
        expect_revert_with(
            address(stream),
            sig,
            abi.encode(0),
            "amt"
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
        stream.fundStream(amt);
        (uint112 rewardTokenAmount, uint112 _, uint112 rewardTokenFeeAmount) = stream.tokenAmounts();
        assertEq(rewardTokenAmount, amt);
        assertEq(rewardTokenFeeAmount, 0);
        assertEq(testTokenA.balanceOf(address(stream)), 1337);
        // ===    ===


        // === Fees Enabled ====
        defaultStreamFactory.updateFeeParams(GovernableFeeParams({
            feePercent: 100,
            feeEnabled: true,
        }));
        stream = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            block.timestamp + 10, // 10 seconds in future
            4 weeks,
            26 weeks, // 6 months
            0,
            false
        );

        uint112 feeAmt = 13; // expected fee amt
        stream.fundStream(amt);
        (uint112 rewardTokenAmount, uint112 _, uint112 rewardTokenFeeAmount) = stream.tokenAmounts();
        assertEq(rewardTokenAmount, amt - feeAmt);
        assertEq(rewardTokenFeeAmount, feeAmt);
        assertEq(testTokenA.balanceOf(address(stream)), 1337);
        // ===============================
    }
}

contract StreamFactoryTest is LockeTest {
    function test_createStream() public {

        // ===  EXPECTED FAILURES ===
        GovernableStreamParams memory streamParams = defaultStreamFactory.streamParams();

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

        if (streamParams.minStreamDuration > 0) {
            expect_revert_with(
                address(defaultStreamFactory),
                sig,
                abi.encode(
                    address(0),
                    address(0),
                    block.timestamp,
                    streamParams.minStreamDuration - 1,
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
                streamParams.maxStreamDuration + 1,
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
                streamParams.minStreamDuration,
                streamParams.maxDepositLockDuration + 1,
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
                streamParams.minStreamDuration,
                streamParams.maxDepositLockDuration,
                streamParams.maxRewardLockDuration + 1,
                false
            ),
            "rug:rewardDuration"
        );
        // ===   ===
        

        // === Successful ===
        Stream stream = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            block.timestamp + 10, // 10 seconds in future
            4 weeks,
            26 weeks, // 6 months
            0,
            false
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), 
                address(this), 
                bytes32(0), // salt is the stream id which should have been 0
                keccak256(type(Stream).creationCode)
            )
        );

        assertEq(address(uint160(uint(hash))), address(stream));
        assertEq(stream.streamId(), 0);
        assertEq(defaultStreamFactory.currStreamId(), 1);
        assertEq(stream.name(), "locke Test Token B: 0");
        assertEq(stream.symbol(), "lockeTTB0");
        // ===   ===
    }


    function test_updateStreamParams() public {
        // set the gov to none
        write_flat(address(defaultStreamFactory), "gov()", address(0));
        StreamFactory.GovernableStreamParams memory newParams = new StreamFactory.GovernableStreamParams({
            maxDepositLockDuration: 1337 years,
            maxRewardLockDuration: 1337 years,
            maxStreamDuration: 1337 weeks,
            minStreamDuration: 1337 hours
        });
        expect_revert_with(
            address(defaultStreamFactory),
            sigs("updateStreamParams((uint32,uint32,uint32,uint32))")
            abi.encode(newParams),
            "!gov"
        );

        // get back gov and set and check
        write_flat(address(defaultStreamFactory), "gov()", address(this));
        defaultStreamFactory.updateStreamParams(newParams);

        StreamFactory.GovernableStreamParams memory readParams = defaultStreamFactory.streamParams();
        assertEq(readParams.maxDepositLockDuration, 1337 years);
        assertEq(readParams.maxRewardLockDuration, 1337 years);
        assertEq(readParams.maxStreamDuration, 1337 weeks);
        assertEq(readParams.minStreamDuration, 1337 hours);
    }

    function test_updateFeeParams() public {
        // set the gov to none
        write_flat(address(defaultStreamFactory), "gov()", address(0));
        
        uint16 max = 500;
        StreamFactory.GovernableFeeParams memory newParams = new StreamFactory.GovernableFeeParams({
            feePercent: max + 1,
            feeEnabled: true
        });
        expect_revert_with(
            address(defaultStreamFactory),
            sigs("updateFeeParams((uint16,bool))")
            abi.encode(newParams),
            "!gov"
        );

        // get back gov and set and check
        write_flat(address(defaultStreamFactory), "gov()", address(this));
        
        expect_revert_with(
            address(defaultStreamFactory),
            sigs("updateFeeParams((uint16,bool))")
            abi.encode(newParams),
            "rug:fee"
        );

        newParams.fee = 137;

        defaultStreamFactory.updateFeeParams(newParams);
        StreamFactory.GovernableStreamParams memory readParams = defaultStreamFactory.streamParams();
        assertEq(readParams.feePercent, 137);
        assertEq(readParams.feeEnabled, true);
    }
}