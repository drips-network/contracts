// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {AddressIdUser} from "./AddressIdUser.t.sol";
import {AddressIdUser} from "./AddressIdUser.t.sol";
import {DripsHubTest} from "./DripsHub.t.sol";
import {ManagedUser} from "./ManagedUser.t.sol";
import {AddressId} from "../AddressId.sol";
import {ERC20Reserve, IERC20Reserve} from "../ERC20Reserve.sol";
import {ERC20DripsHub} from "../ERC20DripsHub.sol";
import {Proxy} from "../Managed.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20DripsHubTest is DripsHubTest {
    string private constant ERROR_NOT_ADMIN = "Caller is not the admin";
    string private constant ERROR_PAUSED = "Contract paused";

    ERC20DripsHub private dripsHub;
    AddressId private addressId;
    uint256 private otherAsset;
    AddressIdUser private user;
    AddressIdUser private receiver1;
    AddressIdUser private receiver2;
    ManagedUser internal admin;
    ManagedUser internal nonAdmin;

    function setUp() public {
        defaultAsset = uint160(
            address(new ERC20PresetFixedSupply("test", "test", 10**6 * 1 ether, address(this)))
        );
        otherAsset = uint160(
            address(new ERC20PresetFixedSupply("other", "other", 10**6 * 1 ether, address(this)))
        );
        ERC20Reserve reserve = new ERC20Reserve(address(this));
        ERC20DripsHub hubLogic = new ERC20DripsHub(10, reserve);
        dripsHub = ERC20DripsHub(address(new Proxy(hubLogic, address(this))));
        reserve.addUser(address(dripsHub));
        addressId = new AddressId(dripsHub);
        user = createUser();
        receiver1 = createUser();
        receiver2 = createUser();
        admin = new ManagedUser(dripsHub);
        nonAdmin = new ManagedUser(dripsHub);
        dripsHub.changeAdmin(address(admin));
        super.setUp(dripsHub);
    }

    function wrapInProxy(ERC20DripsHub logic) internal returns (ERC20DripsHub) {
        Proxy proxy = new Proxy(logic, address(this));
        return ERC20DripsHub(address(proxy));
    }

    function createUser() internal override returns (AddressIdUser newUser) {
        newUser = new AddressIdUser(addressId);
        IERC20(address(uint160(defaultAsset))).transfer(address(newUser), 100 ether);
        IERC20(address(uint160(otherAsset))).transfer(address(newUser), 100 ether);
    }

    function testDripsInDifferentTokensAreIndependent() public {
        uint64 cycleLength = dripsHub.cycleSecs();
        // Covers 1.5 cycles of dripping
        setDrips(
            defaultAsset,
            user,
            0,
            9 * cycleLength,
            dripsReceivers(receiver1, 4, receiver2, 2)
        );

        warpToCycleEnd();
        // Covers 2 cycles of dripping
        setDrips(otherAsset, user, 0, 6 * cycleLength, dripsReceivers(receiver1, 3));

        warpToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        collectAll(defaultAsset, receiver1, 6 * cycleLength);
        // receiver1 had 1.5 cycles of 2 per second
        collectAll(defaultAsset, receiver2, 3 * cycleLength);
        // receiver1 had 1 cycle of 3 per second
        collectAll(otherAsset, receiver1, 3 * cycleLength);
        // receiver2 received nothing
        collectAll(otherAsset, receiver2, 0);

        warpToCycleEnd();
        // receiver1 received nothing
        collectAll(defaultAsset, receiver1, 0);
        // receiver2 received nothing
        collectAll(defaultAsset, receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        collectAll(otherAsset, receiver1, 3 * cycleLength);
        // receiver2 received nothing
        collectAll(otherAsset, receiver2, 0);
    }

    function testSplitsConfigurationIsCommonBetweenTokens() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setSplits(user, splitsReceivers(receiver1, totalWeight / 10));
        give(defaultAsset, receiver2, user, 30);
        give(otherAsset, receiver2, user, 100);
        collectAll(defaultAsset, user, 27, 3);
        collectAll(otherAsset, user, 90, 10);
        collectAll(defaultAsset, receiver1, 3);
        collectAll(otherAsset, receiver1, 10);
    }

    function testSetDripsRevertsWhenNotAccountOwner() public {
        try
            dripsHub.setDrips(
                calcUserId(dripsHub.nextAccountId(), 0),
                defaultAsset,
                0,
                0,
                dripsReceivers(),
                0,
                dripsReceivers()
            )
        {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid setDrips revert reason");
        }
    }

    function testGiveRevertsWhenNotAccountOwner() public {
        try dripsHub.give(calcUserId(dripsHub.nextAccountId(), 0), 0, defaultAsset, 1) {
            assertTrue(false, "Give hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid give revert reason");
        }
    }

    function testSetSplitsRevertsWhenNotAccountOwner() public {
        try dripsHub.setSplits(calcUserId(dripsHub.nextAccountId(), 0), splitsReceivers()) {
            assertTrue(false, "SetSplits hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid setSplits revert reason");
        }
    }

    function testAnyoneCanCollectForAnyoneUsingAddressId() public {
        give(user, receiver1, 5);
        split(receiver1, 5, 0);
        assertCollectable(receiver1, 5);
        uint256 balanceBefore = receiver1.balance(defaultAsset);
        IERC20 erc20 = IERC20(address(uint160(defaultAsset)));

        uint128 collected = addressId.collect(address(receiver1), erc20);

        assertEq(collected, 5, "Invalid collected amount");
        assertCollectable(receiver1, 0);
        assertBalance(receiver1, balanceBefore + 5);
    }

    function testAnyoneCanCollectAllForAnyoneUsingAddressId() public {
        give(user, receiver1, 5);
        assertCollectableAll(receiver1, 5);
        uint256 balanceBefore = receiver1.balance(defaultAsset);
        IERC20 erc20 = IERC20(address(uint160(defaultAsset)));

        (uint128 collected, uint128 split) = addressId.collectAll(
            address(receiver1),
            erc20,
            splitsReceivers()
        );

        assertEq(collected, 5, "Invalid collected amount");
        assertEq(split, 0, "Invalid split amount");
        assertCollectableAll(receiver1, 0);
        assertBalance(receiver1, balanceBefore + 5);
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
        try user.collectAll(address(user), defaultAsset, splitsReceivers()) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testReceiveDripsCanBePaused() public {
        admin.pause();
        try dripsHub.receiveDrips(user.userId(), defaultAsset, 1) {
            assertTrue(false, "ReceiveDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid receiveDrips revert reason");
        }
    }

    function testSplitCanBePaused() public {
        admin.pause();
        try dripsHub.split(user.userId(), defaultAsset, splitsReceivers()) {
            assertTrue(false, "Split hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid split revert reason");
        }
    }

    function testCollectCanBePaused() public {
        admin.pause();
        try user.collect(address(user), defaultAsset) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testSetDripsCanBePaused() public {
        admin.pause();
        try user.setDrips(defaultAsset, 0, 0, dripsReceivers(), 1, dripsReceivers()) {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setDrips revert reason");
        }
    }

    function testSetDripsFromAccountCanBePaused() public {
        admin.pause();
        try user.setDrips(defaultAsset, 0, 0, dripsReceivers(), 1, dripsReceivers()) {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setDrips revert reason");
        }
    }

    function testGiveCanBePaused() public {
        admin.pause();
        try user.give(0, defaultAsset, 1) {
            assertTrue(false, "Give hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid give revert reason");
        }
    }

    function testSetSplitsCanBePaused() public {
        admin.pause();
        try user.setSplits(splitsReceivers()) {
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
