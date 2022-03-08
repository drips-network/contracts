// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DripsHubUser, ManagedDripsHubUser} from "./DripsHubUser.t.sol";
import {DripsHubTest} from "./DripsHub.t.sol";
import {DripsReceiver, SplitsReceiver} from "../DripsHub.sol";
import {ManagedDripsHub, ManagedDripsHubProxy} from "../ManagedDripsHub.sol";

abstract contract ManagedDripsHubTest is DripsHubTest {
    ManagedDripsHub private dripsHub;
    ManagedDripsHubUser internal admin;
    ManagedDripsHubUser private user;
    ManagedDripsHubUser private user1;
    ManagedDripsHubUser private user2;

    string private constant ERROR_NOT_ADMIN = "Caller is not the admin";
    string private constant ERROR_PAUSED = "Contract paused";

    // Must be called once from child contract `setUp`
    function setUp(ManagedDripsHub dripsHub_) internal {
        dripsHub = dripsHub_;
        admin = createManagedUser();
        dripsHub.changeAdmin(address(admin));
        user = createManagedUser();
        user1 = createManagedUser();
        user2 = createManagedUser();
        super.setUp(dripsHub);
    }

    function createUser() internal override returns (DripsHubUser) {
        return createManagedUser();
    }

    function createManagedUser() internal virtual returns (ManagedDripsHubUser);

    function wrapInProxy(ManagedDripsHub hubLogic) internal returns (ManagedDripsHub) {
        ManagedDripsHubProxy proxy = new ManagedDripsHubProxy(hubLogic, address(this));
        return ManagedDripsHub(address(proxy));
    }

    function testAdminCanBeChanged() public {
        assertEq(admin.admin(), address(admin));
        admin.changeAdmin(address(user));
        assertEq(admin.admin(), address(user));
    }

    function testOnlyAdminCanChangeAdmin() public {
        try user1.changeAdmin(address(user2)) {
            assertTrue(false, "ChangeAdmin hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_ADMIN, "Invalid changeAdmin revert reason");
        }
    }

    function testContractCanBeUpgraded() public virtual;

    function testOnlyAdminCanUpgradeContract() public {
        try user.upgradeTo(address(0)) {
            assertTrue(false, "ChangeAdmin hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_ADMIN, "Invalid changeAdmin revert reason");
        }
    }

    function testContractCanBePausedAndUnpaused() public {
        assertTrue(!admin.paused(), "Initially paused");
        admin.pause();
        assertTrue(admin.paused(), "Pausing failed");
        admin.unpause();
        assertTrue(!admin.paused(), "Unpausing failed");
    }

    function testOnlyUnpausedContractCanBePaused() public {
        admin.pause();
        try admin.pause() {
            assertTrue(false, "Pause hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid pause revert reason");
        }
    }

    function testOnlyPausedContractCanBeUnpaused() public {
        try admin.unpause() {
            assertTrue(false, "Unpause hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, "Contract not paused", "Invalid unpause revert reason");
        }
    }

    function testOnlyAdminCanPause() public {
        try user.pause() {
            assertTrue(false, "Pause hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_ADMIN, "Invalid pause revert reason");
        }
    }

    function testOnlyAdminCanUnpause() public {
        admin.pause();
        try user.unpause() {
            assertTrue(false, "Unpause hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_ADMIN, "Invalid unpause revert reason");
        }
    }

    function testCollectAllCanBePaused() public {
        admin.pause();
        try admin.collectAll(address(admin), defaultAsset, new SplitsReceiver[](0)) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testReceiveDripsCanBePaused() public {
        admin.pause();
        try admin.receiveDrips(defaultAsset, 1) {
            assertTrue(false, "ReceiveDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid receiveDrips revert reason");
        }
    }

    function testSplitCanBePaused() public {
        admin.pause();
        try admin.split(address(admin), defaultAsset, new SplitsReceiver[](0)) {
            assertTrue(false, "Split hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid split revert reason");
        }
    }

    function testCollectCanBePaused() public {
        admin.pause();
        try admin.collect(address(admin), defaultAsset) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testSetDripsCanBePaused() public {
        admin.pause();
        try admin.setDrips(defaultAsset, 0, 0, new DripsReceiver[](0), 1, new DripsReceiver[](0)) {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setDrips revert reason");
        }
    }

    function testSetDripsFromAccountCanBePaused() public {
        admin.pause();
        try admin.setDrips(defaultAsset, 0, 0, new DripsReceiver[](0), 1, new DripsReceiver[](0)) {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setDrips revert reason");
        }
    }

    function testGiveCanBePaused() public {
        admin.pause();
        try admin.give(address(user), defaultAsset, 1) {
            assertTrue(false, "Give hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid give revert reason");
        }
    }

    function testGiveFromAccountCanBePaused() public {
        admin.pause();
        try admin.give(0, address(user), defaultAsset, 1) {
            assertTrue(false, "Give hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid giveFrom revert reason");
        }
    }

    function testSetSplitsCanBePaused() public {
        admin.pause();
        try admin.setSplits(new SplitsReceiver[](0)) {
            assertTrue(false, "SetSplits hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setSplits revert reason");
        }
    }
}
