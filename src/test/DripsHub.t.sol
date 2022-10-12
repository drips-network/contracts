// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

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
    // The ERC-20 used in all helper functions
    IERC20 internal erc20;
    IERC20 internal defaultErc20;
    IERC20 internal otherErc20;

    // Keys are user ID and ERC-20
    mapping(uint256 => mapping(IERC20 => DripsReceiver[])) internal drips;
    // Key is user IDs
    mapping(uint256 => SplitsReceiver[]) internal currSplitsReceivers;

    address internal driver;
    address internal admin;

    uint256 internal user;
    uint256 internal receiver;
    uint256 internal user1;
    uint256 internal receiver1;
    uint256 internal user2;
    uint256 internal receiver2;
    uint256 internal receiver3;

    bytes internal constant ERROR_NOT_DRIVER = "Callable only by the driver";
    bytes internal constant ERROR_NOT_ADMIN = "Caller is not the admin";
    bytes internal constant ERROR_PAUSED = "Contract paused";
    bytes internal constant ERROR_BALANCE_TOO_HIGH = "Total balance too high";

    function setUp() public {
        driver = address(1);
        admin = address(2);

        defaultErc20 = new ERC20PresetFixedSupply("default", "default", type(uint136).max, driver);
        otherErc20 = new ERC20PresetFixedSupply("other", "other", type(uint136).max, driver);
        erc20 = defaultErc20;
        Reserve reserve = new Reserve(address(this));
        DripsHub hubLogic = new DripsHub(10, reserve);
        dripsHub = DripsHub(address(new Proxy(hubLogic, admin)));
        reserve.addUser(address(dripsHub));

        uint32 driverId = dripsHub.registerDriver(driver);
        uint256 baseUserId = driverId << 224;
        user = baseUserId + 1;
        user1 = baseUserId + 2;
        user2 = baseUserId + 3;
        receiver = baseUserId + 4;
        receiver1 = baseUserId + 5;
        receiver2 = baseUserId + 6;
        receiver3 = baseUserId + 7;

        vm.prank(driver);
        defaultErc20.approve(address(reserve), UINT256_MAX);
        vm.prank(driver);
        otherErc20.approve(address(reserve), UINT256_MAX);
    }

    function skipToCycleEnd() internal {
        skip(dripsHub.cycleSecs() - (block.timestamp % dripsHub.cycleSecs()));
    }

    function loadDrips(uint256 forUser) internal returns (DripsReceiver[] memory currReceivers) {
        currReceivers = drips[forUser][erc20];
        assertDrips(forUser, currReceivers);
    }

    function storeDrips(uint256 forUser, DripsReceiver[] memory newReceivers) internal {
        assertDrips(forUser, newReceivers);
        delete drips[forUser][erc20];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            drips[forUser][erc20].push(newReceivers[i]);
        }
    }

    function getCurrSplitsReceivers(uint256 forUser)
        internal
        returns (SplitsReceiver[] memory currSplits)
    {
        currSplits = currSplitsReceivers[forUser];
        assertSplits(forUser, currSplits);
    }

    function setCurrSplitsReceivers(uint256 forUser, SplitsReceiver[] memory newReceivers)
        internal
    {
        assertSplits(forUser, newReceivers);
        delete currSplitsReceivers[forUser];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currSplitsReceivers[forUser].push(newReceivers[i]);
        }
    }

    function dripsReceivers() internal pure returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](0);
    }

    function dripsReceivers(uint256 dripsReceiver, uint128 amtPerSec)
        internal
        view
        returns (DripsReceiver[] memory list)
    {
        list = new DripsReceiver[](1);
        list[0] = DripsReceiver(
            dripsReceiver,
            DripsConfigImpl.create(0, uint160(amtPerSec * dripsHub.AMT_PER_SEC_MULTIPLIER()), 0, 0)
        );
    }

    function dripsReceivers(
        uint256 dripsReceiver1,
        uint128 amtPerSec1,
        uint256 dripsReceiver2,
        uint128 amtPerSec2
    ) internal view returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](2);
        list[0] = dripsReceivers(dripsReceiver1, amtPerSec1)[0];
        list[1] = dripsReceivers(dripsReceiver2, amtPerSec2)[0];
    }

    function setDrips(
        uint256 forUser,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        uint256 balanceBefore = balance();
        DripsReceiver[] memory currReceivers = loadDrips(forUser);

        vm.prank(driver);
        (uint128 newBalance, int128 realBalanceDelta) =
            dripsHub.setDrips(forUser, erc20, currReceivers, balanceDelta, newReceivers);

        storeDrips(forUser, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid drips balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        (,, uint32 updateTime, uint128 actualBalance,) = dripsHub.dripsState(forUser, erc20);
        assertEq(updateTime, block.timestamp, "Invalid new last update time");
        assertEq(balanceTo, actualBalance, "Invalid drips balance");
        assertEq(balanceTo, actualBalance, "Invalid drips balance");
        assertBalance(uint256(int256(balanceBefore) - balanceDelta));
    }

    function assertDrips(uint256 forUser, DripsReceiver[] memory currReceivers) internal {
        (bytes32 actual,,,,) = dripsHub.dripsState(forUser, erc20);
        bytes32 expected = dripsHub.hashDrips(currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function assertDripsBalance(uint256 forUser, uint128 expected) internal {
        uint128 actual =
            dripsHub.balanceAt(forUser, erc20, loadDrips(forUser), uint32(block.timestamp));
        assertEq(actual, expected, "Invaild drips balance");
    }

    function changeBalance(uint256 forUser, uint128 balanceFrom, uint128 balanceTo) internal {
        setDrips(forUser, balanceFrom, balanceTo, loadDrips(forUser));
    }

    function assertSetReceiversReverts(
        uint256 forUser,
        DripsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        assertSetDripsReverts(forUser, loadDrips(forUser), 0, newReceivers, expectedReason);
    }

    function assertSetDripsReverts(
        uint256 forUser,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        vm.prank(driver);
        vm.expectRevert(expectedReason);
        dripsHub.setDrips(forUser, erc20, currReceivers, balanceDelta, newReceivers);
    }

    function give(uint256 fromUser, uint256 toUser, uint128 amt) internal {
        uint256 balanceBefore = balance();
        uint128 expectedSplittable = splittable(toUser) + amt;

        vm.prank(driver);
        dripsHub.give(fromUser, toUser, erc20, amt);

        assertBalance(balanceBefore - amt);
        assertSplittable(toUser, expectedSplittable);
    }

    function assertGiveReverts(
        uint256 fromUser,
        uint256 toUser,
        uint128 amt,
        bytes memory expectedReason
    ) internal {
        vm.prank(driver);
        vm.expectRevert(expectedReason);
        dripsHub.give(fromUser, toUser, erc20, amt);
    }

    function splitsReceivers() internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](0);
    }

    function splitsReceivers(uint256 splitsReceiver, uint32 weight)
        internal
        pure
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](1);
        list[0] = SplitsReceiver(splitsReceiver, weight);
    }

    function splitsReceivers(
        uint256 splitsReceiver1,
        uint32 weight1,
        uint256 splitsReceiver2,
        uint32 weight2
    ) internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](2);
        list[0] = SplitsReceiver(splitsReceiver1, weight1);
        list[1] = SplitsReceiver(splitsReceiver2, weight2);
    }

    function setSplits(uint256 forUser, SplitsReceiver[] memory newReceivers) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(forUser);
        assertSplits(forUser, curr);

        vm.prank(driver);
        dripsHub.setSplits(forUser, newReceivers);

        setCurrSplitsReceivers(forUser, newReceivers);
        assertSplits(forUser, newReceivers);
    }

    function assertSetSplitsReverts(
        uint256 forUser,
        SplitsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(forUser);
        assertSplits(forUser, curr);
        vm.prank(driver);
        vm.expectRevert(expectedReason);
        dripsHub.setSplits(forUser, newReceivers);
    }

    function assertSplits(uint256 forUser, SplitsReceiver[] memory expectedReceivers) internal {
        bytes32 actual = dripsHub.splitsHash(forUser);
        bytes32 expected = dripsHub.hashSplits(expectedReceivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function collectAll(uint256 forUser, uint128 expectedAmt) internal {
        collectAll(forUser, expectedAmt, 0);
    }

    function collectAll(uint256 forUser, uint128 expectedCollected, uint128 expectedSplit)
        internal
    {
        (uint128 receivable,) = dripsHub.receiveDripsResult(forUser, erc20, type(uint32).max);
        (uint128 received, uint32 receivableCycles) =
            dripsHub.receiveDrips(forUser, erc20, type(uint32).max);
        assertEq(received, receivable, "Invalid received amount");
        assertEq(receivableCycles, 0, "Non-zero receivable cycles");

        split(forUser, expectedCollected - collectable(forUser), expectedSplit);

        collect(forUser, expectedCollected);
    }

    function receiveDrips(
        uint256 forUser,
        uint128 expectedReceivedAmt,
        uint32 expectedReceivedCycles
    ) internal {
        receiveDrips(forUser, type(uint32).max, expectedReceivedAmt, expectedReceivedCycles, 0, 0);
    }

    function receiveDrips(
        uint256 forUser,
        uint32 maxCycles,
        uint128 expectedReceivedAmt,
        uint32 expectedReceivedCycles,
        uint128 expectedAmtAfter,
        uint32 expectedCyclesAfter
    ) internal {
        uint128 expectedTotalAmt = expectedReceivedAmt + expectedAmtAfter;
        uint32 expectedTotalCycles = expectedReceivedCycles + expectedCyclesAfter;
        assertReceivableDripsCycles(forUser, expectedTotalCycles);
        assertReceiveDripsResult(forUser, type(uint32).max, expectedTotalAmt, 0);
        assertReceiveDripsResult(forUser, maxCycles, expectedReceivedAmt, expectedCyclesAfter);

        (uint128 receivedAmt, uint32 receivableCycles) =
            dripsHub.receiveDrips(forUser, erc20, maxCycles);

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from drips");
        assertEq(receivableCycles, expectedCyclesAfter, "Invalid receivable drips cycles left");
        assertReceivableDripsCycles(forUser, expectedCyclesAfter);
        assertReceiveDripsResult(forUser, type(uint32).max, expectedAmtAfter, 0);
    }

    function assertReceivableDripsCycles(uint256 forUser, uint32 expectedCycles) internal {
        uint32 actualCycles = dripsHub.receivableDripsCycles(forUser, erc20);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable drips cycles");
    }

    function assertReceiveDripsResult(
        uint256 forUser,
        uint32 maxCycles,
        uint128 expectedAmt,
        uint32 expectedCycles
    ) internal {
        (uint128 actualAmt, uint32 actualCycles) =
            dripsHub.receiveDripsResult(forUser, erc20, maxCycles);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
        assertEq(actualCycles, expectedCycles, "Invalid receivable drips cycles");
    }

    function split(uint256 forUser, uint128 expectedCollectable, uint128 expectedSplit) internal {
        assertSplittable(forUser, expectedCollectable + expectedSplit);
        assertSplitResult(forUser, expectedCollectable + expectedSplit, expectedCollectable);
        uint128 collectableBefore = collectable(forUser);

        (uint128 collectableAmt, uint128 splitAmt) =
            dripsHub.split(forUser, erc20, getCurrSplitsReceivers(forUser));

        assertEq(collectableAmt, expectedCollectable, "Invalid collectable amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertSplittable(forUser, 0);
        assertCollectable(forUser, collectableBefore + expectedCollectable);
    }

    function splittable(uint256 forUser) internal view returns (uint128 amt) {
        return dripsHub.splittable(forUser, erc20);
    }

    function assertSplittable(uint256 forUser, uint256 expected) internal {
        uint128 actual = splittable(forUser);
        assertEq(actual, expected, "Invalid splittable");
    }

    function assertSplitResult(uint256 forUser, uint256 amt, uint256 expected) internal {
        uint128 actual =
            dripsHub.splitResult(forUser, getCurrSplitsReceivers(forUser), uint128(amt));
        assertEq(actual, expected, "Invalid split result");
    }

    function collect(uint256 forUser, uint128 expectedAmt) internal {
        assertCollectable(forUser, expectedAmt);
        uint256 balanceBefore = balance();

        vm.prank(driver);
        uint128 actualAmt = dripsHub.collect(forUser, erc20);

        assertEq(actualAmt, expectedAmt, "Invalid collected amount");
        assertCollectable(forUser, 0);
        assertBalance(balanceBefore + expectedAmt);
    }

    function collectable(uint256 forUser) internal view returns (uint128 amt) {
        return dripsHub.collectable(forUser, erc20);
    }

    function assertCollectable(uint256 forUser, uint256 expected) internal {
        assertEq(collectable(forUser), expected, "Invalid collectable");
    }

    function assertTotalBalance(uint256 expected) internal {
        assertEq(dripsHub.totalBalance(erc20), expected, "Invalid total balance");
    }

    function balance() internal view returns (uint256) {
        return erc20.balanceOf(driver);
    }

    function assertBalance(uint256 expected) internal {
        assertEq(erc20.balanceOf(driver), expected, "Invalid balance");
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
        bytes32 actualHistoryHash =
            dripsHub.hashDripsHistory(bytes32(0), dripsHub.hashDrips(receivers), lastUpdate, maxEnd);
        (, bytes32 expectedHistoryHash,,,) = dripsHub.dripsState(user, erc20);
        assertEq(actualHistoryHash, expectedHistoryHash, "Invalid history hash");

        // Check squeezableDrips
        skip(1);
        uint128 amt = dripsHub.squeezeDripsResult(receiver, erc20, user, 0, history);
        assertEq(amt, 1, "Invalid squeezable amt before");

        // Squeeze
        vm.prank(driver);
        amt = dripsHub.squeezeDrips(receiver, erc20, user, 0, history);
        assertEq(amt, 1, "Invalid squeezed amt");

        // Check squeezableDrips
        amt = dripsHub.squeezeDripsResult(receiver, erc20, user, 0, history);
        assertEq(amt, 0, "Invalid squeezable amt after");

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

    function testEmitUserMetadata() public {
        vm.prank(driver);
        dripsHub.emitUserMetadata(user, 1, "value");
    }

    function testBalanceAt() public {
        DripsReceiver[] memory receivers = dripsReceivers(receiver, 1);
        setDrips(user, 0, 2, receivers);
        uint256 balanceAt = dripsHub.balanceAt(user, erc20, receivers, uint32(block.timestamp + 1));
        assertEq(balanceAt, 1, "Invalid balance");
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
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.collect(user, erc20);
    }

    function testDripsInDifferentTokensAreIndependent() public {
        uint32 cycleLength = dripsHub.cycleSecs();
        // Covers 1.5 cycles of dripping
        erc20 = defaultErc20;
        setDrips(user, 0, 9 * cycleLength, dripsReceivers(receiver1, 4, receiver2, 2));

        skipToCycleEnd();
        // Covers 2 cycles of dripping
        erc20 = otherErc20;
        setDrips(user, 0, 6 * cycleLength, dripsReceivers(receiver1, 3));

        skipToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        erc20 = defaultErc20;
        collectAll(receiver1, 6 * cycleLength);
        // receiver1 had 1.5 cycles of 2 per second
        erc20 = defaultErc20;
        collectAll(receiver2, 3 * cycleLength);
        // receiver1 had 1 cycle of 3 per second
        erc20 = otherErc20;
        collectAll(receiver1, 3 * cycleLength);
        // receiver2 received nothing
        erc20 = otherErc20;
        collectAll(receiver2, 0);

        skipToCycleEnd();
        // receiver1 received nothing
        erc20 = defaultErc20;
        collectAll(receiver1, 0);
        // receiver2 received nothing
        erc20 = defaultErc20;
        collectAll(receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        erc20 = otherErc20;
        collectAll(receiver1, 3 * cycleLength);
        // receiver2 received nothing
        erc20 = otherErc20;
        collectAll(receiver2, 0);
    }

    function testSetDripsRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.setDrips(user, erc20, dripsReceivers(), 0, dripsReceivers());
    }

    function testGiveRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.give(user, 0, erc20, 1);
    }

    function testSetSplitsRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.setSplits(user, splitsReceivers());
    }

    function testEmitUserMetadataRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.emitUserMetadata(user, 1, "value");
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
        uint256 userId = user;
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.receiveDrips(userId, erc20, 1);
    }

    function testSqueezeDripsCanBePaused() public {
        pauseDripsHub();
        uint256 userId = user;
        vm.expectRevert(ERROR_PAUSED);
        vm.prank(driver);
        dripsHub.squeezeDrips(user, erc20, userId, 0, new DripsHistory[](0));
    }

    function testSplitCanBePaused() public {
        pauseDripsHub();
        uint256 userId = user;
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.split(userId, erc20, splitsReceivers());
    }

    function testCollectCanBePaused() public {
        pauseDripsHub();
        vm.prank(driver);
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.collect(user, erc20);
    }

    function testSetDripsCanBePaused() public {
        pauseDripsHub();
        vm.prank(driver);
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.setDrips(user, erc20, dripsReceivers(), 1, dripsReceivers());
    }

    function testGiveCanBePaused() public {
        pauseDripsHub();
        vm.prank(driver);
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.give(user, 0, erc20, 1);
    }

    function testSetSplitsCanBePaused() public {
        pauseDripsHub();
        vm.prank(driver);
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.setSplits(user, splitsReceivers());
    }

    function testEmitUserMetadataCanBePaused() public {
        pauseDripsHub();
        vm.prank(driver);
        vm.expectRevert(ERROR_PAUSED);
        dripsHub.emitUserMetadata(user, 1, "value");
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
