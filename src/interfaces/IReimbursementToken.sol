// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7;

interface IReimbursementToken {
  /// @notice Unix time at which redemption of tokens for underlying is possible
  function maturity() external returns (uint256);

  /// @notice Treasury asset that is returned on redemption
  function underlying() external returns (address);
}