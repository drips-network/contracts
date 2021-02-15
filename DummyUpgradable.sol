// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

import "./Proxy.sol";
import "./ProxyAdminStorage.sol";

/// A dummy upgradable contract.
contract DummyUpgradable {
    function upgrade(Proxy proxy) public {
        require(msg.sender == proxy.admin(), "only the proxy admin can change implementations");
        require(proxy._acceptImplementation() == 0, "change must be authorized");
    }
}

/// V1.
contract DummyUpgradableV1 is ProxyAdminStorage, DummyUpgradable {
    uint256 private constant VERSION = 1;

    function version() public pure returns (uint256) {
        return VERSION;
    }
}

/// V2.
contract DummyUpgradableV2 is ProxyAdminStorage, DummyUpgradable {
    uint256 private constant VERSION = 2;

    function version() public pure returns (uint256) {
        return VERSION;
    }
}
