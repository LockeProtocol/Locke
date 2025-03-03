// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IMerkleStream.sol";
import "./IStream.sol";

interface IStreamCreation {
    function creationCode() external view returns (bytes memory);
}

interface IMerkleStreamCreation {
    function creationCode() external view returns (bytes memory);
}

interface IStreamFactory {
    // =======  Structs  =======
    struct StreamParamsLimits {
        uint32 maxDepositLockDuration;
        uint32 maxRewardLockDuration;
        uint32 maxStreamDuration;
        uint32 minStreamDuration;
        uint32 minStartDelay;
    }

    // =======  Events  =======
    event StreamCreated(uint256 indexed stream_id, address stream_addr);
    event StreamParametersUpdated(StreamParamsLimits oldParams, StreamParamsLimits newParams);

    // ======= Errors =========
    error StartTimeError();
    error StreamDurationError();
    error LockDurationError();
    error GovParamsError();
    error DeployFailed();

    // ======  Functions  =====
    function createStream(
        address rewardToken,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        bool isIndefinite,
        bytes32 merkleRoot
    ) external returns (IMerkleStream);
    function createStream(
        address rewardToken,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        bool isIndefinite
    ) external returns (IStream);
    function currStreamId() external view returns (uint64);
    function merkleStreamCreation() external view returns (IMerkleStreamCreation);
    function streamCreation() external view returns (IStreamCreation);
    function streamCreationParams()
        external
        view
        returns (
            uint32 maxDepositLockDuration,
            uint32 maxRewardLockDuration,
            uint32 maxStreamDuration,
            uint32 minStreamDuration,
            uint32 minStartDelay
        );
}
