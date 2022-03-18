// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {ManagedDripsHub} from "../ManagedDripsHub.sol";

contract ManagedDripsHubUser {
    ManagedDripsHub private immutable dripsHub;

    constructor(ManagedDripsHub dripsHub_) {
        dripsHub = dripsHub_;
    }

    function changeAdmin(address newAdmin) public {
        dripsHub.changeAdmin(newAdmin);
    }

    function pause() public {
        dripsHub.pause();
    }

    function unpause() public {
        dripsHub.unpause();
    }

    function upgradeTo(address newImplementation) public {
        dripsHub.upgradeTo(newImplementation);
    }
}
