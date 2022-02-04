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
    struct GovernableStreamParams {
        uint32 maxDepositLockDuration;
        uint32 maxRewardLockDuration;
        uint32 maxStreamDuration;
        uint32 minStreamDuration;
        uint32 minStartDelay;
    }

    struct GovernableFeeParams {
        uint16 feePercent;
        bool feeEnabled;
    }

    // =======  Events  =======
    event StreamCreated(uint256 indexed stream_id, address stream_addr);
    event StreamParametersUpdated(GovernableStreamParams oldParams, GovernableStreamParams newParams);
    event FeeParametersUpdated(GovernableFeeParams oldParams, GovernableFeeParams newParams);

    // ======  Functions  =====
    function createStream(address rewardToken,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        bool isIndefinite,
        bytes32 merkleRoot
    ) external returns (IMerkleStream);
    function createStream(address rewardToken,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        bool isIndefinite
    ) external returns (IStream);
    function currStreamId() external view returns (uint64);
    function feeParams() external view returns (uint16 feePercent, bool feeEnabled);
    function merkleStreamCreation() external view returns (IMerkleStreamCreation);
    function streamCreation() external view returns (IStreamCreation);
    function streamCreationParams() external view returns (
        uint32 maxDepositLockDuration,
        uint32 maxRewardLockDuration,
        uint32 maxStreamDuration,
        uint32 minStreamDuration,
        uint32 minStartDelay
    );
    function updateFeeParams(GovernableFeeParams calldata newFeeParams) external;
    function updateStreamParams(GovernableStreamParams calldata newParams) external;
}