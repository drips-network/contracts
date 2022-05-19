// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {DSTest} from "ds-test/test.sol";
import {DripsHubUserUtils} from "./DripsHubUserUtils.t.sol";
import {AddressIdUser} from "./AddressIdUser.t.sol";
import {ManagedUser} from "./ManagedUser.t.sol";
import {AddressId} from "../AddressId.sol";
import {SplitsReceiver, DripsHub, DripsReceiver} from "../DripsHub.sol";
import {Reserve} from "../Reserve.sol";
import {Proxy} from "../Managed.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract DripsHubTest is DripsHubUserUtils {
    AddressId private addressId;

    IERC20 private otherErc20;

    AddressIdUser private user;
    AddressIdUser private receiver;
    AddressIdUser private user1;
    AddressIdUser private receiver1;
    AddressIdUser private user2;
    AddressIdUser private receiver2;
    AddressIdUser private receiver3;
    ManagedUser internal admin;
    ManagedUser internal nonAdmin;

    string internal constant ERROR_NOT_OWNER = "Callable only by the owner of the user account";
    string private constant ERROR_NOT_ADMIN = "Caller is not the admin";
    string private constant ERROR_PAUSED = "Contract paused";

    function setUp() public {
        defaultErc20 = new ERC20PresetFixedSupply("test", "test", 10**6 * 1 ether, address(this));
        otherErc20 = new ERC20PresetFixedSupply("other", "other", 10**6 * 1 ether, address(this));
        Reserve reserve = new Reserve(address(this));
        DripsHub hubLogic = new DripsHub(10, reserve);
        dripsHub = DripsHub(address(new Proxy(hubLogic, address(this))));
        reserve.addUser(address(dripsHub));
        addressId = new AddressId(dripsHub);
        user = createUser();
        receiver1 = createUser();
        receiver2 = createUser();
        admin = new ManagedUser(dripsHub);
        nonAdmin = new ManagedUser(dripsHub);
        dripsHub.changeAdmin(address(admin));
        user = createUser();
        user1 = createUser();
        user2 = createUser();
        receiver = createUser();
        receiver1 = createUser();
        receiver2 = createUser();
        receiver3 = createUser();
        // Sort receivers by address
        if (receiver1 > receiver2) (receiver1, receiver2) = (receiver2, receiver1);
        if (receiver2 > receiver3) (receiver2, receiver3) = (receiver3, receiver2);
        if (receiver1 > receiver2) (receiver1, receiver2) = (receiver2, receiver1);
    }

    function createUser() internal returns (AddressIdUser newUser) {
        newUser = new AddressIdUser(addressId);
        defaultErc20.transfer(address(newUser), 100 ether);
        otherErc20.transfer(address(newUser), 100 ether);
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        collectAll(receiver, 0);
    }

    function testCollectAllRevertsIfInvalidCurrSplitsReceivers() public {
        setSplits(user, splitsReceivers(receiver, 1));
        try user.collectAll(address(user), defaultErc20, splitsReceivers(receiver, 2)) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, "Invalid current splits receivers", "Invalid collect revert reason");
        }
    }

    function testCollectableAllRevertsIfInvalidCurrSplitsReceivers() public {
        setSplits(user, splitsReceivers(receiver, 1));
        try dripsHub.collectableAll(user.userId(), defaultErc20, splitsReceivers(receiver, 2)) {
            assertTrue(false, "Collectable hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(
                reason,
                "Invalid current splits receivers",
                "Invalid collectable revert reason"
            );
        }
    }

    function testCollectAllSplits() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setDrips(user, 0, 10, dripsReceivers(receiver1, 10));
        setSplits(receiver1, splitsReceivers(receiver2, totalWeight));
        warpToCycleEnd();
        assertCollectableAll(receiver2, 0);
        // Receiver1 had 1 second paying 10 per second of which 10 is split
        collectAll(receiver1, 0, 10);
        // Receiver2 got 10 split from receiver1
        collectAll(receiver2, 10);
    }

    function testUncollectedFundsAreSplitUsingCurrentConfig() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setSplits(user1, splitsReceivers(receiver1, totalWeight));
        setDrips(user2, 0, 5, dripsReceivers(user1, 5));
        warpToCycleEnd();
        give(user2, user1, 5);
        setSplits(user1, splitsReceivers(receiver2, totalWeight));
        // Receiver1 had 1 second paying 5 per second and was given 5 of which 10 is split
        collectAll(user1, 0, 10);
        // Receiver1 wasn't a splits receiver when user1 was collecting
        assertCollectableAll(receiver1, 0);
        // Receiver2 was a splits receiver when user1 was collecting
        collectAll(receiver2, 10);
    }

    function testCollectAllSplitsFundsFromSplits() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setDrips(user, 0, 10, dripsReceivers(receiver1, 10));
        setSplits(receiver1, splitsReceivers(receiver2, totalWeight));
        setSplits(receiver2, splitsReceivers(receiver3, totalWeight));
        warpToCycleEnd();
        assertCollectableAll(receiver2, 0);
        assertCollectableAll(receiver3, 0);
        // Receiver1 had 1 second paying 10 per second of which 10 is split
        collectAll(receiver1, 0, 10);
        // Receiver2 got 10 split from receiver1 of which 10 is split
        collectAll(receiver2, 0, 10);
        // Receiver3 got 10 split from receiver2
        collectAll(receiver3, 10);
    }

    function testCollectAllMixesDripsAndSplits() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setDrips(user, 0, 10, dripsReceivers(receiver1, 5, receiver2, 5));
        setSplits(receiver1, splitsReceivers(receiver2, totalWeight));
        warpToCycleEnd();
        // Receiver2 had 1 second paying 5 per second
        assertCollectableAll(receiver2, 5);
        // Receiver1 had 1 second paying 5 per second
        collectAll(receiver1, 0, 5);
        // Receiver2 had 1 second paying 5 per second and got 5 split from receiver1
        collectAll(receiver2, 10);
    }

    function testCollectAllSplitsFundsBetweenReceiverAndSplits() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setDrips(user, 0, 10, dripsReceivers(receiver1, 10));
        setSplits(
            receiver1,
            splitsReceivers(receiver2, totalWeight / 4, receiver3, totalWeight / 2)
        );
        warpToCycleEnd();
        assertCollectableAll(receiver2, 0);
        assertCollectableAll(receiver3, 0);
        // Receiver1 had 1 second paying 10 per second, of which 3/4 is split, which is 7
        collectAll(receiver1, 3, 7);
        // Receiver2 got 1/3 of 7 split from receiver1, which is 2
        collectAll(receiver2, 2);
        // Receiver3 got 2/3 of 7 split from receiver1, which is 5
        collectAll(receiver3, 5);
    }

    function testReceiveSomeDripsCycles() public {
        // Enough for 3 cycles
        uint128 amt = dripsHub.cycleSecs() * 3;
        warpToCycleEnd();
        setDrips(user, 0, amt, dripsReceivers(receiver, 1));
        warpToCycleEnd();
        warpToCycleEnd();
        warpToCycleEnd();
        receiveDrips({
            user: receiver,
            maxCycles: 2,
            expectedReceivedAmt: dripsHub.cycleSecs() * 2,
            expectedReceivedCycles: 2,
            expectedAmtAfter: dripsHub.cycleSecs(),
            expectedCyclesAfter: 1
        });
        collectAll(receiver, amt);
    }

    function testReceiveAllDripsCycles() public {
        // Enough for 3 cycles
        uint128 amt = dripsHub.cycleSecs() * 3;
        warpToCycleEnd();
        setDrips(user, 0, amt, dripsReceivers(receiver, 1));
        warpToCycleEnd();
        warpToCycleEnd();
        warpToCycleEnd();

        receiveDrips(receiver, dripsHub.cycleSecs() * 3, 3);

        collectAll(receiver, amt);
    }

    function testFundsGivenFromUserCanBeCollected() public {
        give(user, receiver, 10);
        collectAll(receiver, 10);
    }

    function testSplitSplitsFundsReceivedFromAllSources() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();

        // Gives
        give(user2, user1, 1);

        // Drips
        setDrips(user2, 0, 2, dripsReceivers(user1, 2));
        warpToCycleEnd();
        receiveDrips(user1, 2, 1);

        // Splits
        setSplits(receiver2, splitsReceivers(user1, totalWeight));
        give(receiver2, receiver2, 5);
        split(receiver2, 0, 5);

        // Split the received 1 + 2 + 5 = 8
        setSplits(user1, splitsReceivers(receiver1, totalWeight / 4));
        split(user1, 6, 2);
        collect(user1, 6);
    }

    function testSplitRevertsIfInvalidCurrSplitsReceivers() public {
        setSplits(user, splitsReceivers(receiver, 1));
        try dripsHub.split(user.userId(), defaultErc20, splitsReceivers(receiver, 2)) {
            assertTrue(false, "Split hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, "Invalid current splits receivers", "Invalid split revert reason");
        }
    }

    function testSplittingSplitsAllFundsEvenWhenTheyDontDivideEvenly() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setSplits(
            user,
            splitsReceivers(receiver1, (totalWeight / 5) * 2, receiver2, totalWeight / 5)
        );
        give(user, user, 9);
        // user gets 40% of 9, receiver1 40 % and receiver2 20%
        split(user, 4, 5);
        collectAll(receiver1, 3);
        collectAll(receiver2, 2);
    }

    function testUserCanSplitToThemselves() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        // receiver1 receives 30%, gets 50% split to themselves and receiver2 gets split 20%
        setSplits(
            receiver1,
            splitsReceivers(receiver1, totalWeight / 2, receiver2, totalWeight / 5)
        );
        give(receiver1, receiver1, 20);

        // Splitting 20
        (uint128 collectableAmt, uint128 splitAmt) = dripsHub.split(
            receiver1.userId(),
            defaultErc20,
            getCurrSplitsReceivers(receiver1)
        );
        assertEq(collectableAmt, 6, "Invalid collectable amount");
        assertEq(splitAmt, 14, "Invalid split amount");
        assertSplittable(receiver1, 10);
        collect(receiver1, 6);
        collectAll(receiver2, 4);

        // Splitting 10 which has been split to receiver1 themselves in the previous step
        (collectableAmt, splitAmt) = dripsHub.split(
            receiver1.userId(),
            defaultErc20,
            getCurrSplitsReceivers(receiver1)
        );
        assertEq(collectableAmt, 3, "Invalid collectable amount");
        assertEq(splitAmt, 7, "Invalid split amount");
        assertSplittable(receiver1, 5);
        collect(receiver1, 3);
        collectAll(receiver2, 2);
    }

    function testCreateAccount() public {
        address owner = address(0x1234);
        uint32 accountId = dripsHub.nextAccountId();
        assertEq(address(0), dripsHub.accountOwner(accountId), "Invalid nonexistent account owner");
        assertEq(accountId, dripsHub.createAccount(owner), "Invalid assigned account ID");
        assertEq(owner, dripsHub.accountOwner(accountId), "Invalid account owner");
        assertEq(accountId + 1, dripsHub.nextAccountId(), "Invalid next account ID");
    }

    function testTransferAccount() public {
        uint32 accountId = dripsHub.createAccount(address(this));
        assertEq(address(this), dripsHub.accountOwner(accountId), "Invalid account owner before");
        address newOwner = address(0x1234);
        dripsHub.transferAccount(accountId, newOwner);
        assertEq(newOwner, dripsHub.accountOwner(accountId), "Invalid account owner after");
    }

    function testTransferAccountRevertsWhenNotAccountOwner() public {
        uint32 accountId = dripsHub.createAccount(address(0x1234));
        try dripsHub.transferAccount(accountId, address(0x5678)) {
            assertTrue(false, "TransferAccount hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid collect revert reason");
        }
    }

    function testCollectRevertsWhenNotAccountOwner() public {
        try dripsHub.collect(calcUserId(dripsHub.nextAccountId(), 0), defaultErc20) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid collect revert reason");
        }
    }

    function testCollectAllRevertsWhenNotAccountOwner() public {
        try
            dripsHub.collectAll(
                calcUserId(dripsHub.nextAccountId(), 0),
                defaultErc20,
                new SplitsReceiver[](0)
            )
        {
            assertTrue(false, "CollectAll hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid collectAll revert reason");
        }
    }

    function testDripsInDifferentTokensAreIndependent() public {
        uint64 cycleLength = dripsHub.cycleSecs();
        // Covers 1.5 cycles of dripping
        setDrips(
            defaultErc20,
            user,
            0,
            9 * cycleLength,
            dripsReceivers(receiver1, 4, receiver2, 2)
        );

        warpToCycleEnd();
        // Covers 2 cycles of dripping
        setDrips(otherErc20, user, 0, 6 * cycleLength, dripsReceivers(receiver1, 3));

        warpToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        collectAll(defaultErc20, receiver1, 6 * cycleLength);
        // receiver1 had 1.5 cycles of 2 per second
        collectAll(defaultErc20, receiver2, 3 * cycleLength);
        // receiver1 had 1 cycle of 3 per second
        collectAll(otherErc20, receiver1, 3 * cycleLength);
        // receiver2 received nothing
        collectAll(otherErc20, receiver2, 0);

        warpToCycleEnd();
        // receiver1 received nothing
        collectAll(defaultErc20, receiver1, 0);
        // receiver2 received nothing
        collectAll(defaultErc20, receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        collectAll(otherErc20, receiver1, 3 * cycleLength);
        // receiver2 received nothing
        collectAll(otherErc20, receiver2, 0);
    }

    function testSplitsConfigurationIsCommonBetweenTokens() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setSplits(user, splitsReceivers(receiver1, totalWeight / 10));
        give(defaultErc20, receiver2, user, 30);
        give(otherErc20, receiver2, user, 100);
        collectAll(defaultErc20, user, 27, 3);
        collectAll(otherErc20, user, 90, 10);
        collectAll(defaultErc20, receiver1, 3);
        collectAll(otherErc20, receiver1, 10);
    }

    function testSetDripsRevertsWhenNotAccountOwner() public {
        try
            dripsHub.setDrips(
                calcUserId(dripsHub.nextAccountId(), 0),
                defaultErc20,
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
        try dripsHub.give(calcUserId(dripsHub.nextAccountId(), 0), 0, defaultErc20, 1) {
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
        uint256 balanceBefore = defaultErc20.balanceOf(address(receiver1));

        uint128 collected = addressId.collect(address(receiver1), defaultErc20);

        assertEq(collected, 5, "Invalid collected amount");
        assertCollectable(receiver1, 0);
        assertBalance(receiver1, balanceBefore + 5);
    }

    function testAnyoneCanCollectAllForAnyoneUsingAddressId() public {
        give(user, receiver1, 5);
        assertCollectableAll(receiver1, 5);
        uint256 balanceBefore = defaultErc20.balanceOf(address(receiver1));

        (uint128 collected, uint128 split) = addressId.collectAll(
            address(receiver1),
            defaultErc20,
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
        DripsHub newLogic = new DripsHub(newCycleLength, dripsHub.reserve());
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
        try user.collectAll(address(user), defaultErc20, splitsReceivers()) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testReceiveDripsCanBePaused() public {
        admin.pause();
        try dripsHub.receiveDrips(user.userId(), defaultErc20, 1) {
            assertTrue(false, "ReceiveDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid receiveDrips revert reason");
        }
    }

    function testSplitCanBePaused() public {
        admin.pause();
        try dripsHub.split(user.userId(), defaultErc20, splitsReceivers()) {
            assertTrue(false, "Split hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid split revert reason");
        }
    }

    function testCollectCanBePaused() public {
        admin.pause();
        try user.collect(address(user), defaultErc20) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testSetDripsCanBePaused() public {
        admin.pause();
        try user.setDrips(defaultErc20, dripsReceivers(), 1, dripsReceivers()) {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setDrips revert reason");
        }
    }

    function testSetDripsFromAccountCanBePaused() public {
        admin.pause();
        try user.setDrips(defaultErc20, dripsReceivers(), 1, dripsReceivers()) {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid setDrips revert reason");
        }
    }

    function testGiveCanBePaused() public {
        admin.pause();
        try user.give(0, defaultErc20, 1) {
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
