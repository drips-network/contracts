// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DripsHubUser} from "./DripsHubUser.t.sol";
import {ManagedDripsHubUser} from "./ManagedDripsHubUser.t.sol";
import {DripsHubTest} from "./DripsHub.t.sol";
import {DripsReceiver, ERC20DripsHub, IERC20Reserve, SplitsReceiver} from "../ERC20DripsHub.sol";
import {ManagedDripsHub, ManagedDripsHubProxy} from "../ManagedDripsHub.sol";

abstract contract ManagedDripsHubTest is DripsHubTest {
    ManagedDripsHub private dripsHub;
    ManagedDripsHubUser internal admin;
    ManagedDripsHubUser internal nonAdmin;
    DripsHubUser private user;

    string private constant ERROR_NOT_ADMIN = "Caller is not the admin";
    string private constant ERROR_PAUSED = "Contract paused";

    // Must be called once from child contract `setUp`
    function setUp(ManagedDripsHub dripsHub_) internal {
        dripsHub = dripsHub_;
        admin = createManagedUser();
        nonAdmin = createManagedUser();
        dripsHub.changeAdmin(address(admin));
        user = createUser();
        super.setUp(dripsHub);
    }

    function createManagedUser() internal returns (ManagedDripsHubUser) {
        return new ManagedDripsHubUser(dripsHub);
    }

    function wrapInProxy(ManagedDripsHub hubLogic) internal returns (ManagedDripsHub) {
        ManagedDripsHubProxy proxy = new ManagedDripsHubProxy(hubLogic, address(this));
        return ManagedDripsHub(address(proxy));
    }

    function testAdminCanBeChanged() public {
        assertEq(dripsHub.admin(), address(admin));
        admin.changeAdmin(address(nonAdmin));
        assertEq(dripsHub.admin(), address(nonAdmin));
    }

    function testOnlyAdminCanChangeAdmin() public {
        try nonAdmin.changeAdmin(address(0x1234)) {
            assertTrue(false, "ChangeAdmin hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_ADMIN, "Invalid changeAdmin revert reason");
        }
    }

    function testContractCanBeUpgraded() public {
        uint64 newCycleLength = dripsHub.cycleSecs() + 1;
        ERC20DripsHub newLogic = new ERC20DripsHub(newCycleLength, IERC20Reserve(address(0x1234)));
        admin.upgradeTo(address(newLogic));
        assertEq(dripsHub.cycleSecs(), newCycleLength, "Invalid new cycle length");
    }

    function testOnlyAdminCanUpgradeContract() public {
        try nonAdmin.upgradeTo(address(0)) {
            assertTrue(false, "ChangeAdmin hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_ADMIN, "Invalid changeAdmin revert reason");
        }
    }

    function testContractCanBePausedAndUnpaused() public {
        assertTrue(!dripsHub.paused(), "Initially paused");
        admin.pause();
        assertTrue(dripsHub.paused(), "Pausing failed");
        admin.unpause();
        assertTrue(!dripsHub.paused(), "Unpausing failed");
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
        try nonAdmin.pause() {
            assertTrue(false, "Pause hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_ADMIN, "Invalid pause revert reason");
        }
    }

    function testOnlyAdminCanUnpause() public {
        admin.pause();
        try nonAdmin.unpause() {
            assertTrue(false, "Unpause hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_ADMIN, "Invalid unpause revert reason");
        }
    }

    function testCollectAllCanBePaused() public {
        admin.pause();
        try user.collectAll(calcUserId(user), defaultAsset, new SplitsReceiver[](0)) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testReceiveDripsCanBePaused() public {
        admin.pause();
        try dripsHub.receiveDrips(calcUserId(user), defaultAsset, 1) {
            assertTrue(false, "ReceiveDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid receiveDrips revert reason");
        }
    }

    function testSplitCanBePaused() public {
        admin.pause();
        try dripsHub.split(calcUserId(user), defaultAsset, new SplitsReceiver[](0)) {
            assertTrue(false, "Split hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid split revert reason");
        }
    }

    function testCollectCanBePaused() public {
        admin.pause();
        try user.collect(calcUserId(user), defaultAsset) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testSetDripsCanBePaused() public {
        admin.pause();
        try
            user.setDrips(
                calcUserId(user),
                defaultAsset,
                0,
                0,
                new DripsReceiver[](0),
                1,
                new DripsReceiver[](0)
            )
        {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setDrips revert reason");
        }
    }

    function testSetDripsFromAccountCanBePaused() public {
        admin.pause();
        try
            user.setDrips(
                calcUserId(user),
                defaultAsset,
                0,
                0,
                new DripsReceiver[](0),
                1,
                new DripsReceiver[](0)
            )
        {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setDrips revert reason");
        }
    }

    function testGiveCanBePaused() public {
        admin.pause();
        try user.give(calcUserId(user), 0, defaultAsset, 1) {
            assertTrue(false, "Give hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid give revert reason");
        }
    }

    function testSetSplitsCanBePaused() public {
        admin.pause();
        try user.setSplits(calcUserId(user), new SplitsReceiver[](0)) {
            assertTrue(false, "SetSplits hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setSplits revert reason");
        }
    }

    function testCreateAccountCanBePaused() public {
        admin.pause();
        try dripsHub.createAccount(address(0x1234)) {
            assertTrue(false, "CreateAccount hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid createAccount revert reason");
        }
    }
}
