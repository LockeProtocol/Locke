// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IStream.sol";

interface IMerkleStream is IStream {
    error NoAccess();

    function merkleRoot() external view returns (bytes32 _merkleRoot);
    function stake(uint112 amount, bytes32[] calldata proof) external;
}
