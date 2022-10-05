// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILockeCallee {
    function lockeCall(
        address initiator,
        address token,
        uint256 amount,
        bytes calldata data
    )
        external;
}
