// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMinimallyGoverned {
    error NotPending();
    error NotGov();

    event NewGov(address indexed oldGov, address indexed newGov);
    event NewPendingGov(address indexed oldPendingGov, address indexed newPendingGov);

    function gov() external view returns (address _gov);
    function __abdicate() external;
    function acceptGov() external;
    function pendingGov() external view returns (address _pendingGov);
    function setPendingGov(address newPendingGov) external;
}