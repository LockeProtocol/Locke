// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import "../utils/LockeTest.sol";
import "../../LockeFactory.sol";
import "../../interfaces/IStreamFactory.sol";

contract StreamFactoryTest is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
    }

    function test_constructor() public {
        StreamCreation sc = new StreamCreation();
        MerkleStreamCreation msc = new MerkleStreamCreation();

        StreamFactory sf = new StreamFactory(bob, bob, sc, msc);

        (uint16 feePercent, bool feeEnabled) = sf.feeParams();
        assertTrue(!feeEnabled);
        assertEq(feePercent, 0);
        (
            uint32 maxDepositLockDuration,
            uint32 maxRewardLockDuration,
            uint32 maxStreamDuration,
            uint32 minStreamDuration,
            uint32 minStartDelay
        ) = sf.streamCreationParams();
        assertEq(maxDepositLockDuration, 52 weeks);
        assertEq(maxRewardLockDuration, 52 weeks);
        assertEq(maxStreamDuration, 2 weeks);
        assertEq(minStreamDuration, 1 hours);
        assertEq(minStartDelay, 1 days);
        assertEq(address(sf.streamCreation()), address(sc));
        assertEq(address(sf.merkleStreamCreation()), address(msc));
    }

    function test_createStreamNoMerkle() public {
        (
            uint32 maxDepositLockDuration,
            uint32 maxRewardLockDuration,
            uint32 maxStreamDuration,
            uint32 minStreamDuration,
            uint32 minStartDelay
        ) = defaultStreamFactory.streamCreationParams();

        stream = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            minStreamDuration,
            maxDepositLockDuration,
            0,
            false
        );
        vm.label(address(stream), "Stream");

        (uint16 feePercent, bool feeEnabled) = stream.feeParams();
        assertEq(feePercent, 0);
        assertTrue(!feeEnabled);

        (
            startTime,
            endStream,
            endDepositLock,
            endRewardLock
        ) = stream.streamParams();

        assertEq(startTime,      block.timestamp + minStartDelay);
        assertEq(endStream,      block.timestamp + minStartDelay + minStreamDuration);
        assertEq(endDepositLock, block.timestamp + minStartDelay + minStreamDuration + maxDepositLockDuration);
        assertEq(endRewardLock,  block.timestamp + minStartDelay + 0);

        assertEq(stream.rewardToken(),  address(testTokenA));
        assertEq(stream.depositToken(), address(testTokenB));
        assertTrue(!stream.isIndefinite());
        assertEq(stream.streamId(), 0);
        assertEq(stream.streamCreator(), address(this));
        assertEq(stream.lastUpdate(), startTime);
        
        assertEq(stream.name(),     "lockeTest Token B 0: JAN-1-2023");
        assertEq(stream.symbol(),   "lockeTTB0-JAN-1-2023");
        assertEq(stream.decimals(), 18);

        assertEq(stream.transferStartTime(), endStream);
        assertEq(stream.underlying(), address(testTokenB));
        assertEq(stream.maturity(), endDepositLock);

        assertEq(defaultStreamFactory.currStreamId(), 1);
    }

    function test_createStreamMerkle() public {
        (
            uint32 maxDepositLockDuration,
            uint32 maxRewardLockDuration,
            uint32 maxStreamDuration,
            uint32 minStreamDuration,
            uint32 minStartDelay
        ) = defaultStreamFactory.streamCreationParams();

        merkle = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            minStreamDuration,
            maxDepositLockDuration,
            0,
            false,
            bytes32(hex"1337")
        );
        vm.label(address(merkle), "MerkleStream");

        (uint16 feePercent, bool feeEnabled) = merkle.feeParams();
        assertEq(feePercent, 0);
        assertTrue(!feeEnabled);

        (
            startTime,
            endStream,
            endDepositLock,
            endRewardLock
        ) = merkle.streamParams();

        assertEq(startTime,      block.timestamp + minStartDelay);
        assertEq(endStream,      block.timestamp + minStartDelay + minStreamDuration);
        assertEq(endDepositLock, block.timestamp + minStartDelay + minStreamDuration + maxDepositLockDuration);
        assertEq(endRewardLock,  block.timestamp + minStartDelay + 0);

        assertEq(merkle.rewardToken(),  address(testTokenA));
        assertEq(merkle.depositToken(), address(testTokenB));
        assertTrue(!merkle.isIndefinite());
        assertEq(merkle.streamId(), 0);
        assertEq(merkle.streamCreator(), address(this));
        assertEq(merkle.lastUpdate(), startTime);
        
        assertEq(merkle.name(),     "lockeTest Token B 0: JAN-1-2023");
        assertEq(merkle.symbol(),   "lockeTTB0-JAN-1-2023");
        assertEq(merkle.decimals(), 18);

        assertEq(merkle.transferStartTime(), endStream);
        assertEq(merkle.underlying(), address(testTokenB));
        assertEq(merkle.maturity(), endDepositLock);

        assertEq(merkle.merkleRoot(), bytes32(hex"1337"));
        
        assertEq(defaultStreamFactory.currStreamId(), 1);
    }

    function test_createStreamTooSoonRevert() public {
        vm.expectRevert(IStreamFactory.StartTimeError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp),
            minStreamDuration,
            maxDepositLockDuration,
            0,
            false
        );
    }

    function test_createStreamStreamDurShortRevert() public {
        vm.expectRevert(IStreamFactory.StreamDurationError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            0,
            maxDepositLockDuration,
            0,
            false
        );
    }

    function test_createStreamStreamDurLongRevert() public {
        vm.expectRevert(IStreamFactory.StreamDurationError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            maxStreamDuration + 1,
            maxDepositLockDuration,
            0,
            false
        );
    }

    function test_createStreamLockDurDepositRevert() public {
        vm.expectRevert(IStreamFactory.LockDurationError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            minStreamDuration,
            maxDepositLockDuration + 1,
            0,
            false
        );
    }

    function test_createStreamLockDurRewardRevert() public {
        vm.expectRevert(IStreamFactory.LockDurationError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            minStreamDuration,
            maxDepositLockDuration,
            maxRewardLockDuration + 1,
            false
        );
    }

    function test_createStreamMerkleTooSoonRevert() public {
        vm.expectRevert(IStreamFactory.StartTimeError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp),
            minStreamDuration,
            maxDepositLockDuration,
            0,
            false,
            bytes32(hex"1337")
        );
    }

    function test_createStreamMerkleStreamDurShortRevert() public {
        vm.expectRevert(IStreamFactory.StreamDurationError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            0,
            maxDepositLockDuration,
            0,
            false,
            bytes32(hex"1337")
        );
    }

    function test_createStreamMerkleStreamDurLongRevert() public {
        vm.expectRevert(IStreamFactory.StreamDurationError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            maxStreamDuration + 1,
            maxDepositLockDuration,
            0,
            false,
            bytes32(hex"1337")
        );
    }

    function test_createStreamMerkleLockDurDepositRevert() public {
        vm.expectRevert(IStreamFactory.LockDurationError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            minStreamDuration,
            maxDepositLockDuration + 1,
            0,
            false,
            bytes32(hex"1337")
        );
    }

    function test_createStreamMerkleLockDurRewardRevert() public {
        vm.expectRevert(IStreamFactory.LockDurationError.selector);
        defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + minStartDelay),
            minStreamDuration,
            maxDepositLockDuration,
            maxRewardLockDuration + 1,
            false,
            bytes32(hex"1337")
        );
    }

    function test_updateFeeParamsNotGov() public {
        vm.prank(bob);
        vm.expectRevert(IMinimallyGoverned.NotGov.selector);
        defaultStreamFactory.updateFeeParams(IStreamFactory.GovernableFeeParams({feePercent: 0, feeEnabled: true}));
    }

    function test_updateFeeParams() public {
        defaultStreamFactory.updateFeeParams(IStreamFactory.GovernableFeeParams({feePercent: 1, feeEnabled: true}));
        (uint16 feePercent, bool feeEnabled) = defaultStreamFactory.feeParams();
        assertEq(feePercent, 1);
        assertTrue(feeEnabled);
    }

    function test_updateFeeParamsTooHighRevert() public {
        vm.expectRevert(IStreamFactory.GovParamsError.selector);
        defaultStreamFactory.updateFeeParams(IStreamFactory.GovernableFeeParams({feePercent: 501, feeEnabled: true}));
    }

    function test_updateStreamParamsNotGov() public {
        vm.prank(bob);
        vm.expectRevert(IMinimallyGoverned.NotGov.selector);
        defaultStreamFactory.updateStreamParams(IStreamFactory.GovernableStreamParams({
            maxDepositLockDuration: 52 weeks,
            maxRewardLockDuration: 52 weeks,
            maxStreamDuration: 2 weeks,
            minStreamDuration: 1 hours,
            minStartDelay: 1 days
        }));
    }


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
    //         (uint32 startTime, uint32 endStream, uint32 depositLockDuration, uint32 rewardLockDuration) = stream.streamParams();
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
    //         (uint32 startTime, uint32 endStream, uint32 depositLockDuration, uint32 rewardLockDuration) = stream.streamParams();
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