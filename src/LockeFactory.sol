// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.11;

import "./Locke.sol";
import "./MerkleLocke.sol";
import "./interfaces/IStreamFactory.sol";

// Bytecode size hack - allows StreamFactory to be larger than 24kb - size(type(Stream).creationCode)
contract StreamCreation is IStreamCreation {
    bytes public override constant creationCode = type(Stream).creationCode;
}

contract MerkleStreamCreation is IMerkleStreamCreation {
    bytes public override constant creationCode = type(MerkleStream).creationCode;
}

contract StreamFactory is IStreamFactory, MinimallyGoverned {
    // ======= Storage ========
    GovernableStreamParams public override streamCreationParams;
    GovernableFeeParams public override feeParams;
    uint64 public override currStreamId; 
    
    IStreamCreation public override immutable streamCreation;
    IMerkleStreamCreation public override immutable merkleStreamCreation;
    uint16 constant MAX_FEE_PERCENT = 500; // 500/10000 == 5%

    // ======= Errors =========
    error StartTimeError();
    error StreamDurationError();
    error LockDurationError();
    error GovParamsError();
    error DeployFailed();

    constructor(
        address _governor,
        address _emergency_governor,
        StreamCreation _streamCreation,
        MerkleStreamCreation _merkleStreamCreation
    ) 
        MinimallyGoverned(_governor)
    {
        streamCreation = _streamCreation;
        merkleStreamCreation = _merkleStreamCreation;
        streamCreationParams = GovernableStreamParams({
            maxDepositLockDuration: 52 weeks,
            maxRewardLockDuration: 52 weeks,
            maxStreamDuration: 2 weeks,
            minStreamDuration: 1 hours,
            minStartDelay: 1 days
        });
    }

    /**
     * @dev Deploys a minimal contract pointing to streaming logic. This contract will also be the token contract
     * for the receipt token. It custodies the depositTokens until depositLockDuration is complete. After
     * lockDuration is completed, the depositTokens can be claimed by the original depositors
     * 
    **/
    function createStream(
        address rewardToken,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        bool isIndefinite
    )
        external
        override
        returns (IStream)
    {
        // perform checks

        {
            if (startTime < block.timestamp + streamCreationParams.minStartDelay) revert StartTimeError();
            if (streamDuration < streamCreationParams.minStreamDuration || streamDuration > streamCreationParams.maxStreamDuration) revert StreamDurationError();
            if (depositLockDuration > streamCreationParams.maxDepositLockDuration || rewardLockDuration > streamCreationParams.maxRewardLockDuration) revert LockDurationError();
        }
        

        // TODO: figure out sane salt, i.e. streamid + x? streamid guaranteed to be unique
        uint64 that_stream = currStreamId;
        currStreamId += 1;
        bytes32 salt = bytes32(uint256(that_stream));

        bytes memory bytecode = abi.encodePacked(streamCreation.creationCode(), abi.encode(
            that_stream,
            msg.sender,
            isIndefinite,
            rewardToken,
            depositToken,
            startTime,
            streamDuration,
            depositLockDuration,
            rewardLockDuration,
            feeParams.feePercent,
            feeParams.feeEnabled
        ));

        IStream stream;
        assembly {
            // Deploy a new contract with our pre-made bytecode via CREATE2.
            // We start 32 bytes into the code to avoid copying the byte length.
            stream := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        if (address(stream) == address(0)) revert DeployFailed();

        emit StreamCreated(that_stream, address(stream));

        return stream;
    }

     /**
     * @dev Deploys a minimal contract pointing to streaming logic. This contract will also be the token contract
     * for the receipt token. It custodies the depositTokens until depositLockDuration is complete. After
     * lockDuration is completed, the depositTokens can be claimed by the original depositors. Adds merkle access pattern
     * 
    **/
    function createStream(
        address rewardToken,
        address depositToken,
        uint32 startTime,
        uint32 streamDuration,
        uint32 depositLockDuration,
        uint32 rewardLockDuration,
        bool isIndefinite,
        bytes32 merkleRoot
    )
        external
        override
        returns (IMerkleStream)
    {
        // perform checks

        {
            if (startTime < block.timestamp + streamCreationParams.minStartDelay) revert StartTimeError();
            if (streamDuration < streamCreationParams.minStreamDuration || streamDuration > streamCreationParams.maxStreamDuration) revert StreamDurationError();
            if (depositLockDuration > streamCreationParams.maxDepositLockDuration || rewardLockDuration > streamCreationParams.maxRewardLockDuration) revert LockDurationError();
        }
        
        bytes memory bytecode;
        {
            bytecode = abi.encodePacked(merkleStreamCreation.creationCode(), abi.encode(
                currStreamId,
                msg.sender,
                isIndefinite,
                rewardToken,
                depositToken,
                startTime,
                streamDuration,
                depositLockDuration,
                rewardLockDuration,
                feeParams.feePercent,
                feeParams.feeEnabled,
                merkleRoot
            ));
        }

        IMerkleStream stream;
        assembly {
            // Deploy a new contract with our pre-made bytecode via CREATE2.
            // We start 32 bytes into the code to avoid copying the byte length.
            stream := create2(0, add(bytecode, 32), mload(bytecode), sload(currStreamId.slot))
        }

        if (address(stream) == address(0)) revert DeployFailed();


        emit StreamCreated(currStreamId, address(stream));
        currStreamId++;
        return stream;
    }

    function updateStreamParams(GovernableStreamParams memory newParams) external override governed {
        // DATA VALIDATION:
        //  there is no real concept of "sane" limits here, and if misconfigured its ultimated
        //  not a massive deal so no data validation is done
        GovernableStreamParams memory old = streamCreationParams;
        streamCreationParams = newParams;
        emit StreamParametersUpdated(old, newParams);
    }

    function updateFeeParams(GovernableFeeParams memory newFeeParams) external override governed {
        if (newFeeParams.feePercent > MAX_FEE_PERCENT) revert GovParamsError();
        GovernableFeeParams memory old = feeParams;
        feeParams = newFeeParams;
        emit FeeParametersUpdated(old, newFeeParams);
    }
}
