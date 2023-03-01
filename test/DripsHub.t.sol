// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {
    SplitsReceiver,
    DripsConfigImpl,
    DripsHub,
    DripsHistory,
    DripsReceiver,
    UserMetadata
} from "src/DripsHub.sol";
import {ManagedProxy} from "src/Managed.sol";
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
    mapping(uint256 => mapping(IERC20 => DripsReceiver[])) internal currDripsReceivers;
    // Key is user IDs
    mapping(uint256 => SplitsReceiver[]) internal currSplitsReceivers;

    address internal driver = address(1);
    address internal admin = address(2);

    uint32 internal driverId;

    uint256 internal user;
    uint256 internal receiver;
    uint256 internal user1;
    uint256 internal receiver1;
    uint256 internal user2;
    uint256 internal receiver2;
    uint256 internal receiver3;

    bytes internal constant ERROR_NOT_DRIVER = "Callable only by the driver";
    bytes internal constant ERROR_BALANCE_TOO_HIGH = "Total balance too high";
    bytes internal constant ERROR_ERC_20_BALANCE_TOO_LOW = "ERC-20 balance too low";

    function setUp() public {
        defaultErc20 = new ERC20PresetFixedSupply("default", "default", 2 ** 128, address(this));
        otherErc20 = new ERC20PresetFixedSupply("other", "other", 2 ** 128, address(this));
        erc20 = defaultErc20;
        DripsHub hubLogic = new DripsHub(10);
        dripsHub = DripsHub(address(new ManagedProxy(hubLogic, admin)));

        driverId = dripsHub.registerDriver(driver);
        uint256 baseUserId = driverId << 224;
        user = baseUserId + 1;
        user1 = baseUserId + 2;
        user2 = baseUserId + 3;
        receiver = baseUserId + 4;
        receiver1 = baseUserId + 5;
        receiver2 = baseUserId + 6;
        receiver3 = baseUserId + 7;
    }

    function skipToCycleEnd() internal {
        skip(dripsHub.cycleSecs() - (block.timestamp % dripsHub.cycleSecs()));
    }

    function loadDrips(uint256 forUser) internal returns (DripsReceiver[] memory currReceivers) {
        currReceivers = currDripsReceivers[forUser][erc20];
        assertDrips(forUser, currReceivers);
    }

    function storeDrips(uint256 forUser, DripsReceiver[] memory newReceivers) internal {
        assertDrips(forUser, newReceivers);
        delete currDripsReceivers[forUser][erc20];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currDripsReceivers[forUser][erc20].push(newReceivers[i]);
        }
    }

    function loadSplits(uint256 forUser) internal returns (SplitsReceiver[] memory currSplits) {
        currSplits = currSplitsReceivers[forUser];
        assertSplits(forUser, currSplits);
    }

    function storeSplits(uint256 forUser, SplitsReceiver[] memory newReceivers) internal {
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
        uint256 dripsHubBalanceBefore = dripsHubBalance();
        uint256 totalBalanceBefore = totalBalance();
        DripsReceiver[] memory currReceivers = loadDrips(forUser);

        if (balanceDelta > 0) transferToDripsHub(uint128(balanceDelta));
        vm.prank(driver);
        int128 realBalanceDelta =
            dripsHub.setDrips(forUser, erc20, currReceivers, balanceDelta, newReceivers, 0, 0);
        if (balanceDelta < 0) withdraw(uint128(-balanceDelta));

        storeDrips(forUser, newReceivers);
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        (,, uint32 updateTime, uint128 actualBalance,) = dripsHub.dripsState(forUser, erc20);
        assertEq(updateTime, block.timestamp, "Invalid new last update time");
        assertEq(balanceTo, actualBalance, "Invalid drips balance");
        assertBalance(uint256(int256(balanceBefore) - balanceDelta));
        assertDripsHubBalance(uint256(int256(dripsHubBalanceBefore) + balanceDelta));
        assertTotalBalance(uint256(int256(totalBalanceBefore) + balanceDelta));
    }

    function assertDrips(uint256 forUser, DripsReceiver[] memory currReceivers) internal {
        (bytes32 actual,,,,) = dripsHub.dripsState(forUser, erc20);
        bytes32 expected = dripsHub.hashDrips(currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function give(uint256 fromUser, uint256 toUser, uint128 amt) internal {
        uint256 balanceBefore = balance();
        uint256 dripsHubBalanceBefore = dripsHubBalance();
        uint256 totalBalanceBefore = totalBalance();
        uint128 expectedSplittable = splittable(toUser) + amt;

        transferToDripsHub(amt);
        vm.prank(driver);
        dripsHub.give(fromUser, toUser, erc20, amt);

        assertBalance(balanceBefore - amt);
        assertDripsHubBalance(dripsHubBalanceBefore + amt);
        assertTotalBalance(totalBalanceBefore + amt);
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
        SplitsReceiver[] memory curr = loadSplits(forUser);
        assertSplits(forUser, curr);

        vm.prank(driver);
        dripsHub.setSplits(forUser, newReceivers);

        storeSplits(forUser, newReceivers);
        assertSplits(forUser, newReceivers);
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
        uint128 receivable = dripsHub.receiveDripsResult(forUser, erc20, type(uint32).max);
        uint32 receivableCycles = dripsHub.receivableDripsCycles(forUser, erc20);
        receiveDrips(forUser, receivable, receivableCycles);

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
        assertReceiveDripsResult(forUser, type(uint32).max, expectedTotalAmt);
        assertReceiveDripsResult(forUser, maxCycles, expectedReceivedAmt);

        uint128 receivedAmt = dripsHub.receiveDrips(forUser, erc20, maxCycles);

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from drips");
        assertReceivableDripsCycles(forUser, expectedCyclesAfter);
        assertReceiveDripsResult(forUser, type(uint32).max, expectedAmtAfter);
    }

    function assertReceivableDripsCycles(uint256 forUser, uint32 expectedCycles) internal {
        uint32 actualCycles = dripsHub.receivableDripsCycles(forUser, erc20);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable drips cycles");
    }

    function assertReceiveDripsResult(uint256 forUser, uint32 maxCycles, uint128 expectedAmt)
        internal
    {
        uint128 actualAmt = dripsHub.receiveDripsResult(forUser, erc20, maxCycles);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
    }

    function split(uint256 forUser, uint128 expectedCollectable, uint128 expectedSplit) internal {
        assertSplittable(forUser, expectedCollectable + expectedSplit);
        assertSplitResult(forUser, expectedCollectable + expectedSplit, expectedCollectable);
        uint128 collectableBefore = collectable(forUser);

        (uint128 collectableAmt, uint128 splitAmt) =
            dripsHub.split(forUser, erc20, loadSplits(forUser));

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
        (uint128 collectableAmt, uint128 splitAmt) =
            dripsHub.splitResult(forUser, loadSplits(forUser), uint128(amt));
        assertEq(collectableAmt, expected, "Invalid collectable amount");
        assertEq(splitAmt, amt - expected, "Invalid split amount");
    }

    function collect(uint256 forUser, uint128 expectedAmt) internal {
        assertCollectable(forUser, expectedAmt);
        uint256 balanceBefore = balance();
        uint256 dripsHubBalanceBefore = dripsHubBalance();
        uint256 totalBalanceBefore = totalBalance();

        vm.prank(driver);
        uint128 actualAmt = dripsHub.collect(forUser, erc20);
        withdraw(actualAmt);

        assertEq(actualAmt, expectedAmt, "Invalid collected amount");
        assertCollectable(forUser, 0);
        assertBalance(balanceBefore + expectedAmt);
        assertDripsHubBalance(dripsHubBalanceBefore - expectedAmt);
        assertTotalBalance(totalBalanceBefore - expectedAmt);
    }

    function collectable(uint256 forUser) internal view returns (uint128 amt) {
        return dripsHub.collectable(forUser, erc20);
    }

    function assertCollectable(uint256 forUser, uint256 expected) internal {
        assertEq(collectable(forUser), expected, "Invalid collectable");
    }

    function totalBalance() internal view returns (uint256) {
        return dripsHub.totalBalance(erc20);
    }

    function assertTotalBalance(uint256 expected) internal {
        assertEq(totalBalance(), expected, "Invalid total balance");
    }

    function transferToDripsHub(uint256 amt) internal {
        assertDripsHubBalance(totalBalance());
        erc20.transfer(address(dripsHub), amt);
    }

    function withdraw(uint256 amt) internal {
        uint256 balanceBefore = balance();
        uint256 totalBalanceBefore = totalBalance();
        assertDripsHubBalance(totalBalanceBefore + amt);

        dripsHub.withdraw(erc20, address(this), amt);

        assertBalance(balanceBefore + amt);
        assertTotalBalance(totalBalanceBefore);
        assertDripsHubBalance(totalBalanceBefore);
    }

    function balance() internal view returns (uint256) {
        return erc20.balanceOf(address(this));
    }

    function assertBalance(uint256 expected) internal {
        assertEq(balance(), expected, "Invalid balance");
    }

    function dripsHubBalance() internal view returns (uint256) {
        return erc20.balanceOf(address(dripsHub));
    }

    function assertDripsHubBalance(uint256 expected) internal {
        assertEq(dripsHubBalance(), expected, "Invalid DripsHub balance");
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        receiveDrips(receiver, 0, 0);
        split(receiver, 0, 0);
        collect(receiver, 0);
    }

    function testSetDripsLimitsWithdrawalToDripsBalance() public {
        uint128 dripsBalance = 10;
        DripsReceiver[] memory receivers = dripsReceivers();
        uint256 balanceBefore = balance();
        setDrips(user, 0, dripsBalance, receivers);

        vm.prank(driver);
        int128 realBalanceDelta =
            dripsHub.setDrips(user, erc20, receivers, -int128(dripsBalance) - 1, receivers, 0, 0);
        withdraw(uint128(-realBalanceDelta));

        assertEq(realBalanceDelta, -int128(dripsBalance), "Invalid real balance delta");
        (,,, uint128 actualBalance,) = dripsHub.dripsState(user, erc20);
        assertEq(actualBalance, 0, "Invalid drips balance");
        assertBalance(balanceBefore);
        assertDripsHubBalance(0);
        assertTotalBalance(0);
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
        UserMetadata[] memory userMetadata = new UserMetadata[](2);
        userMetadata[0] = UserMetadata("key 1", "value 1");
        userMetadata[1] = UserMetadata("key 2", "value 2");
        vm.prank(driver);
        dripsHub.emitUserMetadata(user, userMetadata);
    }

    function testBalanceAt() public {
        DripsReceiver[] memory receivers = dripsReceivers(receiver, 1);
        setDrips(user, 0, 2, receivers);
        uint256 balanceAt = dripsHub.balanceAt(user, erc20, receivers, uint32(block.timestamp + 1));
        assertEq(balanceAt, 1, "Invalid balance");
    }

    function testRegisterDriver() public {
        address driverAddr = address(0x1234);
        uint32 nextDriverId = dripsHub.nextDriverId();
        assertEq(address(0), dripsHub.driverAddress(nextDriverId), "Invalid unused driver address");
        assertEq(nextDriverId, dripsHub.registerDriver(driverAddr), "Invalid assigned driver ID");
        assertEq(driverAddr, dripsHub.driverAddress(nextDriverId), "Invalid driver address");
        assertEq(nextDriverId + 1, dripsHub.nextDriverId(), "Invalid next driver ID");
    }

    function testRegisteringDriverForZeroAddressReverts() public {
        vm.expectRevert("Driver registered for 0 address");
        dripsHub.registerDriver(address(0));
    }

    function testUpdateDriverAddress() public {
        assertEq(driver, dripsHub.driverAddress(driverId), "Invalid driver address before");
        address newDriverAddr = address(0x1234);
        vm.prank(driver);
        dripsHub.updateDriverAddress(driverId, newDriverAddr);
        assertEq(newDriverAddr, dripsHub.driverAddress(driverId), "Invalid driver address after");
    }

    function testUpdateDriverAddressRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.updateDriverAddress(driverId, address(1234));
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
        dripsHub.setDrips(user, erc20, dripsReceivers(), 0, dripsReceivers(), 0, 0);
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
        UserMetadata[] memory userMetadata = new UserMetadata[](1);
        userMetadata[0] = UserMetadata("key", "value");
        vm.expectRevert(ERROR_NOT_DRIVER);
        dripsHub.emitUserMetadata(user, userMetadata);
    }

    function testSetDripsLimitsTotalBalance() public {
        uint128 maxBalance = uint128(dripsHub.MAX_TOTAL_BALANCE());
        assertTotalBalance(0);
        setDrips(user1, 0, maxBalance, dripsReceivers());
        assertTotalBalance(maxBalance);

        transferToDripsHub(1);
        vm.prank(driver);
        vm.expectRevert(ERROR_BALANCE_TOO_HIGH);
        dripsHub.setDrips(user2, erc20, dripsReceivers(), 1, dripsReceivers(), 0, 0);
        withdraw(1);

        setDrips(user1, maxBalance, maxBalance - 1, dripsReceivers());
        assertTotalBalance(maxBalance - 1);
        setDrips(user2, 0, 1, dripsReceivers());
        assertTotalBalance(maxBalance);
    }

    function testSetDripsRequiresTransferredTokens() public {
        setDrips(user, 0, 2, dripsReceivers());

        vm.prank(driver);
        vm.expectRevert(ERROR_ERC_20_BALANCE_TOO_LOW);
        dripsHub.setDrips(user, erc20, dripsReceivers(), 1, dripsReceivers(), 0, 0);

        setDrips(user, 2, 3, dripsReceivers());
    }

    function testGiveLimitsTotalBalance() public {
        uint128 maxBalance = uint128(dripsHub.MAX_TOTAL_BALANCE());
        assertTotalBalance(0);
        give(user, receiver1, maxBalance - 1);
        assertTotalBalance(maxBalance - 1);
        give(user, receiver2, 1);
        assertTotalBalance(maxBalance);

        transferToDripsHub(1);
        vm.prank(driver);
        vm.expectRevert(ERROR_BALANCE_TOO_HIGH);
        dripsHub.give(user, receiver3, erc20, 1);
        withdraw(1);

        collectAll(receiver2, 1);
        assertTotalBalance(maxBalance - 1);
        give(user, receiver3, 1);
        assertTotalBalance(maxBalance);
    }

    function testGiveRequiresTransferredTokens() public {
        give(user, receiver, 2);

        vm.prank(driver);
        vm.expectRevert(ERROR_ERC_20_BALANCE_TOO_LOW);
        dripsHub.give(user, receiver, erc20, 1);

        give(user, receiver, 1);
    }

    function testWithdrawalBelowTotalBalanceReverts() public {
        give(user, receiver, 2);
        transferToDripsHub(1);

        vm.expectRevert("Withdrawal amount too high");
        dripsHub.withdraw(erc20, address(this), 2);

        withdraw(1);
    }

    modifier canBePausedTest() {
        vm.prank(admin);
        dripsHub.pause();
        vm.expectRevert("Contract paused");
        _;
    }

    function testReceiveDripsCanBePaused() public canBePausedTest {
        dripsHub.receiveDrips(user, erc20, 1);
    }

    function testSqueezeDripsCanBePaused() public canBePausedTest {
        dripsHub.squeezeDrips(user, erc20, user, 0, new DripsHistory[](0));
    }

    function testSplitCanBePaused() public canBePausedTest {
        dripsHub.split(user, erc20, splitsReceivers());
    }

    function testCollectCanBePaused() public canBePausedTest {
        dripsHub.collect(user, erc20);
    }

    function testSetDripsCanBePaused() public canBePausedTest {
        dripsHub.setDrips(user, erc20, dripsReceivers(), 1, dripsReceivers(), 0, 0);
    }

    function testGiveCanBePaused() public canBePausedTest {
        dripsHub.give(user, 0, erc20, 1);
    }

    function testSetSplitsCanBePaused() public canBePausedTest {
        dripsHub.setSplits(user, splitsReceivers());
    }

    function testEmitUserMetadataCanBePaused() public canBePausedTest {
        dripsHub.emitUserMetadata(user, new UserMetadata[](0));
    }

    function testRegisterDriverCanBePaused() public canBePausedTest {
        dripsHub.registerDriver(address(0x1234));
    }

    function testUpdateDriverAddressCanBePaused() public canBePausedTest {
        dripsHub.updateDriverAddress(driverId, address(0x1234));
    }
}
