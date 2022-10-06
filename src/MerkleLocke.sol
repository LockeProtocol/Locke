// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.17;

import "./Locke.sol";
import "./interfaces/IMerkleStream.sol";

library MerkleProof {
    function verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        return processProof(proof, leaf) == root;
    }

    function processProof(bytes32[] calldata proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = _efficientHash(computedHash, proofElement);
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = _efficientHash(proofElement, computedHash);
            }
        }
        return computedHash;
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}

contract MerkleStream is Stream, IMerkleStream {
    bytes32 public immutable merkleRoot;

    constructor(
        uint64 _streamId,
        address creator,
        bool _isIndefinite,
        address _rewardToken,
        address _depositToken,
        uint32 _startTime,
        uint32 _streamDuration,
        uint32 _depositLockDuration,
        uint32 _rewardLockDuration,
        bytes32 _merkleRoot
    )
        Stream(
            _streamId,
            creator,
            _isIndefinite,
            _rewardToken,
            _depositToken,
            _startTime,
            _streamDuration,
            _depositLockDuration,
            _rewardLockDuration
        )
    {
        merkleRoot = _merkleRoot;
    }

    function stake(uint112 amount, bytes32[] calldata proof) external lock updateStream {
        if (!MerkleProof.verify(proof, merkleRoot, keccak256(abi.encodePacked(msg.sender, true)))) {
            revert NoAccess();
        }
        tokenStreamForAccount[msg.sender].merkleAccess = true;
        _stake(amount);
    }

    function stake(uint112 amount) external override (Stream, IStream) lock updateStream {
        if (!tokenStreamForAccount[msg.sender].merkleAccess) {
            revert NoAccess();
        }
        _stake(amount);
    }
}
