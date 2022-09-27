// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {AddressDriverUser} from "./AddressDriverUser.t.sol";
import {AddressDriver} from "../AddressDriver.sol";
import {
    SplitsReceiver, DripsConfigImpl, DripsHub, DripsHistory, DripsReceiver
} from "../DripsHub.sol";
import {Reserve} from "../Reserve.sol";
import {Proxy} from "../Upgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract DripsHubTest is Test {
    DripsHub internal dripsHub;
    IERC20 internal defaultErc20;
    IERC20 internal otherErc20;

    // Keys are user ID and ERC-20
    mapping(uint256 => mapping(IERC20 => DripsReceiver[])) internal drips;
    // Keys is user ID
    mapping(uint256 => SplitsReceiver[]) internal currSplitsReceivers;

    AddressDriver internal addressDriver;

    AddressDriverUser internal user;
    AddressDriverUser internal receiver;
    AddressDriverUser internal user1;
    AddressDriverUser internal receiver1;
    AddressDriverUser internal user2;
    AddressDriverUser internal receiver2;
    AddressDriverUser internal receiver3;
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

    function skipToCycleEnd() internal {
        skip(dripsHub.cycleSecs() - (block.timestamp % dripsHub.cycleSecs()));
    }

    function calcUserId(uint32 driverId, uint224 userIdPart) internal view returns (uint256) {
        return (uint256(driverId) << dripsHub.DRIVER_ID_OFFSET()) | userIdPart;
    }

    function loadDrips(AddressDriverUser forUser)
        internal
        returns (DripsReceiver[] memory currReceivers)
    {
        return loadDrips(defaultErc20, forUser);
    }

    function loadDrips(IERC20 erc20, AddressDriverUser forUser)
        internal
        returns (DripsReceiver[] memory currReceivers)
    {
        currReceivers = drips[forUser.userId()][erc20];
        assertDrips(erc20, forUser, currReceivers);
    }

    function storeDrips(AddressDriverUser forUser, DripsReceiver[] memory newReceivers) internal {
        storeDrips(defaultErc20, forUser, newReceivers);
    }

    function storeDrips(
        IERC20 erc20,
        AddressDriverUser forUser,
        DripsReceiver[] memory newReceivers
    ) internal {
        assertDrips(erc20, forUser, newReceivers);
        delete drips[forUser.userId()][erc20];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            drips[forUser.userId()][erc20].push(newReceivers[i]);
        }
    }

    function getCurrSplitsReceivers(AddressDriverUser forUser)
        internal
        returns (SplitsReceiver[] memory currSplits)
    {
        currSplits = currSplitsReceivers[forUser.userId()];
        assertSplits(forUser, currSplits);
    }

    function setCurrSplitsReceivers(AddressDriverUser forUser, SplitsReceiver[] memory newReceivers)
        internal
    {
        assertSplits(forUser, newReceivers);
        delete currSplitsReceivers[forUser.userId()];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currSplitsReceivers[forUser.userId()].push(newReceivers[i]);
        }
    }

    function dripsReceivers() internal pure returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](0);
    }

    function dripsReceivers(AddressDriverUser dripsReceiver, uint128 amtPerSec)
        internal
        view
        returns (DripsReceiver[] memory list)
    {
        list = new DripsReceiver[](1);
        list[0] = DripsReceiver(
            dripsReceiver.userId(),
            DripsConfigImpl.create(uint192(amtPerSec * dripsHub.AMT_PER_SEC_MULTIPLIER()), 0, 0)
        );
    }

    function dripsReceivers(
        AddressDriverUser dripsReceiver1,
        uint128 amtPerSec1,
        AddressDriverUser dripsReceiver2,
        uint128 amtPerSec2
    ) internal view returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](2);
        list[0] = DripsReceiver(
            dripsReceiver1.userId(),
            DripsConfigImpl.create(uint192(amtPerSec1 * dripsHub.AMT_PER_SEC_MULTIPLIER()), 0, 0)
        );
        list[1] = DripsReceiver(
            dripsReceiver2.userId(),
            DripsConfigImpl.create(uint192(amtPerSec2 * dripsHub.AMT_PER_SEC_MULTIPLIER()), 0, 0)
        );
    }

    function setDrips(
        AddressDriverUser forUser,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        setDrips(defaultErc20, forUser, balanceFrom, balanceTo, newReceivers);
    }

    function setDrips(
        IERC20 erc20,
        AddressDriverUser forUser,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        uint256 expectedBalance = uint256(int256(erc20.balanceOf(address(forUser))) - balanceDelta);
        DripsReceiver[] memory currReceivers = loadDrips(erc20, forUser);

        (uint128 newBalance, int128 realBalanceDelta) =
            forUser.setDrips(erc20, currReceivers, balanceDelta, newReceivers, address(forUser));

        storeDrips(erc20, forUser, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid drips balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        (,, uint32 updateTime, uint128 actualBalance,) =
            dripsHub.dripsState(forUser.userId(), erc20);
        assertEq(updateTime, block.timestamp, "Invalid new last update time");
        assertEq(balanceTo, actualBalance, "Invalid drips balance");
        assertEq(balanceTo, actualBalance, "Invalid drips balance");
        assertBalance(erc20, forUser, expectedBalance);
    }

    function assertDrips(
        IERC20 erc20,
        AddressDriverUser forUser,
        DripsReceiver[] memory currReceivers
    ) internal {
        (bytes32 actual,,,,) = dripsHub.dripsState(forUser.userId(), erc20);
        bytes32 expected = dripsHub.hashDrips(currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function assertDripsBalance(AddressDriverUser forUser, uint128 expected) internal {
        uint128 balance = dripsHub.balanceAt(
            forUser.userId(), defaultErc20, loadDrips(forUser), uint32(block.timestamp)
        );
        assertEq(balance, expected, "Invaild drips balance");
    }

    function changeBalance(AddressDriverUser forUser, uint128 balanceFrom, uint128 balanceTo)
        internal
    {
        setDrips(forUser, balanceFrom, balanceTo, loadDrips(forUser));
    }

    function assertSetReceiversReverts(
        AddressDriverUser forUser,
        DripsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        assertSetDripsReverts(forUser, loadDrips(forUser), 0, newReceivers, expectedReason);
    }

    function assertSetDripsReverts(
        AddressDriverUser forUser,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        vm.expectRevert(expectedReason);
        forUser.setDrips(defaultErc20, currReceivers, balanceDelta, newReceivers, address(forUser));
    }

    function give(AddressDriverUser fromUser, AddressDriverUser toUser, uint128 amt) internal {
        give(defaultErc20, fromUser, toUser, amt);
    }

    function give(IERC20 erc20, AddressDriverUser fromUser, AddressDriverUser toUser, uint128 amt)
        internal
    {
        uint256 expectedBalance = uint256(erc20.balanceOf(address(fromUser)) - amt);
        uint128 expectedSplittable = splittable(toUser, erc20) + amt;

        fromUser.give(toUser.userId(), erc20, amt);

        assertBalance(erc20, fromUser, expectedBalance);
        assertSplittable(toUser, erc20, expectedSplittable);
    }

    function assertGiveReverts(
        AddressDriverUser fromUser,
        AddressDriverUser toUser,
        uint128 amt,
        bytes memory expectedReason
    ) internal {
        uint256 userId = toUser.userId();
        vm.expectRevert(expectedReason);
        fromUser.give(userId, defaultErc20, amt);
    }

    function splitsReceivers() internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](0);
    }

    function splitsReceivers(AddressDriverUser splitsReceiver, uint32 weight)
        internal
        view
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](1);
        list[0] = SplitsReceiver(splitsReceiver.userId(), weight);
    }

    function splitsReceivers(
        AddressDriverUser splitsReceiver1,
        uint32 weight1,
        AddressDriverUser splitsReceiver2,
        uint32 weight2
    ) internal view returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](2);
        list[0] = SplitsReceiver(splitsReceiver1.userId(), weight1);
        list[1] = SplitsReceiver(splitsReceiver2.userId(), weight2);
    }

    function setSplits(AddressDriverUser forUser, SplitsReceiver[] memory newReceivers) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(forUser);
        assertSplits(forUser, curr);

        forUser.setSplits(newReceivers);

        setCurrSplitsReceivers(forUser, newReceivers);
        assertSplits(forUser, newReceivers);
    }

    function assertSetSplitsReverts(
        AddressDriverUser forUser,
        SplitsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(forUser);
        assertSplits(forUser, curr);
        vm.expectRevert(expectedReason);
        forUser.setSplits(newReceivers);
    }

    function assertSplits(AddressDriverUser forUser, SplitsReceiver[] memory expectedReceivers)
        internal
    {
        bytes32 actual = dripsHub.splitsHash(forUser.userId());
        bytes32 expected = dripsHub.hashSplits(expectedReceivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function collectAll(AddressDriverUser forUser, uint128 expectedAmt) internal {
        collectAll(defaultErc20, forUser, expectedAmt, 0);
    }

    function collectAll(IERC20 erc20, AddressDriverUser forUser, uint128 expectedAmt) internal {
        collectAll(erc20, forUser, expectedAmt, 0);
    }

    function collectAll(AddressDriverUser forUser, uint128 expectedCollected, uint128 expectedSplit)
        internal
    {
        collectAll(defaultErc20, forUser, expectedCollected, expectedSplit);
    }

    function collectAll(
        IERC20 erc20,
        AddressDriverUser forUser,
        uint128 expectedCollected,
        uint128 expectedSplit
    ) internal {
        (uint128 receivable,) = dripsHub.receivableDrips(forUser.userId(), erc20, type(uint32).max);
        (uint128 received, uint32 receivableCycles) =
            dripsHub.receiveDrips(forUser.userId(), erc20, type(uint32).max);
        assertEq(received, receivable, "Invalid received amount");
        assertEq(receivableCycles, 0, "Non-zero receivable cycles");

        split(forUser, erc20, expectedCollected - collectable(forUser, erc20), expectedSplit);

        collect(forUser, erc20, expectedCollected);
    }

    function receiveDrips(
        AddressDriverUser forUser,
        uint128 expectedReceivedAmt,
        uint32 expectedReceivedCycles
    ) internal {
        receiveDrips(forUser, type(uint32).max, expectedReceivedAmt, expectedReceivedCycles, 0, 0);
    }

    function receiveDrips(
        AddressDriverUser forUser,
        uint32 maxCycles,
        uint128 expectedReceivedAmt,
        uint32 expectedReceivedCycles,
        uint128 expectedAmtAfter,
        uint32 expectedCyclesAfter
    ) internal {
        uint128 expectedTotalAmt = expectedReceivedAmt + expectedAmtAfter;
        uint32 expectedTotalCycles = expectedReceivedCycles + expectedCyclesAfter;
        assertReceivableDripsCycles(forUser, expectedTotalCycles);
        assertReceivableDrips(forUser, type(uint32).max, expectedTotalAmt, 0);
        assertReceivableDrips(forUser, maxCycles, expectedReceivedAmt, expectedCyclesAfter);

        (uint128 receivedAmt, uint32 receivableCycles) =
            dripsHub.receiveDrips(forUser.userId(), defaultErc20, maxCycles);

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from drips");
        assertEq(receivableCycles, expectedCyclesAfter, "Invalid receivable drips cycles left");
        assertReceivableDripsCycles(forUser, expectedCyclesAfter);
        assertReceivableDrips(forUser, type(uint32).max, expectedAmtAfter, 0);
    }

    function assertReceivableDripsCycles(AddressDriverUser forUser, uint32 expectedCycles)
        internal
    {
        uint32 actualCycles = dripsHub.receivableDripsCycles(forUser.userId(), defaultErc20);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable drips cycles");
    }

    function assertReceivableDrips(
        AddressDriverUser forUser,
        uint32 maxCycles,
        uint128 expectedAmt,
        uint32 expectedCycles
    ) internal {
        (uint128 actualAmt, uint32 actualCycles) =
            dripsHub.receivableDrips(forUser.userId(), defaultErc20, maxCycles);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
        assertEq(actualCycles, expectedCycles, "Invalid receivable drips cycles");
    }

    function split(AddressDriverUser forUser, uint128 expectedCollectable, uint128 expectedSplit)
        internal
    {
        split(forUser, defaultErc20, expectedCollectable, expectedSplit);
    }

    function split(
        AddressDriverUser forUser,
        IERC20 erc20,
        uint128 expectedCollectable,
        uint128 expectedSplit
    ) internal {
        assertSplittable(forUser, erc20, expectedCollectable + expectedSplit);
        assertSplitResults(forUser, expectedCollectable + expectedSplit, expectedCollectable);
        uint128 collectableBefore = collectable(forUser, erc20);

        (uint128 collectableAmt, uint128 splitAmt) =
            dripsHub.split(forUser.userId(), erc20, getCurrSplitsReceivers(forUser));

        assertEq(collectableAmt, expectedCollectable, "Invalid collectable amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertSplittable(forUser, erc20, 0);
        assertCollectable(forUser, erc20, collectableBefore + expectedCollectable);
    }

    function splittable(AddressDriverUser forUser, IERC20 erc20)
        internal
        view
        returns (uint128 amt)
    {
        return dripsHub.splittable(forUser.userId(), erc20);
    }

    function assertSplittable(AddressDriverUser forUser, IERC20 erc20, uint256 expected) internal {
        uint128 actual = splittable(forUser, erc20);
        assertEq(actual, expected, "Invalid splittable");
    }

    function assertSplitResults(AddressDriverUser forUser, uint256 amt, uint256 expected)
        internal
    {
        uint128 actual =
            dripsHub.splitResults(forUser.userId(), getCurrSplitsReceivers(forUser), uint128(amt));
        assertEq(actual, expected, "Invalid split results");
    }

    function collect(AddressDriverUser forUser, uint128 expectedAmt) internal {
        collect(forUser, defaultErc20, expectedAmt);
    }

    function collect(AddressDriverUser forUser, IERC20 erc20, uint128 expectedAmt) internal {
        assertCollectable(forUser, erc20, expectedAmt);
        uint256 balanceBefore = erc20.balanceOf(address(forUser));

        uint128 actualAmt = forUser.collect(erc20, address(forUser));

        assertEq(actualAmt, expectedAmt, "Invalid collected amount");
        assertCollectable(forUser, erc20, 0);
        assertBalance(erc20, forUser, balanceBefore + expectedAmt);
    }

    function collectable(AddressDriverUser forUser) internal view returns (uint128 amt) {
        return collectable(forUser, defaultErc20);
    }

    function collectable(AddressDriverUser forUser, IERC20 erc20)
        internal
        view
        returns (uint128 amt)
    {
        return dripsHub.collectable(forUser.userId(), erc20);
    }

    function assertCollectable(AddressDriverUser forUser, uint256 expected) internal {
        assertCollectable(forUser, defaultErc20, expected);
    }

    function assertCollectable(AddressDriverUser forUser, IERC20 erc20, uint256 expected)
        internal
    {
        assertEq(collectable(forUser, erc20), expected, "Invalid collectable");
    }

    function assertTotalBalance(uint256 expected) internal {
        assertEq(dripsHub.totalBalance(defaultErc20), expected, "Invalid total balance");
    }

    function assertBalance(AddressDriverUser forUser, uint256 expected) internal {
        assertBalance(defaultErc20, forUser, expected);
    }

    function assertBalance(IERC20 erc20, AddressDriverUser forUser, uint256 expected) internal {
        assertEq(erc20.balanceOf(address(forUser)), expected, "Invalid balance");
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
            forUser: receiver,
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
