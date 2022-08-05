// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.15;

import {Managed} from "../Managed.sol";

contract ManagedUser {
    Managed private immutable managed;

    constructor(Managed managed_) {
        managed = managed_;
    }

    function changeAdmin(address newAdmin) public {
        managed.changeAdmin(newAdmin);
    }

    function pause() public {
        managed.pause();
    }

    function unpause() public {
        managed.unpause();
    }

    function upgradeTo(address newImplementation) public {
        managed.upgradeTo(newImplementation);
    }
}
