// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGov {
    function gov() external view returns (address);
    function __abdicate() external;
    function acceptGov() external;
    function pendingGov() external view returns (address);
    function setPendingGov(address newPendingGov) external;
}