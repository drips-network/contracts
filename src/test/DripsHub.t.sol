// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {DripsHubUserUtils} from "./DripsHubUserUtils.t.sol";
import {AddressDriverUser} from "./AddressDriverUser.t.sol";
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
    address internal admin;

    bytes internal constant ERROR_NOT_DRIVER = "Callable only by the driver";
    bytes internal constant ERROR_NOT_ADMIN = "Caller is not the admin";
    bytes internal constant ERROR_PAUSED = "Contract paused";
    bytes internal constant ERROR_BALANCE_TOO_HIGH = "Total balance too high";

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
        admin = address(1);
        dripsHub.changeAdmin(admin);
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

    function pauseDripsHub() internal {
        vm.prank(admin);
        dripsHub.pause();
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
        uint32 driverId = dripsHub.registerDriver(address(1234));
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.updateDriverAddress(driverId, address(5678));
    }

    function testCollectRevertsWhenNotCalledByTheDriver() public {
        uint256 userId = calcUserId(dripsHub.nextDriverId(), 0);
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.collect(userId, defaultErc20);
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
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.squeezeDrips(userId, defaultErc20, 1, 0, new DripsHistory[](0));
    }

    function testSetDripsRevertsWhenNotCalledByTheDriver() public {
        uint256 userId = calcUserId(dripsHub.nextDriverId(), 0);
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.setDrips(userId, defaultErc20, dripsReceivers(), 0, dripsReceivers());
    }

    function testGiveRevertsWhenNotCalledByTheDriver() public {
        uint256 userId = calcUserId(dripsHub.nextDriverId(), 0);
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.give(userId, 0, defaultErc20, 1);
    }

    function testSetSplitsRevertsWhenNotCalledByTheDriver() public {
        uint256 userId = calcUserId(dripsHub.nextDriverId(), 0);
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.setSplits(userId, splitsReceivers());
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
        assertEq(dripsHub.admin(), admin);
        address newAdmin = address(1234);
        vm.prank(admin);
        dripsHub.changeAdmin(newAdmin);
        assertEq(dripsHub.admin(), newAdmin);
    }

    function testOnlyAdminCanChangeAdmin() public {
        vm.expectRevert(ERROR_NOT_ADMIN);
        dripsHub.changeAdmin(address(1234));
    }

    function testContractCanBeUpgraded() public {
        uint32 newCycleLength = dripsHub.cycleSecs() + 1;
        DripsHub newLogic = new DripsHub(newCycleLength, dripsHub.reserve());
        vm.prank(admin);
        dripsHub.upgradeTo(address(newLogic));
        assertEq(dripsHub.cycleSecs(), newCycleLength, "Invalid new cycle length");
    }

    function testOnlyAdminCanUpgradeContract() public {
        uint32 newCycleLength = dripsHub.cycleSecs() + 1;
        DripsHub newLogic = new DripsHub(newCycleLength, dripsHub.reserve());
        vm.expectRevert(ERROR_NOT_ADMIN);
        dripsHub.upgradeTo(address(newLogic));
    }

    function testContractCanBePausedAndUnpaused() public {
        assertTrue(!dripsHub.paused(), "Initially paused");
        vm.prank(admin);
        dripsHub.pause();
        assertTrue(dripsHub.paused(), "Pausing failed");
        vm.prank(admin);
        dripsHub.unpause();
        assertTrue(!dripsHub.paused(), "Unpausing failed");
    }

    function testOnlyUnpausedContractCanBePaused() public {
        pauseDripsHub();
        vm.prank(admin);
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.pause();
    }

    function testOnlyPausedContractCanBeUnpaused() public {
        vm.prank(admin);
        vm.expectRevert("Contract not paused");
        dripsHub.unpause();
    }

    function testOnlyAdminCanPause() public {
        vm.expectRevert(ERROR_NOT_ADMIN);
        dripsHub.pause();
    }

    function testOnlyAdminCanUnpause() public {
        pauseDripsHub();
        vm.expectRevert(ERROR_NOT_ADMIN);
        dripsHub.unpause();
    }

    function testReceiveDripsCanBePaused() public {
        pauseDripsHub();
        uint256 userId = user.userId();
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.receiveDrips(userId, defaultErc20, 1);
    }

    function testSqueezeDripsCanBePaused() public {
        pauseDripsHub();
        uint256 userId = user.userId();
        vm.expectRevert(ERROR_PAUSED);
        user.squeezeDrips(defaultErc20, userId, 0, new DripsHistory[](0));
    }

    function testSplitCanBePaused() public {
        pauseDripsHub();
        uint256 userId = user.userId();
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.split(userId, defaultErc20, splitsReceivers());
    }

    function testCollectCanBePaused() public {
        pauseDripsHub();
        vm.expectRevert(ERROR_PAUSED);
        user.collect(defaultErc20, address(user));
    }

    function testSetDripsCanBePaused() public {
        pauseDripsHub();
        vm.expectRevert(ERROR_PAUSED);
        user.setDrips(defaultErc20, dripsReceivers(), 1, dripsReceivers(), address(user));
    }

    function testGiveCanBePaused() public {
        pauseDripsHub();
        vm.expectRevert(ERROR_PAUSED);
        user.give(0, defaultErc20, 1);
    }

    function testSetSplitsCanBePaused() public {
        pauseDripsHub();
        vm.expectRevert(ERROR_PAUSED);
        user.setSplits(splitsReceivers());
    }

    function testRegisterDriverCanBePaused() public {
        pauseDripsHub();
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.registerDriver(address(0x1234));
    }

    function testUpdateDriverAddressCanBePaused() public {
        uint32 driverId = dripsHub.registerDriver(address(this));
        pauseDripsHub();
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.updateDriverAddress(driverId, address(0x1234));
    }
}
