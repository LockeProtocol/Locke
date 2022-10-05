// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import "./interfaces/IMinimallyGoverned.sol";

contract MinimallyGoverned is IMinimallyGoverned {
    address public override gov;
    address public override pendingGov;

    constructor(address _governor) {
        gov = _governor;
    }

    /// Update pending governor
    function setPendingGov(address newPendingGov) external override governed {
        address old = pendingGov;
        pendingGov = newPendingGov;
        emit NewPendingGov(old, newPendingGov);
    }

    /// Accepts governorship
    function acceptGov() external override {
        if (pendingGov != msg.sender) revert NotPending();
        address old = gov;
        gov = pendingGov;
        emit NewGov(old, pendingGov);
    }

    /// Remove governor
    function __abdicate() external override governed {
        address old = gov;
        gov = address(0);
        emit NewGov(old, address(0));
    }

    // ====== Modifiers =======
    /// Governed function
    modifier governed() {
        if (msg.sender != gov) revert NotGov();
        _;
    }
}

abstract contract MinimallyExternallyGoverned {
    MinimallyGoverned immutable gov;

    error NotGov();

    constructor(address governor) {
        gov = MinimallyGoverned(governor);
    }

    // ====== Modifiers =======
    /// Governed function
    modifier externallyGoverned() {
        if (msg.sender != gov.gov()) revert NotGov();
        _;
    }
}
