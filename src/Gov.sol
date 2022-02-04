// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import "./interfaces/IGov.sol";

contract MinimallyGoverned is IGov {
    address public override gov;
    address public override pendingGov;

    error NotPending();
    error NotGov();

    event NewGov(address indexed oldGov, address indexed newGov);
    event NewPendingGov(address indexed oldPendingGov, address indexed newPendingGov);

    constructor(address _governor) {
        gov = _governor;
    }

    /// Update pending governor
    function setPendingGov(address newPendingGov) governed external override {
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
    function __abdicate() governed external override {
        address old = gov;
        gov = address(0);
        emit NewGov(old, address(0));
    }

    // ====== Modifiers =======
    /// Governed function
    modifier governed {
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
    modifier externallyGoverned {
        if (msg.sender != gov.gov()) revert NotGov();
        _;
    }
}
