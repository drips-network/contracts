// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {DripsHubUserUtils} from "./DripsHubUserUtils.t.sol";
import {AddressDriverUser} from "./AddressDriverUser.t.sol";
import {ManagedUser} from "./ManagedUser.t.sol";
import {AddressDriver} from "../AddressDriver.sol";
import {SplitsReceiver, DripsHub, DripsHistory, DripsReceiver} from "../DripsHub.sol";
import {Reserve} from "../Reserve.sol";
import {Proxy} from "../Upgradeable.sol";
import {
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract DripsHubTest is DripsHubUserUtils {
    AddressDriver private addressDriver;

    IERC20 private otherErc20;

    AddressDriverUser private user;
    AddressDriverUser private receiver;
    AddressDriverUser private user1;
    AddressDriverUser private receiver1;
    AddressDriverUser private user2;
    AddressDriverUser private receiver2;
    AddressDriverUser private receiver3;
    ManagedUser internal admin;
    ManagedUser internal nonAdmin;

    string internal constant ERROR_NOT_DRIVER = "Callable only by the driver";
    string private constant ERROR_NOT_ADMIN = "Caller is not the admin";
    string private constant ERROR_PAUSED = "Contract paused";
    string private constant ERROR_BALANCE_TOO_HIGH = "Total balance too high";

    function setUp() public {
        defaultErc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        otherErc20 = new ERC20PresetFixedSupply("other", "other", type(uint136).max, address(this));
        Reserve reserve = new Reserve(address(this));
        DripsHub hubLogic = new DripsHub(10, reserve);
        dripsHub = DripsHub(address(new Proxy(hubLogic, address(this))));
        reserve.addUser(address(dripsHub));
        uint32 addressDriverId = dripsHub.registerDriver(address(this));
        addressDriver = new AddressDriver(dripsHub, address(0), addressDriverId);
        dripsHub.updateDriverAddress(addressDriverId, address(addressDriver));
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
        if (receiver1 > receiver2) {
            (receiver1, receiver2) = (receiver2, receiver1);
        }
        if (receiver2 > receiver3) {
            (receiver2, receiver3) = (receiver3, receiver2);
        }
        if (receiver1 > receiver2) {
            (receiver1, receiver2) = (receiver2, receiver1);
        }
    }

    function createUser() internal returns (AddressDriverUser newUser) {
        newUser = new AddressDriverUser(addressDriver);
        defaultErc20.transfer(address(newUser), defaultErc20.totalSupply() / 100);
        otherErc20.transfer(address(newUser), otherErc20.totalSupply() / 100);
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        receiveDrips(receiver, 0, 0);
        split(receiver, 0, 0);
        collect(receiver, 0);
    }

    function testUncollectedFundsAreSplitUsingCurrentConfig() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setSplits(user1, splitsReceivers(receiver1, totalWeight));
        setDrips(user2, 0, 5, dripsReceivers(user1, 5));
        skipToCycleEnd();
        give(user2, user1, 5);
        setSplits(user1, splitsReceivers(receiver2, totalWeight));
        // Receiver1 had 1 second paying 5 per second and was given 5 of which 10 is split
        collectAll(user1, 0, 10);
        // Receiver1 wasn't a splits receiver when user1 was collecting
        collectAll(receiver1, 0);
        // Receiver2 was a splits receiver when user1 was collecting
        collectAll(receiver2, 10);
    }

    function testReceiveSomeDripsCycles() public {
        // Enough for 3 cycles
        uint128 amt = dripsHub.cycleSecs() * 3;
        skipToCycleEnd();
        setDrips(user, 0, amt, dripsReceivers(receiver, 1));
        skipToCycleEnd();
        skipToCycleEnd();
        skipToCycleEnd();
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
        skipToCycleEnd();
        setDrips(user, 0, amt, dripsReceivers(receiver, 1));
        skipToCycleEnd();
        skipToCycleEnd();
        skipToCycleEnd();

        receiveDrips(receiver, dripsHub.cycleSecs() * 3, 3);

        collectAll(receiver, amt);
    }

    function testSqueezeDrips() public {
        skipToCycleEnd();
        // Start dripping
        DripsReceiver[] memory receivers = dripsReceivers(receiver, 1);
        setDrips(user, 0, 2, receivers);

        // Create history
        uint32 lastUpdate = uint32(block.timestamp);
        uint32 maxEnd = lastUpdate + 2;
        DripsHistory[] memory history = new DripsHistory[](1);
        history[0] = DripsHistory(0, receivers, lastUpdate, maxEnd);

        // Check squeezableDrips
        skip(1);
        (uint128 amt, uint32 nextSqueezed) =
            dripsHub.squeezableDrips(receiver.userId(), defaultErc20, user.userId(), 0, history);
        assertEq(amt, 1, "Invalid squeezable amt before");
        assertEq(nextSqueezed, block.timestamp, "Invalid next squeezable before");

        // Check nextSqueezedDrips
        nextSqueezed = dripsHub.nextSqueezedDrips(receiver.userId(), defaultErc20, user.userId());
        assertEq(nextSqueezed, block.timestamp - 1, "Invalid next squeezed before");

        // Squeeze
        (amt, nextSqueezed) = receiver.squeezeDrips(defaultErc20, user.userId(), 0, history);
        assertEq(amt, 1, "Invalid squeezed amt");
        assertEq(nextSqueezed, block.timestamp, "Invalid next squeezed");

        // Check squeezableDrips
        (amt, nextSqueezed) =
            dripsHub.squeezableDrips(receiver.userId(), defaultErc20, user.userId(), 0, history);
        assertEq(amt, 0, "Invalid squeezable amt after");
        assertEq(nextSqueezed, block.timestamp, "Invalid next squeezed after");

        // Check nextSqueezedDrips
        nextSqueezed = dripsHub.nextSqueezedDrips(receiver.userId(), defaultErc20, user.userId());
        assertEq(nextSqueezed, block.timestamp, "Invalid next squeezed after");

        // Collect the squeezed amount
        split(receiver, 1, 0);
        collect(receiver, 1);
        skipToCycleEnd();
        collectAll(receiver, 1);
    }

    function testCollectTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 10;
        address transferTo = address(1234);
        give(defaultErc20, user, receiver, amt);
        split(receiver, defaultErc20, 10, 0);

        uint128 collected = receiver.collect(defaultErc20, transferTo);

        assertEq(collected, amt, "Invalid collected");
        assertCollectable(receiver, defaultErc20, 0);
        assertEq(defaultErc20.balanceOf(transferTo), amt, "Invalid balance");
    }

    function testSetDripsDecreasingBalanceTransfersFundsToTheProvidedAddress() public {
        int128 amt = 10;
        DripsReceiver[] memory receivers = dripsReceivers();
        user.setDrips(defaultErc20, receivers, amt, receivers, address(user));
        address transferTo = address(1234);

        (uint128 newBalance, int128 realBalanceDelta) =
            user.setDrips(defaultErc20, receivers, -amt, receivers, transferTo);

        assertEq(newBalance, 0, "Invalid drips balance");
        assertEq(realBalanceDelta, -amt, "Invalid balance delta");
        assertEq(defaultErc20.balanceOf(transferTo), uint128(amt), "Invalid balance");
    }

    function testFundsGivenFromUserCanBeCollected() public {
        give(user, receiver, 10);
        collectAll(receiver, 10);
    }

    function testSplitSplitsFundsReceivedFromAllSources() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        // Gives
        give(user2, user1, 1);

        // Drips
        setDrips(user2, 0, 2, dripsReceivers(user1, 2));
        skipToCycleEnd();
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

    function testRegisterDriver() public {
        address driverAddr = address(0x1234);
        uint32 driverId = dripsHub.nextDriverId();
        assertEq(address(0), dripsHub.driverAddress(driverId), "Invalid unused driver address");
        assertEq(driverId, dripsHub.registerDriver(driverAddr), "Invalid assigned driver ID");
        assertEq(driverAddr, dripsHub.driverAddress(driverId), "Invalid driver address");
        assertEq(driverId + 1, dripsHub.nextDriverId(), "Invalid next driver ID");
    }

    function testUpdateDriverAddress() public {
        uint32 driverId = dripsHub.registerDriver(address(this));
        assertEq(address(this), dripsHub.driverAddress(driverId), "Invalid driver address before");
        address newDriverAddr = address(0x1234);
        dripsHub.updateDriverAddress(driverId, newDriverAddr);
        assertEq(newDriverAddr, dripsHub.driverAddress(driverId), "Invalid driver address after");
    }

    function testUpdateDriverAddressRevertsWhenNotCalledByTheDriver() public {
        uint32 driverId = dripsHub.registerDriver(address(0x1234));
        try dripsHub.updateDriverAddress(driverId, address(0x5678)) {
            assertTrue(false, "UpdateDriverAddress hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_DRIVER, "Invalid collect revert reason");
        }
    }

    function testCollectRevertsWhenNotCalledByTheDriver() public {
        try dripsHub.collect(calcUserId(dripsHub.nextDriverId(), 0), defaultErc20) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_DRIVER, "Invalid collect revert reason");
        }
    }

    function testDripsInDifferentTokensAreIndependent() public {
        uint32 cycleLength = dripsHub.cycleSecs();
        // Covers 1.5 cycles of dripping
        setDrips(defaultErc20, user, 0, 9 * cycleLength, dripsReceivers(receiver1, 4, receiver2, 2));

        skipToCycleEnd();
        // Covers 2 cycles of dripping
        setDrips(otherErc20, user, 0, 6 * cycleLength, dripsReceivers(receiver1, 3));

        skipToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        collectAll(defaultErc20, receiver1, 6 * cycleLength);
        // receiver1 had 1.5 cycles of 2 per second
        collectAll(defaultErc20, receiver2, 3 * cycleLength);
        // receiver1 had 1 cycle of 3 per second
        collectAll(otherErc20, receiver1, 3 * cycleLength);
        // receiver2 received nothing
        collectAll(otherErc20, receiver2, 0);

        skipToCycleEnd();
        // receiver1 received nothing
        collectAll(defaultErc20, receiver1, 0);
        // receiver2 received nothing
        collectAll(defaultErc20, receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        collectAll(otherErc20, receiver1, 3 * cycleLength);
        // receiver2 received nothing
        collectAll(otherErc20, receiver2, 0);
    }

    function testSqueezeDripsRevertsWhenNotCalledByTheDriver() public {
        uint256 userId = calcUserId(dripsHub.nextDriverId(), 0);
        try dripsHub.squeezeDrips(userId, defaultErc20, 1, 0, new DripsHistory[](0)) {
            assertTrue(false, "SqueezeDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_DRIVER, "Invalid squeezeDrips revert reason");
        }
    }

    function testSetDripsRevertsWhenNotCalledByTheDriver() public {
        try dripsHub.setDrips(
            calcUserId(dripsHub.nextDriverId(), 0),
            defaultErc20,
            dripsReceivers(),
            0,
            dripsReceivers()
        ) {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_DRIVER, "Invalid setDrips revert reason");
        }
    }

    function testGiveRevertsWhenNotCalledByTheDriver() public {
        try dripsHub.give(calcUserId(dripsHub.nextDriverId(), 0), 0, defaultErc20, 1) {
            assertTrue(false, "Give hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_DRIVER, "Invalid give revert reason");
        }
    }

    function testSetSplitsRevertsWhenNotCalledByTheDriver() public {
        try dripsHub.setSplits(calcUserId(dripsHub.nextDriverId(), 0), splitsReceivers()) {
            assertTrue(false, "SetSplits hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_DRIVER, "Invalid setSplits revert reason");
        }
    }

    function testSetDripsLimitsTotalBalance() public {
        uint128 maxBalance = uint128(dripsHub.MAX_TOTAL_BALANCE());
        assertTotalBalance(0);
        setDrips(user1, 0, maxBalance, dripsReceivers());
        assertTotalBalance(maxBalance);
        assertSetDripsReverts(user2, dripsReceivers(), 1, dripsReceivers(), ERROR_BALANCE_TOO_HIGH);
        setDrips(user1, maxBalance, maxBalance - 1, dripsReceivers());
        assertTotalBalance(maxBalance - 1);
        setDrips(user2, 0, 1, dripsReceivers());
        assertTotalBalance(maxBalance);
    }

    function testGiveLimitsTotalBalance() public {
        uint128 maxBalance = uint128(dripsHub.MAX_TOTAL_BALANCE());
        assertTotalBalance(0);
        give(user1, receiver1, maxBalance - 1);
        assertTotalBalance(maxBalance - 1);
        give(user1, receiver2, 1);
        assertTotalBalance(maxBalance);
        assertGiveReverts(user2, receiver3, 1, ERROR_BALANCE_TOO_HIGH);
        collectAll(receiver2, 1);
        assertTotalBalance(maxBalance - 1);
        give(user2, receiver3, 1);
        assertTotalBalance(maxBalance);
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
        uint32 newCycleLength = dripsHub.cycleSecs() + 1;
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

    function testReceiveDripsCanBePaused() public {
        admin.pause();
        try dripsHub.receiveDrips(user.userId(), defaultErc20, 1) {
            assertTrue(false, "ReceiveDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid receiveDrips revert reason");
        }
    }

    function testSqueezeDripsCanBePaused() public {
        admin.pause();
        try user.squeezeDrips(defaultErc20, receiver.userId(), 0, new DripsHistory[](0)) {
            assertTrue(false, "SqueezeDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid squeezeDrips revert reason");
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
        try user.collect(defaultErc20, address(user)) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid collect revert reason");
        }
    }

    function testSetDripsCanBePaused() public {
        admin.pause();
        try user.setDrips(defaultErc20, dripsReceivers(), 1, dripsReceivers(), address(user)) {
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

    function testRegisterDriverCanBePaused() public {
        admin.pause();
        try dripsHub.registerDriver(address(0x1234)) {
            assertTrue(false, "RegisterDriver hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid registerDriver revert reason");
        }
    }

    function testUpdateDriverAddressCanBePaused() public {
        uint32 driverId = dripsHub.registerDriver(address(this));
        admin.pause();
        try dripsHub.updateDriverAddress(driverId, address(0x1234)) {
            assertTrue(false, "UpdateDriverAddress hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_PAUSED, "Invalid updateDriverAddress revert reason");
        }
    }
}
