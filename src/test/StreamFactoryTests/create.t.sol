// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

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

        StreamFactory sf = new StreamFactory(sc, msc);

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
        (uint32 maxDepositLockDuration,,, uint32 minStreamDuration, uint32 minStartDelay) =
            defaultStreamFactory.streamCreationParams();

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

        (startTime, endStream, endDepositLock, endRewardLock) = stream.streamParams();

        assertEq(startTime, block.timestamp + minStartDelay);
        assertEq(endStream, block.timestamp + minStartDelay + minStreamDuration);
        assertEq(endDepositLock, block.timestamp + minStartDelay + minStreamDuration + maxDepositLockDuration);
        assertEq(endRewardLock, block.timestamp + minStartDelay + 0);

        assertEq(stream.rewardToken(), address(testTokenA));
        assertEq(stream.depositToken(), address(testTokenB));
        assertTrue(!stream.isIndefinite());
        assertEq(stream.streamId(), 0);
        assertEq(stream.streamCreator(), address(this));
        assertEq(stream.lastUpdate(), startTime);

        assertEq(stream.name(), "lockeTest Token B 0: JAN-1-2023");
        assertEq(stream.symbol(), "lockeTTB0-JAN-1-2023");
        assertEq(stream.decimals(), 18);

        assertEq(stream.transferStartTime(), endStream);
        assertEq(stream.underlying(), address(testTokenB));
        assertEq(stream.maturity(), endDepositLock);

        assertEq(defaultStreamFactory.currStreamId(), 1);
    }

    function test_createStreamMerkle() public {
        (uint32 maxDepositLockDuration,,, uint32 minStreamDuration, uint32 minStartDelay) =
            defaultStreamFactory.streamCreationParams();

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

        (startTime, endStream, endDepositLock, endRewardLock) = merkle.streamParams();

        assertEq(startTime, block.timestamp + minStartDelay);
        assertEq(endStream, block.timestamp + minStartDelay + minStreamDuration);
        assertEq(endDepositLock, block.timestamp + minStartDelay + minStreamDuration + maxDepositLockDuration);
        assertEq(endRewardLock, block.timestamp + minStartDelay + 0);

        assertEq(merkle.rewardToken(), address(testTokenA));
        assertEq(merkle.depositToken(), address(testTokenB));
        assertTrue(!merkle.isIndefinite());
        assertEq(merkle.streamId(), 0);
        assertEq(merkle.streamCreator(), address(this));
        assertEq(merkle.lastUpdate(), startTime);

        assertEq(merkle.name(), "lockeTest Token B 0: JAN-1-2023");
        assertEq(merkle.symbol(), "lockeTTB0-JAN-1-2023");
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
}
