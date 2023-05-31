// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {
    SplitsReceiver,
    StreamConfigImpl,
    Drips,
    StreamsHistory,
    StreamReceiver,
    UserMetadata
} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";
import {
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract DripsTest is Test {
    Drips internal drips;
    // The ERC-20 used in all helper functions
    IERC20 internal erc20;
    IERC20 internal defaultErc20;
    IERC20 internal otherErc20;

    // Keys are user ID and ERC-20
    mapping(uint256 => mapping(IERC20 => StreamReceiver[])) internal currStreamsReceivers;
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
    bytes internal constant ERROR_ERC_20_BALANCE_TOO_LOW = "Token balance too low";

    function setUp() public {
        defaultErc20 = new ERC20PresetFixedSupply("default", "default", 2 ** 128, address(this));
        otherErc20 = new ERC20PresetFixedSupply("other", "other", 2 ** 128, address(this));
        erc20 = defaultErc20;
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, admin)));

        driverId = drips.registerDriver(driver);
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
        skip(drips.cycleSecs() - (block.timestamp % drips.cycleSecs()));
    }

    function loadStreams(uint256 forUser)
        internal
        returns (StreamReceiver[] memory currReceivers)
    {
        currReceivers = currStreamsReceivers[forUser][erc20];
        assertStreams(forUser, currReceivers);
    }

    function storeStreams(uint256 forUser, StreamReceiver[] memory newReceivers) internal {
        assertStreams(forUser, newReceivers);
        delete currStreamsReceivers[forUser][erc20];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currStreamsReceivers[forUser][erc20].push(newReceivers[i]);
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

    function streamsReceivers() internal pure returns (StreamReceiver[] memory list) {
        list = new StreamReceiver[](0);
    }

    function streamsReceivers(uint256 streamReceiver, uint128 amtPerSec)
        internal
        view
        returns (StreamReceiver[] memory list)
    {
        list = new StreamReceiver[](1);
        list[0] = StreamReceiver(
            streamReceiver,
            StreamConfigImpl.create(0, uint160(amtPerSec * drips.AMT_PER_SEC_MULTIPLIER()), 0, 0)
        );
    }

    function streamsReceivers(
        uint256 streamReceiver1,
        uint128 amtPerSec1,
        uint256 streamReceiver2,
        uint128 amtPerSec2
    ) internal view returns (StreamReceiver[] memory list) {
        list = new StreamReceiver[](2);
        list[0] = streamsReceivers(streamReceiver1, amtPerSec1)[0];
        list[1] = streamsReceivers(streamReceiver2, amtPerSec2)[0];
    }

    function setStreams(
        uint256 forUser,
        uint128 balanceFrom,
        uint128 balanceTo,
        StreamReceiver[] memory newReceivers
    ) internal {
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        uint256 ownBalanceBefore = ownBalance();
        uint256 dripsBalanceBefore = dripsBalance();
        (uint256 streamsBalanceBefore, uint256 splitsBalanceBefore) = balances();
        StreamReceiver[] memory currReceivers = loadStreams(forUser);

        if (balanceDelta > 0) transferToDrips(uint128(balanceDelta));
        vm.prank(driver);
        int128 realBalanceDelta =
            drips.setStreams(forUser, erc20, currReceivers, balanceDelta, newReceivers, 0, 0);
        if (balanceDelta < 0) withdraw(uint128(-balanceDelta));

        storeStreams(forUser, newReceivers);
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        (,, uint32 updateTime, uint128 actualBalance,) = drips.streamsState(forUser, erc20);
        assertEq(updateTime, block.timestamp, "Invalid new last update time");
        assertEq(balanceTo, actualBalance, "Invalid streams balance");
        assertOwnBalance(uint256(int256(ownBalanceBefore) - balanceDelta));
        assertDripsBalance(uint256(int256(dripsBalanceBefore) + balanceDelta));
        assertBalances(uint256(int256(streamsBalanceBefore) + balanceDelta), splitsBalanceBefore);
    }

    function assertStreams(uint256 forUser, StreamReceiver[] memory currReceivers) internal {
        (bytes32 actual,,,,) = drips.streamsState(forUser, erc20);
        bytes32 expected = drips.hashStreams(currReceivers);
        assertEq(actual, expected, "Invalid streams configuration");
    }

    function give(uint256 fromUser, uint256 toUser, uint128 amt) internal {
        uint256 ownBalanceBefore = ownBalance();
        uint256 dripsBalanceBefore = dripsBalance();
        (uint256 streamsBalanceBefore, uint256 splitsBalanceBefore) = balances();
        uint128 expectedSplittable = splittable(toUser) + amt;

        transferToDrips(amt);
        vm.prank(driver);
        drips.give(fromUser, toUser, erc20, amt);

        assertOwnBalance(ownBalanceBefore - amt);
        assertDripsBalance(dripsBalanceBefore + amt);
        assertBalances(streamsBalanceBefore, splitsBalanceBefore + amt);
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
        drips.give(fromUser, toUser, erc20, amt);
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
        drips.setSplits(forUser, newReceivers);

        storeSplits(forUser, newReceivers);
        assertSplits(forUser, newReceivers);
    }

    function assertSplits(uint256 forUser, SplitsReceiver[] memory expectedReceivers) internal {
        bytes32 actual = drips.splitsHash(forUser);
        bytes32 expected = drips.hashSplits(expectedReceivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function collectAll(uint256 forUser, uint128 expectedAmt) internal {
        collectAll(forUser, expectedAmt, 0);
    }

    function collectAll(uint256 forUser, uint128 expectedCollected, uint128 expectedSplit)
        internal
    {
        uint128 receivable = drips.receiveStreamsResult(forUser, erc20, type(uint32).max);
        uint32 receivableCycles = drips.receivableStreamsCycles(forUser, erc20);
        receiveStreams(forUser, receivable, receivableCycles);

        split(forUser, expectedCollected - collectable(forUser), expectedSplit);

        collect(forUser, expectedCollected);
    }

    function receiveStreams(
        uint256 forUser,
        uint128 expectedReceivedAmt,
        uint32 expectedReceivedCycles
    ) internal {
        receiveStreams(forUser, type(uint32).max, expectedReceivedAmt, expectedReceivedCycles, 0, 0);
    }

    function receiveStreams(
        uint256 forUser,
        uint32 maxCycles,
        uint128 expectedReceivedAmt,
        uint32 expectedReceivedCycles,
        uint128 expectedAmtAfter,
        uint32 expectedCyclesAfter
    ) internal {
        uint128 expectedTotalAmt = expectedReceivedAmt + expectedAmtAfter;
        uint32 expectedTotalCycles = expectedReceivedCycles + expectedCyclesAfter;
        assertReceivableStreamsCycles(forUser, expectedTotalCycles);
        assertReceiveStreamsResult(forUser, type(uint32).max, expectedTotalAmt);
        assertReceiveStreamsResult(forUser, maxCycles, expectedReceivedAmt);

        uint128 receivedAmt = drips.receiveStreams(forUser, erc20, maxCycles);

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from streams");
        assertReceivableStreamsCycles(forUser, expectedCyclesAfter);
        assertReceiveStreamsResult(forUser, type(uint32).max, expectedAmtAfter);
    }

    function assertReceivableStreamsCycles(uint256 forUser, uint32 expectedCycles) internal {
        uint32 actualCycles = drips.receivableStreamsCycles(forUser, erc20);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable streams cycles");
    }

    function assertReceiveStreamsResult(uint256 forUser, uint32 maxCycles, uint128 expectedAmt)
        internal
    {
        uint128 actualAmt = drips.receiveStreamsResult(forUser, erc20, maxCycles);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
    }

    function split(uint256 forUser, uint128 expectedCollectable, uint128 expectedSplit) internal {
        assertSplittable(forUser, expectedCollectable + expectedSplit);
        assertSplitResult(forUser, expectedCollectable + expectedSplit, expectedCollectable);
        uint128 collectableBefore = collectable(forUser);

        (uint128 collectableAmt, uint128 splitAmt) =
            drips.split(forUser, erc20, loadSplits(forUser));

        assertEq(collectableAmt, expectedCollectable, "Invalid collectable amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertSplittable(forUser, 0);
        assertCollectable(forUser, collectableBefore + expectedCollectable);
    }

    function splittable(uint256 forUser) internal view returns (uint128 amt) {
        return drips.splittable(forUser, erc20);
    }

    function assertSplittable(uint256 forUser, uint256 expected) internal {
        uint128 actual = splittable(forUser);
        assertEq(actual, expected, "Invalid splittable");
    }

    function assertSplitResult(uint256 forUser, uint256 amt, uint256 expected) internal {
        (uint128 collectableAmt, uint128 splitAmt) =
            drips.splitResult(forUser, loadSplits(forUser), uint128(amt));
        assertEq(collectableAmt, expected, "Invalid collectable amount");
        assertEq(splitAmt, amt - expected, "Invalid split amount");
    }

    function collect(uint256 forUser, uint128 expectedAmt) internal {
        assertCollectable(forUser, expectedAmt);
        uint256 ownBalanceBefore = ownBalance();
        uint256 dripsBalanceBefore = dripsBalance();
        (uint256 streamsBalanceBefore, uint256 splitsBalanceBefore) = balances();

        vm.prank(driver);
        uint128 actualAmt = drips.collect(forUser, erc20);
        withdraw(actualAmt);

        assertEq(actualAmt, expectedAmt, "Invalid collected amount");
        assertCollectable(forUser, 0);
        assertOwnBalance(ownBalanceBefore + expectedAmt);
        assertDripsBalance(dripsBalanceBefore - expectedAmt);
        assertBalances(streamsBalanceBefore, splitsBalanceBefore - expectedAmt);
    }

    function collectable(uint256 forUser) internal view returns (uint128 amt) {
        return drips.collectable(forUser, erc20);
    }

    function assertCollectable(uint256 forUser, uint256 expected) internal {
        assertEq(collectable(forUser), expected, "Invalid collectable");
    }

    function balances() internal view returns (uint256 streamsBalance, uint256 splitsBalance) {
        return drips.balances(erc20);
    }

    function assertBalances(uint256 expectedStreamsBalance, uint256 expectedSplitsBalance)
        internal
    {
        (uint256 streamsBalance, uint256 splitsBalance) = balances();
        assertEq(streamsBalance, expectedStreamsBalance, "Invalid streams balance");
        assertEq(splitsBalance, expectedSplitsBalance, "Invalid splits balance");
    }

    function transferToDrips(uint256 amt) internal {
        (uint256 streamsBalance, uint256 splitsBalance) = balances();
        assertDripsBalance(streamsBalance + splitsBalance);
        erc20.transfer(address(drips), amt);
    }

    function withdraw(uint256 amt) internal {
        uint256 ownBalanceBefore = ownBalance();
        (uint256 streamsBalance, uint256 splitsBalance) = balances();
        assertDripsBalance(streamsBalance + splitsBalance + amt);

        drips.withdraw(erc20, address(this), amt);

        assertOwnBalance(ownBalanceBefore + amt);
        assertDripsBalance(streamsBalance + splitsBalance);
        assertBalances(streamsBalance, splitsBalance);
    }

    function ownBalance() internal view returns (uint256) {
        return erc20.balanceOf(address(this));
    }

    function assertOwnBalance(uint256 expected) internal {
        assertEq(ownBalance(), expected, "Invalid own balance");
    }

    function dripsBalance() internal view returns (uint256) {
        return erc20.balanceOf(address(drips));
    }

    function assertDripsBalance(uint256 expected) internal {
        assertEq(dripsBalance(), expected, "Invalid Drips balance");
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        receiveStreams(receiver, 0, 0);
        split(receiver, 0, 0);
        collect(receiver, 0);
    }

    function testSetStreamsLimitsWithdrawalToStreamsBalance() public {
        uint128 streamsBalance = 10;
        StreamReceiver[] memory receivers = streamsReceivers();
        uint256 ownBalanceBefore = ownBalance();
        setStreams(user, 0, streamsBalance, receivers);

        vm.prank(driver);
        int128 realBalanceDelta =
            drips.setStreams(user, erc20, receivers, -int128(streamsBalance) - 1, receivers, 0, 0);
        withdraw(uint128(-realBalanceDelta));

        assertEq(realBalanceDelta, -int128(streamsBalance), "Invalid real balance delta");
        (,,, uint128 actualBalance,) = drips.streamsState(user, erc20);
        assertEq(actualBalance, 0, "Invalid streams balance");
        assertOwnBalance(ownBalanceBefore);
        assertDripsBalance(0);
        assertBalances(0, 0);
    }

    function testUncollectedFundsAreSplitUsingCurrentConfig() public {
        uint32 totalWeight = drips.TOTAL_SPLITS_WEIGHT();
        setSplits(user1, splitsReceivers(receiver1, totalWeight));
        setStreams(user2, 0, 5, streamsReceivers(user1, 5));
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

    function testReceiveSomeStreamsCycles() public {
        // Enough for 3 cycles
        uint128 amt = drips.cycleSecs() * 3;
        skipToCycleEnd();
        setStreams(user, 0, amt, streamsReceivers(receiver, 1));
        skipToCycleEnd();
        skipToCycleEnd();
        skipToCycleEnd();
        receiveStreams({
            forUser: receiver,
            maxCycles: 2,
            expectedReceivedAmt: drips.cycleSecs() * 2,
            expectedReceivedCycles: 2,
            expectedAmtAfter: drips.cycleSecs(),
            expectedCyclesAfter: 1
        });
        collectAll(receiver, amt);
    }

    function testReceiveAllStreamsCycles() public {
        // Enough for 3 cycles
        uint128 amt = drips.cycleSecs() * 3;
        skipToCycleEnd();
        setStreams(user, 0, amt, streamsReceivers(receiver, 1));
        skipToCycleEnd();
        skipToCycleEnd();
        skipToCycleEnd();

        receiveStreams(receiver, drips.cycleSecs() * 3, 3);

        collectAll(receiver, amt);
    }

    function testSqueezeStreams() public {
        skipToCycleEnd();
        // Start streaming
        StreamReceiver[] memory receivers = streamsReceivers(receiver, 1);
        setStreams(user, 0, 2, receivers);

        // Create history
        uint32 lastUpdate = uint32(block.timestamp);
        uint32 maxEnd = lastUpdate + 2;
        StreamsHistory[] memory history = new StreamsHistory[](1);
        history[0] = StreamsHistory(0, receivers, lastUpdate, maxEnd);
        bytes32 actualHistoryHash =
            drips.hashStreamsHistory(bytes32(0), drips.hashStreams(receivers), lastUpdate, maxEnd);
        (, bytes32 expectedHistoryHash,,,) = drips.streamsState(user, erc20);
        assertEq(actualHistoryHash, expectedHistoryHash, "Invalid history hash");

        // Check squeezable streams
        skip(1);
        uint128 amt = drips.squeezeStreamsResult(receiver, erc20, user, 0, history);
        assertEq(amt, 1, "Invalid squeezable amt before");

        // Squeeze
        vm.prank(driver);
        amt = drips.squeezeStreams(receiver, erc20, user, 0, history);
        assertEq(amt, 1, "Invalid squeezed amt");

        // Check squeezable streams
        amt = drips.squeezeStreamsResult(receiver, erc20, user, 0, history);
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
        uint32 totalWeight = drips.TOTAL_SPLITS_WEIGHT();
        // Gives
        give(user2, user1, 1);

        // Streams
        setStreams(user2, 0, 2, streamsReceivers(user1, 2));
        skipToCycleEnd();
        receiveStreams(user1, 2, 1);

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
        drips.emitUserMetadata(user, userMetadata);
    }

    function testBalanceAt() public {
        StreamReceiver[] memory receivers = streamsReceivers(receiver, 1);
        setStreams(user, 0, 2, receivers);
        uint256 balanceAt = drips.balanceAt(user, erc20, receivers, uint32(block.timestamp + 1));
        assertEq(balanceAt, 1, "Invalid balance");
    }

    function testRegisterDriver() public {
        address driverAddr = address(0x1234);
        uint32 nextDriverId = drips.nextDriverId();
        assertEq(address(0), drips.driverAddress(nextDriverId), "Invalid unused driver address");
        assertEq(nextDriverId, drips.registerDriver(driverAddr), "Invalid assigned driver ID");
        assertEq(driverAddr, drips.driverAddress(nextDriverId), "Invalid driver address");
        assertEq(nextDriverId + 1, drips.nextDriverId(), "Invalid next driver ID");
    }

    function testRegisteringDriverForZeroAddressReverts() public {
        vm.expectRevert("Driver registered for 0 address");
        drips.registerDriver(address(0));
    }

    function testUpdateDriverAddress() public {
        assertEq(driver, drips.driverAddress(driverId), "Invalid driver address before");
        address newDriverAddr = address(0x1234);
        vm.prank(driver);
        drips.updateDriverAddress(driverId, newDriverAddr);
        assertEq(newDriverAddr, drips.driverAddress(driverId), "Invalid driver address after");
    }

    function testUpdateDriverAddressRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        drips.updateDriverAddress(driverId, address(1234));
    }

    function testCollectRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        drips.collect(user, erc20);
    }

    function testStreamsInDifferentTokensAreIndependent() public {
        uint32 cycleLength = drips.cycleSecs();
        // Covers 1.5 cycles of streaming
        erc20 = defaultErc20;
        setStreams(user, 0, 9 * cycleLength, streamsReceivers(receiver1, 4, receiver2, 2));

        skipToCycleEnd();
        // Covers 2 cycles of streaming
        erc20 = otherErc20;
        setStreams(user, 0, 6 * cycleLength, streamsReceivers(receiver1, 3));

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

    function testSetStreamsRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        drips.setStreams(user, erc20, streamsReceivers(), 0, streamsReceivers(), 0, 0);
    }

    function testGiveRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        drips.give(user, 0, erc20, 1);
    }

    function testSetSplitsRevertsWhenNotCalledByTheDriver() public {
        vm.expectRevert(ERROR_NOT_DRIVER);
        drips.setSplits(user, splitsReceivers());
    }

    function testEmitUserMetadataRevertsWhenNotCalledByTheDriver() public {
        UserMetadata[] memory userMetadata = new UserMetadata[](1);
        userMetadata[0] = UserMetadata("key", "value");
        vm.expectRevert(ERROR_NOT_DRIVER);
        drips.emitUserMetadata(user, userMetadata);
    }

    function testSetStreamsLimitsTotalBalance() public {
        uint128 splitsBalance = uint128(drips.MAX_TOTAL_BALANCE()) / 10;
        give(user, receiver, splitsBalance);
        uint128 maxBalance = uint128(drips.MAX_TOTAL_BALANCE()) - splitsBalance;
        assertBalances(0, splitsBalance);
        setStreams(user1, 0, maxBalance, streamsReceivers());
        assertBalances(maxBalance, splitsBalance);

        transferToDrips(1);
        vm.prank(driver);
        vm.expectRevert(ERROR_BALANCE_TOO_HIGH);
        drips.setStreams(user2, erc20, streamsReceivers(), 1, streamsReceivers(), 0, 0);
        withdraw(1);

        setStreams(user1, maxBalance, maxBalance - 1, streamsReceivers());
        assertBalances(maxBalance - 1, splitsBalance);
        setStreams(user2, 0, 1, streamsReceivers());
        assertBalances(maxBalance, splitsBalance);
    }

    function testSetStreamsRequiresTransferredTokens() public {
        setStreams(user, 0, 2, streamsReceivers());

        vm.prank(driver);
        vm.expectRevert(ERROR_ERC_20_BALANCE_TOO_LOW);
        drips.setStreams(user, erc20, streamsReceivers(), 1, streamsReceivers(), 0, 0);

        setStreams(user, 2, 3, streamsReceivers());
    }

    function testGiveLimitsTotalBalance() public {
        uint128 streamsBalance = uint128(drips.MAX_TOTAL_BALANCE()) / 10;
        setStreams(user, 0, streamsBalance, streamsReceivers());
        uint128 maxBalance = uint128(drips.MAX_TOTAL_BALANCE()) - streamsBalance;
        assertBalances(streamsBalance, 0);
        give(user, receiver1, maxBalance - 1);
        assertBalances(streamsBalance, maxBalance - 1);
        give(user, receiver2, 1);
        assertBalances(streamsBalance, maxBalance);

        transferToDrips(1);
        vm.prank(driver);
        vm.expectRevert(ERROR_BALANCE_TOO_HIGH);
        drips.give(user, receiver3, erc20, 1);
        withdraw(1);

        collectAll(receiver2, 1);
        assertBalances(streamsBalance, maxBalance - 1);
        give(user, receiver3, 1);
        assertBalances(streamsBalance, maxBalance);
    }

    function testGiveRequiresTransferredTokens() public {
        give(user, receiver, 2);

        vm.prank(driver);
        vm.expectRevert(ERROR_ERC_20_BALANCE_TOO_LOW);
        drips.give(user, receiver, erc20, 1);

        give(user, receiver, 1);
    }

    function testWithdrawalBelowTotalBalanceReverts() public {
        setStreams(user, 0, 2, streamsReceivers());
        give(user, receiver, 2);
        transferToDrips(1);

        vm.expectRevert("Withdrawal amount too high");
        drips.withdraw(erc20, address(this), 2);

        withdraw(1);
    }

    modifier canBePausedTest() {
        vm.prank(admin);
        drips.pause();
        vm.expectRevert("Contract paused");
        _;
    }

    function testReceiveStreamsCanBePaused() public canBePausedTest {
        drips.receiveStreams(user, erc20, 1);
    }

    function testSqueezeStreamsCanBePaused() public canBePausedTest {
        drips.squeezeStreams(user, erc20, user, 0, new StreamsHistory[](0));
    }

    function testSplitCanBePaused() public canBePausedTest {
        drips.split(user, erc20, splitsReceivers());
    }

    function testCollectCanBePaused() public canBePausedTest {
        drips.collect(user, erc20);
    }

    function testSetStreamsCanBePaused() public canBePausedTest {
        drips.setStreams(user, erc20, streamsReceivers(), 1, streamsReceivers(), 0, 0);
    }

    function testGiveCanBePaused() public canBePausedTest {
        drips.give(user, 0, erc20, 1);
    }

    function testSetSplitsCanBePaused() public canBePausedTest {
        drips.setSplits(user, splitsReceivers());
    }

    function testEmitUserMetadataCanBePaused() public canBePausedTest {
        drips.emitUserMetadata(user, new UserMetadata[](0));
    }

    function testRegisterDriverCanBePaused() public canBePausedTest {
        drips.registerDriver(address(0x1234));
    }

    function testUpdateDriverAddressCanBePaused() public canBePausedTest {
        drips.updateDriverAddress(driverId, address(0x1234));
    }
}
