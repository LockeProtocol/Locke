// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/IStream.sol";
import "./interfaces/IReimbursementToken.sol";

abstract contract SharedState is IReimbursementToken {
    uint32 private immutable reimburse_endDepositLock;

    address private immutable reimburse_depositToken;

    constructor(address _depositToken, uint32 _edl) {
        reimburse_depositToken = _depositToken;
        reimburse_endDepositLock = _edl;
    }

    function underlying() external view override returns (address) {
        return reimburse_depositToken;
    }

    function maturity() external view override returns (uint256) {
        return reimburse_endDepositLock;
    }
}
