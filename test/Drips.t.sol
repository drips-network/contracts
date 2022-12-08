// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {Drips, DripsConfig, DripsHistory, DripsConfigImpl, DripsReceiver} from "src/Drips.sol";

contract PseudoRandomUtils {
    bytes32 private seed;
    bool private initialized = false;

    // returns a pseudo-random number between 0 and range
    function random(uint256 range) public returns (uint256) {
        require(initialized, "seed not set for test run");
        seed = keccak256(bytes.concat(seed));
        return uint256(seed) % range;
    }

    function initSeed(bytes32 seed_) public {
        require(initialized == false, "only init seed once per test run");
        seed = seed_;
        initialized = true;
    }
}

contract DripsTest is Test, PseudoRandomUtils, Drips {
    bytes internal constant ERROR_NOT_SORTED = "Receivers not sorted";
    bytes internal constant ERROR_INVALID_DRIPS_LIST = "Invalid current drips list";
    bytes internal constant ERROR_TIMESTAMP_EARLY = "Timestamp before last drips update";
    bytes internal constant ERROR_HISTORY_INVALID = "Invalid drips history";
    bytes internal constant ERROR_HISTORY_UNCLEAR = "Drips history entry with hash and receivers";

    uint32 internal cycleSecs;
    // Keys are assetId and userId
    mapping(uint256 => mapping(uint256 => DripsReceiver[])) internal currReceiversStore;
    uint256 internal defaultAssetId = 1;
    uint256 internal otherAssetId = 2;
    // The asset ID used in all helper functions
    uint256 internal assetId = defaultAssetId;
    uint256 internal sender = 1;
    uint256 internal sender1 = 2;
    uint256 internal sender2 = 3;
    uint256 internal receiver = 4;
    uint256 internal receiver1 = 5;
    uint256 internal receiver2 = 6;
    uint256 internal receiver3 = 7;
    uint256 internal receiver4 = 8;

    constructor() Drips(10, bytes32(uint256(1000))) {
        cycleSecs = Drips._cycleSecs;
    }

    function setUp() public {
        skipToCycleEnd();
    }

    function skipToCycleEnd() internal {
        skip(cycleSecs - (block.timestamp % cycleSecs));
    }

    function skipTo(uint256 timestamp) internal {
        vm.warp(timestamp);
    }

    function loadCurrReceivers(uint256 userId)
        internal
        returns (DripsReceiver[] memory currReceivers)
    {
        currReceivers = currReceiversStore[assetId][userId];
        assertDrips(userId, currReceivers);
    }

    function storeCurrReceivers(uint256 userId, DripsReceiver[] memory newReceivers) internal {
        assertDrips(userId, newReceivers);
        delete currReceiversStore[assetId][userId];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currReceiversStore[assetId][userId].push(newReceivers[i]);
        }
    }

    function recv() internal pure returns (DripsReceiver[] memory) {
        return new DripsReceiver[](0);
    }

    function recv(uint256 userId, uint256 amtPerSec)
        internal
        pure
        returns (DripsReceiver[] memory receivers)
    {
        return recv(userId, amtPerSec, 0);
    }

    function recv(uint256 userId, uint256 amtPerSec, uint256 amtPerSecFrac)
        internal
        pure
        returns (DripsReceiver[] memory receivers)
    {
        return recv(userId, amtPerSec, amtPerSecFrac, 0, 0);
    }

    function recv(uint256 userId, uint256 amtPerSec, uint256 start, uint256 duration)
        internal
        pure
        returns (DripsReceiver[] memory receivers)
    {
        return recv(userId, amtPerSec, 0, start, duration);
    }

    function recv(
        uint256 userId,
        uint256 amtPerSec,
        uint256 amtPerSecFrac,
        uint256 start,
        uint256 duration
    ) internal pure returns (DripsReceiver[] memory receivers) {
        return recv(userId, 0, amtPerSec, amtPerSecFrac, start, duration);
    }

    function recv(
        uint256 userId,
        uint256 dripId,
        uint256 amtPerSec,
        uint256 amtPerSecFrac,
        uint256 start,
        uint256 duration
    ) internal pure returns (DripsReceiver[] memory receivers) {
        receivers = new DripsReceiver[](1);
        uint256 amtPerSecFull = amtPerSec * Drips._AMT_PER_SEC_MULTIPLIER + amtPerSecFrac;
        DripsConfig config = DripsConfigImpl.create(
            uint32(dripId), uint160(amtPerSecFull), uint32(start), uint32(duration)
        );
        receivers[0] = DripsReceiver(userId, config);
    }

    function recv(DripsReceiver[] memory recv1, DripsReceiver[] memory recv2)
        internal
        pure
        returns (DripsReceiver[] memory receivers)
    {
        receivers = new DripsReceiver[](recv1.length + recv2.length);
        for (uint256 i = 0; i < recv1.length; i++) {
            receivers[i] = recv1[i];
        }
        for (uint256 i = 0; i < recv2.length; i++) {
            receivers[recv1.length + i] = recv2[i];
        }
    }

    function recv(
        DripsReceiver[] memory recv1,
        DripsReceiver[] memory recv2,
        DripsReceiver[] memory recv3
    ) internal pure returns (DripsReceiver[] memory) {
        return recv(recv(recv1, recv2), recv3);
    }

    function recv(
        DripsReceiver[] memory recv1,
        DripsReceiver[] memory recv2,
        DripsReceiver[] memory recv3,
        DripsReceiver[] memory recv4
    ) internal pure returns (DripsReceiver[] memory) {
        return recv(recv(recv1, recv2, recv3), recv4);
    }

    function genRandomRecv(
        uint256 amountReceiver,
        uint128 maxAmtPerSec,
        uint32 maxStart,
        uint32 maxDuration
    ) internal returns (DripsReceiver[] memory) {
        uint256 inPercent = 100;
        uint256 probMaxEnd = random(inPercent);
        uint256 probStartNow = random(inPercent);
        return genRandomRecv(
            amountReceiver, maxAmtPerSec, maxStart, maxDuration, probMaxEnd, probStartNow
        );
    }

    function genRandomRecv(
        uint256 amountReceiver,
        uint128 maxAmtPerSec,
        uint32 maxStart,
        uint32 maxDuration,
        uint256 probMaxEnd,
        uint256 probStartNow
    ) internal returns (DripsReceiver[] memory) {
        DripsReceiver[] memory receivers = new DripsReceiver[](amountReceiver);
        for (uint256 i = 0; i < amountReceiver; i++) {
            uint256 dripId = random(type(uint32).max + uint256(1));
            uint256 amtPerSec = random(maxAmtPerSec) + 1;
            uint256 start = random(maxStart);
            if (start % 100 <= probStartNow) {
                start = 0;
            }
            uint256 duration = random(maxDuration);
            if (duration % 100 <= probMaxEnd) {
                duration = 0;
            }
            receivers[i] = recv(i, dripId, 0, amtPerSec, start, duration)[0];
        }
        return receivers;
    }

    function hist() internal pure returns (DripsHistory[] memory) {
        return new DripsHistory[](0);
    }

    function hist(DripsReceiver[] memory receivers, uint32 updateTime, uint32 maxEnd)
        internal
        pure
        returns (DripsHistory[] memory history)
    {
        history = new DripsHistory[](1);
        history[0] = DripsHistory(0, receivers, updateTime, maxEnd);
    }

    function histSkip(bytes32 dripsHash, uint32 updateTime, uint32 maxEnd)
        internal
        pure
        returns (DripsHistory[] memory history)
    {
        history = hist(recv(), updateTime, maxEnd);
        history[0].dripsHash = dripsHash;
    }

    function hist(uint256 userId) internal returns (DripsHistory[] memory history) {
        DripsReceiver[] memory receivers = loadCurrReceivers(userId);
        (,, uint32 updateTime,, uint32 maxEnd) = Drips._dripsState(userId, assetId);
        return hist(receivers, updateTime, maxEnd);
    }

    function histSkip(uint256 userId) internal view returns (DripsHistory[] memory history) {
        (bytes32 dripsHash,, uint32 updateTime,, uint32 maxEnd) = Drips._dripsState(userId, assetId);
        return histSkip(dripsHash, updateTime, maxEnd);
    }

    function hist(DripsHistory[] memory history, uint256 userId)
        internal
        returns (DripsHistory[] memory)
    {
        return hist(history, hist(userId));
    }

    function histSkip(DripsHistory[] memory history, uint256 userId)
        internal
        view
        returns (DripsHistory[] memory)
    {
        return hist(history, histSkip(userId));
    }

    function hist(DripsHistory[] memory history1, DripsHistory[] memory history2)
        internal
        pure
        returns (DripsHistory[] memory history)
    {
        history = new DripsHistory[](history1.length + history2.length);
        for (uint256 i = 0; i < history1.length; i++) {
            history[i] = history1[i];
        }
        for (uint256 i = 0; i < history2.length; i++) {
            history[history1.length + i] = history2[i];
        }
    }

    function drainBalance(uint256 userId, uint128 balanceFrom) internal {
        setDrips(userId, balanceFrom, 0, loadCurrReceivers(userId), 0);
    }

    function setDrips(
        uint256 userId,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers,
        uint256 expectedMaxEndFromNow
    ) internal {
        setDrips(userId, balanceFrom, balanceTo, newReceivers, 0, 0, expectedMaxEndFromNow);
    }

    function setDrips(
        uint256 userId,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers,
        uint32 maxEndTip1,
        uint32 maxEndTip2,
        uint256 expectedMaxEndFromNow
    ) internal {
        (, bytes32 oldHistoryHash,,,) = Drips._dripsState(userId, assetId);
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);

        int128 realBalanceDelta = Drips._setDrips(
            userId,
            assetId,
            loadCurrReceivers(userId),
            balanceDelta,
            newReceivers,
            maxEndTip1,
            maxEndTip2
        );

        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        storeCurrReceivers(userId, newReceivers);
        (bytes32 dripsHash, bytes32 historyHash, uint32 updateTime, uint128 balance, uint32 maxEnd)
        = Drips._dripsState(userId, assetId);
        assertEq(
            Drips._hashDripsHistory(oldHistoryHash, dripsHash, updateTime, maxEnd),
            historyHash,
            "Invalid history hash"
        );
        assertEq(updateTime, block.timestamp, "Invalid new last update time");
        assertEq(balanceTo, balance, "Invalid drips balance");
        assertEq(maxEnd, block.timestamp + expectedMaxEndFromNow, "Invalid max end");
    }

    function maxEndMax() internal view returns (uint32) {
        return type(uint32).max - uint32(block.timestamp);
    }

    function assertDrips(uint256 userId, DripsReceiver[] memory currReceivers) internal {
        (bytes32 actual,,,,) = Drips._dripsState(userId, assetId);
        bytes32 expected = Drips._hashDrips(currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function assertBalance(uint256 userId, uint128 expected) internal {
        assertBalanceAt(userId, expected, block.timestamp);
    }

    function assertBalanceAt(uint256 userId, uint128 expected, uint256 timestamp) internal {
        uint128 balance =
            Drips._balanceAt(userId, assetId, loadCurrReceivers(userId), uint32(timestamp));
        assertEq(balance, expected, "Invalid drips balance");
    }

    function assertBalanceAtReverts(
        uint256 userId,
        DripsReceiver[] memory receivers,
        uint256 timestamp,
        bytes memory expectedReason
    ) internal {
        vm.expectRevert(expectedReason);
        this.balanceAtExternal(userId, receivers, timestamp);
    }

    function balanceAtExternal(uint256 userId, DripsReceiver[] memory receivers, uint256 timestamp)
        external
        view
    {
        Drips._balanceAt(userId, assetId, receivers, uint32(timestamp));
    }

    function assetMaxEnd(uint256 userId, uint256 expected) public {
        (,,,, uint32 maxEnd) = Drips._dripsState(userId, assetId);
        assertEq(maxEnd, expected, "Invalid max end");
    }

    function assertSetDripsReverts(
        uint256 userId,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        assertSetDripsReverts(
            userId, loadCurrReceivers(userId), balanceFrom, balanceTo, newReceivers, expectedReason
        );
    }

    function assertSetDripsReverts(
        uint256 userId,
        DripsReceiver[] memory currReceivers,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        vm.expectRevert(expectedReason);
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        this.setDripsExternal(userId, currReceivers, balanceDelta, newReceivers);
    }

    function setDripsExternal(
        uint256 userId,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) external {
        Drips._setDrips(userId, assetId, currReceivers, balanceDelta, newReceivers, 0, 0);
    }

    function receiveDrips(uint256 userId, uint128 expectedAmt) internal {
        uint128 actualAmt = Drips._receiveDrips(userId, assetId, type(uint32).max);
        assertEq(actualAmt, expectedAmt, "Invalid amount received from drips");
    }

    function receiveDrips(
        uint256 userId,
        uint32 maxCycles,
        uint128 expectedReceivedAmt,
        uint32 expectedReceivedCycles,
        uint128 expectedAmtAfter,
        uint32 expectedCyclesAfter
    ) internal {
        uint128 expectedTotalAmt = expectedReceivedAmt + expectedAmtAfter;
        uint32 expectedTotalCycles = expectedReceivedCycles + expectedCyclesAfter;
        assertReceivableDripsCycles(userId, expectedTotalCycles);
        assertReceiveDripsResult(userId, type(uint32).max, expectedTotalAmt, 0);
        assertReceiveDripsResult(userId, maxCycles, expectedReceivedAmt, expectedCyclesAfter);

        uint128 receivedAmt = Drips._receiveDrips(userId, assetId, maxCycles);

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from drips");
        assertReceivableDripsCycles(userId, expectedCyclesAfter);
        assertReceiveDripsResult(userId, type(uint32).max, expectedAmtAfter, 0);
    }

    function receiveDrips(DripsReceiver[] memory receivers, uint32 maxEnd, uint32 updateTime)
        internal
    {
        emit log_named_uint("maxEnd:", maxEnd);
        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory r = receivers[i];
            uint32 duration = r.config.duration();
            uint32 start = r.config.start();
            if (start == 0) {
                start = updateTime;
            }
            if (duration == 0) {
                duration = maxEnd - start;
            }
            // drips was in the past, not added
            if (start + duration < updateTime) {
                duration = 0;
            } else if (start < updateTime) {
                duration -= updateTime - start;
            }

            uint256 expectedAmt = (duration * r.config.amtPerSec()) >> 64;
            uint128 actualAmt = Drips._receiveDrips(r.userId, assetId, type(uint32).max);
            // only log if actualAmt doesn't match expectedAmt
            if (expectedAmt != actualAmt) {
                emit log_named_uint("userId:", r.userId);
                emit log_named_uint("start:", r.config.start());
                emit log_named_uint("duration:", r.config.duration());
                emit log_named_uint("amtPerSec:", r.config.amtPerSec());
            }
            assertEq(actualAmt, expectedAmt);
        }
    }

    function assertReceivableDripsCycles(uint256 userId, uint32 expectedCycles) internal {
        uint32 actualCycles = Drips._receivableDripsCycles(userId, assetId);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable drips cycles");
    }

    function assertReceiveDripsResult(uint256 userId, uint128 expectedAmt) internal {
        (uint128 actualAmt,,,,) = Drips._receiveDripsResult(userId, assetId, type(uint32).max);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
    }

    function assertReceiveDripsResult(
        uint256 userId,
        uint32 maxCycles,
        uint128 expectedAmt,
        uint32 expectedCycles
    ) internal {
        (uint128 actualAmt, uint32 actualCycles,,,) =
            Drips._receiveDripsResult(userId, assetId, maxCycles);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
        assertEq(actualCycles, expectedCycles, "Invalid receivable drips cycles");
    }

    function squeezeDrips(
        uint256 userId,
        uint256 senderId,
        DripsHistory[] memory dripsHistory,
        uint256 expectedAmt
    ) internal {
        squeezeDrips(userId, senderId, 0, dripsHistory, expectedAmt);
    }

    function squeezeDrips(
        uint256 userId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory,
        uint256 expectedAmt
    ) internal {
        (uint128 amtBefore,,,,) =
            Drips._squeezeDripsResult(userId, assetId, senderId, historyHash, dripsHistory);
        assertEq(amtBefore, expectedAmt, "Invalid squeezable amount before squeezing");

        uint128 amt = Drips._squeezeDrips(userId, assetId, senderId, historyHash, dripsHistory);

        assertEq(amt, expectedAmt, "Invalid squeezed amount");
        (uint128 amtAfter,,,,) =
            Drips._squeezeDripsResult(userId, assetId, senderId, historyHash, dripsHistory);
        assertEq(amtAfter, 0, "Squeezable amount after squeezing non-zero");
    }

    function assertSqueezeDripsReverts(
        uint256 userId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory,
        bytes memory expectedReason
    ) internal {
        vm.expectRevert(expectedReason);
        this.squeezeDripsExternal(userId, senderId, historyHash, dripsHistory);
        vm.expectRevert(expectedReason);
        this.squeezeDripsResultExternal(userId, senderId, historyHash, dripsHistory);
    }

    function squeezeDripsExternal(
        uint256 userId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) external {
        Drips._squeezeDrips(userId, assetId, senderId, historyHash, dripsHistory);
    }

    function squeezeDripsResultExternal(
        uint256 userId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) external view {
        Drips._squeezeDripsResult(userId, assetId, senderId, historyHash, dripsHistory);
    }

    function testDripsConfigStoresParameters() public {
        DripsConfig config = DripsConfigImpl.create(1, 2, 3, 4);
        assertEq(config.dripId(), 1, "Invalid dripId");
        assertEq(config.amtPerSec(), 2, "Invalid amtPerSec");
        assertEq(config.start(), 3, "Invalid start");
        assertEq(config.duration(), 4, "Invalid duration");
    }

    function testDripsConfigChecksOrdering() public {
        DripsConfig config = DripsConfigImpl.create(1, 1, 1, 1);
        assertFalse(config.lt(config), "Configs equal");

        DripsConfig higherDripId = DripsConfigImpl.create(2, 1, 1, 1);
        assertTrue(config.lt(higherDripId), "DripId higher");
        assertFalse(higherDripId.lt(config), "DripId lower");

        DripsConfig higherAmtPerSec = DripsConfigImpl.create(1, 2, 1, 1);
        assertTrue(config.lt(higherAmtPerSec), "AmtPerSec higher");
        assertFalse(higherAmtPerSec.lt(config), "AmtPerSec lower");

        DripsConfig higherStart = DripsConfigImpl.create(1, 1, 2, 1);
        assertTrue(config.lt(higherStart), "Start higher");
        assertFalse(higherStart.lt(config), "Start lower");

        DripsConfig higherDuration = DripsConfigImpl.create(1, 1, 1, 2);
        assertTrue(config.lt(higherDuration), "Duration higher");
        assertFalse(higherDuration.lt(config), "Duration lower");
    }

    function testAllowsDrippingToASingleReceiver() public {
        setDrips(sender, 0, 100, recv(receiver, 1), 100);
        skip(15);
        // Sender had 15 seconds paying 1 per second
        drainBalance(sender, 85);
        skipToCycleEnd();
        // Receiver 1 had 15 seconds paying 1 per second
        receiveDrips(receiver, 15);
    }

    function testDripsToTwoReceivers() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 1), recv(receiver2, 1)), 50);
        skip(14);
        // Sender had 14 seconds paying 2 per second
        drainBalance(sender, 72);
        skipToCycleEnd();
        // Receiver 1 had 14 seconds paying 1 per second
        receiveDrips(receiver1, 14);
        // Receiver 2 had 14 seconds paying 1 per second
        receiveDrips(receiver2, 14);
    }

    function testDripsFromTwoSendersToASingleReceiver() public {
        setDrips(sender1, 0, 100, recv(receiver, 1), 100);
        skip(2);
        setDrips(sender2, 0, 100, recv(receiver, 2), 50);
        skip(15);
        // Sender1 had 17 seconds paying 1 per second
        drainBalance(sender1, 83);
        // Sender2 had 15 seconds paying 2 per second
        drainBalance(sender2, 70);
        skipToCycleEnd();
        // Receiver had 2 seconds paying 1 per second and 15 seconds paying 3 per second
        receiveDrips(receiver, 47);
    }

    function testDripsWithStartAndDuration() public {
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp + 5, 10), maxEndMax());
        skip(5);
        assertBalance(sender, 10);
        skip(10);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 10);
    }

    function testDripsWithStartAndDurationWithInsufficientBalance() public {
        setDrips(sender, 0, 1, recv(receiver, 1, block.timestamp + 1, 2), 2);
        skip(1);
        assertBalance(sender, 1);
        skip(1);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
    }

    function testDripsWithOnlyDuration() public {
        setDrips(sender, 0, 10, recv(receiver, 1, 0, 10), maxEndMax());
        skip(10);
        skipToCycleEnd();
        receiveDrips(receiver, 10);
    }

    function testDripsWithOnlyDurationWithInsufficientBalance() public {
        setDrips(sender, 0, 1, recv(receiver, 1, 0, 2), 1);
        assertBalance(sender, 1);
        skip(1);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
    }

    function testDripsWithOnlyStart() public {
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp + 5, 0), 15);
        skip(5);
        assertBalance(sender, 10);
        skip(10);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 10);
    }

    function testDripsWithoutDurationHaveCommonEndTime() public {
        // Enough for 8 seconds of dripping
        setDrips(
            sender,
            0,
            39,
            recv(
                recv(receiver1, 1, block.timestamp + 5, 0),
                recv(receiver2, 2, 0, 0),
                recv(receiver3, 3, block.timestamp + 3, 0)
            ),
            8
        );
        skip(8);
        assertBalance(sender, 5);
        skipToCycleEnd();
        receiveDrips(receiver1, 3);
        receiveDrips(receiver2, 16);
        receiveDrips(receiver3, 15);
        drainBalance(sender, 5);
    }

    function testTwoDripsToSingleReceiver() public {
        setDrips(
            sender,
            0,
            28,
            recv(
                recv(receiver, 1, block.timestamp + 5, 10),
                recv(receiver, 2, block.timestamp + 10, 9)
            ),
            maxEndMax()
        );
        skip(19);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 28);
    }

    function testDripsOfAllSchedulingModes() public {
        setDrips(
            sender,
            0,
            62,
            recv(
                recv(receiver1, 1, 0, 0),
                recv(receiver2, 2, 0, 4),
                recv(receiver3, 3, block.timestamp + 2, 0),
                recv(receiver4, 4, block.timestamp + 3, 5)
            ),
            10
        );
        skip(10);
        skipToCycleEnd();
        receiveDrips(receiver1, 10);
        receiveDrips(receiver2, 8);
        receiveDrips(receiver3, 24);
        receiveDrips(receiver4, 20);
    }

    function testDripsWithStartInThePast() public {
        skip(5);
        setDrips(sender, 0, 3, recv(receiver, 1, block.timestamp - 5, 0), 3);
        skip(3);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 3);
    }

    function testDripsWithStartInThePastAndDurationIntoFuture() public {
        skip(5);
        setDrips(sender, 0, 3, recv(receiver, 1, block.timestamp - 5, 8), maxEndMax());
        skip(3);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 3);
    }

    function testDripsWithStartAndDurationInThePast() public {
        skip(5);
        setDrips(sender, 0, 1, recv(receiver, 1, block.timestamp - 5, 3), 0);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDripsWithStartAfterFundsRunOut() public {
        setDrips(
            sender, 0, 4, recv(recv(receiver1, 1), recv(receiver2, 2, block.timestamp + 5, 0)), 4
        );
        skip(6);
        skipToCycleEnd();
        receiveDrips(receiver1, 4);
        receiveDrips(receiver2, 0);
    }

    function testDripsWithStartInTheFutureCycleCanBeMovedToAnEarlierOne() public {
        setDrips(sender, 0, 1, recv(receiver, 1, block.timestamp + cycleSecs, 0), cycleSecs + 1);
        setDrips(sender, 1, 1, recv(receiver, 1), 1);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDripsWithZeroDurationReceiversNotSortedByStart() public {
        setDrips(
            sender,
            0,
            7,
            recv(
                recv(receiver1, 2, block.timestamp + 2, 0),
                recv(receiver2, 1, block.timestamp + 1, 0)
            ),
            4
        );
        skip(4);
        skipToCycleEnd();
        // Has been receiving 2 per second for 2 seconds
        receiveDrips(receiver1, 4);
        // Has been receiving 1 per second for 3 seconds
        receiveDrips(receiver2, 3);
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        receiveDrips(receiver, 0);
    }

    function testDoesNotCollectCyclesBeforeFirstDrip() public {
        skip(cycleSecs / 2);
        // Dripping starts in 2 cycles
        setDrips(
            sender, 0, 1, recv(receiver, 1, block.timestamp + cycleSecs * 2, 0), cycleSecs * 2 + 1
        );
        // The first cycle hasn't been dripping
        skipToCycleEnd();
        assertReceivableDripsCycles(receiver, 0);
        assertReceiveDripsResult(receiver, 0);
        // The second cycle hasn't been dripping
        skipToCycleEnd();
        assertReceivableDripsCycles(receiver, 0);
        assertReceiveDripsResult(receiver, 0);
        // The third cycle has been dripping
        skipToCycleEnd();
        assertReceivableDripsCycles(receiver, 1);
        receiveDrips(receiver, 1);
    }

    function testAllowsReceivingWhileBeingDrippedTo() public {
        setDrips(sender, 0, cycleSecs + 10, recv(receiver, 1), cycleSecs + 10);
        skipToCycleEnd();
        // Receiver had cycleSecs seconds paying 1 per second
        receiveDrips(receiver, cycleSecs);
        skip(7);
        // Sender had cycleSecs + 7 seconds paying 1 per second
        drainBalance(sender, 3);
        skipToCycleEnd();
        // Receiver had 7 seconds paying 1 per second
        receiveDrips(receiver, 7);
    }

    function testDripsFundsUntilTheyRunOut() public {
        setDrips(sender, 0, 100, recv(receiver, 9), 11);
        skip(10);
        // Sender had 10 seconds paying 9 per second, drips balance is about to run out
        assertBalance(sender, 10);
        skip(1);
        // Sender had 11 seconds paying 9 per second, drips balance has run out
        assertBalance(sender, 1);
        // Nothing more will be dripped
        skipToCycleEnd();
        drainBalance(sender, 1);
        receiveDrips(receiver, 99);
    }

    function testAllowsDripsConfigurationWithOverflowingTotalAmtPerSec() public {
        setDrips(sender, 0, 2, recv(recv(receiver, 1), recv(receiver, type(uint128).max)), 0);
        skipToCycleEnd();
        // Sender hasn't sent anything
        drainBalance(sender, 2);
        // Receiver hasn't received anything
        receiveDrips(receiver, 0);
    }

    function testAllowsDripsConfigurationWithOverflowingAmtPerCycle() public {
        // amtPerSec is valid, but amtPerCycle is over 2 times higher than int128.max.
        // The multiplier is chosen to prevent the amounts from being "clean" binary numbers
        // which could make the overflowing behavior correct by coincidence.
        uint128 amtPerSec = (uint128(type(int128).max) / cycleSecs / 1000) * 2345;
        uint128 amt = amtPerSec * 4;
        setDrips(sender, 0, amt, recv(receiver, amtPerSec), 4);
        skipToCycleEnd();
        receiveDrips(receiver, amt);
    }

    function testAllowsDripsConfigurationWithOverflowingAmtPerCycleAcrossCycleBoundaries() public {
        // amtPerSec is valid, but amtPerCycle is over 2 times higher than int128.max.
        // The multiplier is chosen to prevent the amounts from being "clean" binary numbers
        // which could make the overflowing behavior correct by coincidence.
        uint128 amtPerSec = (uint128(type(int128).max) / cycleSecs / 1000) * 2345;
        // Dripping time in the current and future cycle
        uint128 secs = 2;
        uint128 amt = amtPerSec * secs * 2;
        setDrips(
            sender,
            0,
            amt,
            recv(receiver, amtPerSec, block.timestamp + cycleSecs - secs, 0),
            cycleSecs + 2
        );
        skipToCycleEnd();
        assertReceiveDripsResult(receiver, amt / 2);
        skipToCycleEnd();
        receiveDrips(receiver, amt);
    }

    function testAllowsDripsConfigurationWithOverflowingAmtDeltas() public {
        // The amounts in the comments are expressed as parts of `type(int128).max`.
        // AmtPerCycle is 0.812.
        // The multiplier is chosen to prevent the amounts from being "clean" binary numbers
        // which could make the overflowing behavior correct by coincidence.
        uint128 amtPerSec = (uint128(type(int128).max) / cycleSecs / 1000) * 812;
        uint128 amt = amtPerSec * cycleSecs;
        // Set amtDeltas to +0.812 for the current cycle and -0.812 for the next.
        setDrips(sender1, 0, amt, recv(receiver, amtPerSec), cycleSecs);
        // Alter amtDeltas by +0.0812 for the current cycle and -0.0812 for the next one
        // As an intermediate step when the drips start is applied at the middle of the cycle,
        // but the end not yet, apply +0.406 for the current cycle and -0.406 for the next one.
        // It makes amtDeltas reach +1.218 for the current cycle and -1.218 for the next one.
        setDrips(sender2, 0, amtPerSec, recv(receiver, amtPerSec, cycleSecs / 2, 0), 1);
        skipToCycleEnd();
        receiveDrips(receiver, amt + amtPerSec);
    }

    function testAllowsToppingUpWhileDripping() public {
        DripsReceiver[] memory receivers = recv(receiver, 10);
        setDrips(sender, 0, 100, recv(receiver, 10), 10);
        skip(6);
        // Sender had 6 seconds paying 10 per second
        setDrips(sender, 40, 60, receivers, 6);
        skip(5);
        // Sender had 5 seconds paying 10 per second
        drainBalance(sender, 10);
        skipToCycleEnd();
        // Receiver had 11 seconds paying 10 per second
        receiveDrips(receiver, 110);
    }

    function testAllowsToppingUpAfterFundsRunOut() public {
        DripsReceiver[] memory receivers = recv(receiver, 10);
        setDrips(sender, 0, 100, receivers, 10);
        skip(10);
        // Sender had 10 seconds paying 10 per second
        assertBalance(sender, 0);
        skipToCycleEnd();
        // Receiver had 10 seconds paying 10 per second
        assertReceiveDripsResult(receiver, 100);
        setDrips(sender, 0, 60, receivers, 6);
        skip(5);
        // Sender had 5 seconds paying 10 per second
        drainBalance(sender, 10);
        skipToCycleEnd();
        // Receiver had 15 seconds paying 10 per second
        receiveDrips(receiver, 150);
    }

    function testAllowsDrippingWhichShouldEndAfterMaxTimestamp() public {
        uint128 balance = type(uint32).max + uint128(6);
        setDrips(sender, 0, balance, recv(receiver, 1), maxEndMax());
        skip(10);
        // Sender had 10 seconds paying 1 per second
        drainBalance(sender, balance - 10);
        skipToCycleEnd();
        // Receiver had 10 seconds paying 1 per second
        receiveDrips(receiver, 10);
    }

    function testAllowsDrippingWithDurationEndingAfterMaxTimestamp() public {
        uint32 maxTimestamp = type(uint32).max;
        uint32 currTimestamp = uint32(block.timestamp);
        uint32 maxDuration = maxTimestamp - currTimestamp;
        uint32 duration = maxDuration + 5;
        setDrips(sender, 0, duration, recv(receiver, 1, 0, duration), maxEndMax());
        skipToCycleEnd();
        receiveDrips(receiver, cycleSecs);
        setDrips(sender, duration - cycleSecs, 0, recv(), 0);
    }

    function testAllowsChangingReceiversWhileDripping() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 6), recv(receiver2, 6)), 8);
        skip(3);
        setDrips(sender, 64, 64, recv(recv(receiver1, 4), recv(receiver2, 8)), 5);
        skip(4);
        // Sender had 7 seconds paying 12 per second
        drainBalance(sender, 16);
        skipToCycleEnd();
        // Receiver1 had 3 seconds paying 6 per second and 4 seconds paying 4 per second
        receiveDrips(receiver1, 34);
        // Receiver2 had 3 seconds paying 6 per second and 4 seconds paying 8 per second
        receiveDrips(receiver2, 50);
    }

    function testAllowsRemovingReceiversWhileDripping() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 5), recv(receiver2, 5)), 10);
        skip(3);
        setDrips(sender, 70, 70, recv(receiver2, 10), 7);
        skip(4);
        setDrips(sender, 30, 30, recv(), 0);
        skip(10);
        // Sender had 7 seconds paying 10 per second
        drainBalance(sender, 30);
        skipToCycleEnd();
        // Receiver1 had 3 seconds paying 5 per second
        receiveDrips(receiver1, 15);
        // Receiver2 had 3 seconds paying 5 per second and 4 seconds paying 10 per second
        receiveDrips(receiver2, 55);
    }

    function testDrippingFractions() public {
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / cycleSecs + 1;
        setDrips(sender, 0, 2, recv(receiver, 0, onePerCycle), cycleSecs * 3 - 1);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDrippingFractionsWithFundsEnoughForHalfCycle() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / cycleSecs + 1;
        // Full units are dripped on cycle timestamps 4 and 9
        setDrips(sender, 0, 1, recv(receiver, 0, onePerCycle * 2), 9);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDrippingFractionsWithFundsEnoughForOneCycle() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / cycleSecs + 1;
        // Full units are dripped on cycle timestamps 4 and 9
        setDrips(sender, 0, 2, recv(receiver, 0, onePerCycle * 2), 14);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDrippingFractionsWithFundsEnoughForTwoCycles() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / cycleSecs + 1;
        // Full units are dripped on cycle timestamps 4 and 9
        setDrips(sender, 0, 4, recv(receiver, 0, onePerCycle * 2), 24);
        skipToCycleEnd();
        assertBalance(sender, 2);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testFractionsAreClearedOnCycleBoundary() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 per second
        // Full units are dripped on cycle timestamps 3 and 7
        setDrips(sender, 0, 3, recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1), 17);
        skipToCycleEnd();
        assertBalance(sender, 1);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testFractionsAreAppliedOnCycleSecondsWhenTheyAddUpToWholeUnits() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 per second
        // Full units are dripped on cycle timestamps 3 and 7
        setDrips(sender, 0, 3, recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1), 17);
        assertBalanceAt(sender, 3, block.timestamp + 3);
        assertBalanceAt(sender, 2, block.timestamp + 4);
        assertBalanceAt(sender, 2, block.timestamp + 7);
        assertBalanceAt(sender, 1, block.timestamp + 8);
        assertBalanceAt(sender, 1, block.timestamp + 13);
        assertBalanceAt(sender, 0, block.timestamp + 14);
    }

    function testDripsWithFractionsCanBeSeamlesslyToppedUp() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 per second
        DripsReceiver[] memory receivers = recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1);
        // Full units are dripped on cycle timestamps 3 and 7
        setDrips(sender, 0, 2, receivers, 13);
        // Top up 2
        setDrips(sender, 2, 4, receivers, 23);
        skipToCycleEnd();
        assertBalance(sender, 2);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testFractionsDoNotCumulateOnSender() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 and 0.33 per second
        setDrips(
            sender,
            0,
            5,
            recv(
                recv(receiver1, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1),
                recv(receiver2, 0, (Drips._AMT_PER_SEC_MULTIPLIER / 100 + 1) * 33)
            ),
            13
        );
        // Full units are dripped by 0.25 on cycle timestamps 3 and 7, 0.33 on 3, 6 and 9
        assertBalance(sender, 5);
        assertBalanceAt(sender, 5, block.timestamp + 3);
        assertBalanceAt(sender, 3, block.timestamp + 4);
        assertBalanceAt(sender, 3, block.timestamp + 6);
        assertBalanceAt(sender, 2, block.timestamp + 7);
        assertBalanceAt(sender, 1, block.timestamp + 8);
        assertBalanceAt(sender, 1, block.timestamp + 9);
        assertBalanceAt(sender, 0, block.timestamp + 10);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver1, 2);
        receiveDrips(receiver2, 3);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver1, 0);
        receiveDrips(receiver2, 0);
    }

    function testFractionsDoNotCumulateOnReceiver() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 per second or 2.5 per cycle
        setDrips(sender1, 0, 3, recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1), 17);
        // Rate of 0.66 per second or 6.6 per cycle
        setDrips(
            sender2, 0, 7, recv(receiver, 0, (Drips._AMT_PER_SEC_MULTIPLIER / 100 + 1) * 66), 13
        );
        skipToCycleEnd();
        assertBalance(sender1, 1);
        assertBalance(sender2, 1);
        receiveDrips(receiver, 8);
        skipToCycleEnd();
        assertBalance(sender1, 0);
        assertBalance(sender2, 0);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testLimitsTheTotalReceiversCount() public {
        uint256 countMax = Drips._MAX_DRIPS_RECEIVERS;
        DripsReceiver[] memory receivers = new DripsReceiver[](countMax);
        for (uint160 i = 0; i < countMax; i++) {
            receivers[i] = recv(i, 1, 0, 0)[0];
        }
        setDrips(sender, 0, uint128(countMax), receivers, 1);
        receivers = recv(receivers, recv(countMax, 1, 0, 0));
        assertSetDripsReverts(
            sender, uint128(countMax), uint128(countMax + 1), receivers, "Too many drips receivers"
        );
    }

    function testBenchSetDrips() public {
        initSeed(0);
        uint32 wrongTip1 = uint32(block.timestamp) + 1;
        uint32 wrongTip2 = wrongTip1 + 1;

        uint32 worstEnd = type(uint32).max - 2;
        uint32 worstTip = worstEnd + 1;
        uint32 worstTipPerfect = worstEnd;
        uint32 worstTip1Minute = worstEnd - 1 minutes;
        uint32 worstTip1Hour = worstEnd - 1 hours;

        benchSetDrips("worst 100 no tip         ", 100, worstEnd, 0, 0);
        benchSetDrips("worst 100 perfect tip    ", 100, worstEnd, worstTip, worstTipPerfect);
        benchSetDrips("worst 100 1 minute tip   ", 100, worstEnd, worstTip, worstTip1Minute);
        benchSetDrips("worst 100 1 hour tip     ", 100, worstEnd, worstTip, worstTip1Hour);
        benchSetDrips("worst 100 wrong tip      ", 100, worstEnd, wrongTip1, wrongTip2);
        emit log_string("-----------------------------------------------");

        benchSetDrips("worst 10 no tip          ", 10, worstEnd, 0, 0);
        benchSetDrips("worst 10 perfect tip     ", 10, worstEnd, worstTip, worstTipPerfect);
        benchSetDrips("worst 10 1 minute tip    ", 10, worstEnd, worstTip, worstTip1Minute);
        benchSetDrips("worst 10 1 hour tip      ", 10, worstEnd, worstTip, worstTip1Hour);
        benchSetDrips("worst 10 wrong tip       ", 10, worstEnd, wrongTip1, wrongTip2);
        emit log_string("-----------------------------------------------");

        benchSetDrips("worst 1 no tip           ", 1, worstEnd, 0, 0);
        benchSetDrips("worst 1 perfect tip      ", 1, worstEnd, worstTip, worstTipPerfect);
        benchSetDrips("worst 1 1 minute tip     ", 1, worstEnd, worstTip, worstTip1Minute);
        benchSetDrips("worst 1 1 hour tip       ", 1, worstEnd, worstTip, worstTip1Hour);
        benchSetDrips("worst 1 wrong tip        ", 1, worstEnd, wrongTip1, wrongTip2);
        emit log_string("-----------------------------------------------");

        uint32 monthEnd = uint32(block.timestamp) + 30 days;
        uint32 monthTip = monthEnd + 1;
        uint32 monthTipPerfect = monthEnd;
        uint32 monthTip1Minute = monthEnd - 1 minutes;
        uint32 monthTip1Hour = monthEnd - 1 hours;

        benchSetDrips("1 month 100 no tip       ", 100, monthEnd, 0, 0);
        benchSetDrips("1 month 100 perfect tip  ", 100, monthEnd, monthTip, monthTipPerfect);
        benchSetDrips("1 month 100 1 minute tip ", 100, monthEnd, monthTip, monthTip1Minute);
        benchSetDrips("1 month 100 1 hour tip   ", 100, monthEnd, monthTip, monthTip1Hour);
        benchSetDrips("1 month 100 wrong tip    ", 100, monthEnd, wrongTip1, wrongTip2);
        emit log_string("-----------------------------------------------");

        benchSetDrips("1 month 10 no tip        ", 10, monthEnd, 0, 0);
        benchSetDrips("1 month 10 perfect tip   ", 10, monthEnd, monthTip, monthTipPerfect);
        benchSetDrips("1 month 10 1 minute tip  ", 10, monthEnd, monthTip, monthTip1Minute);
        benchSetDrips("1 month 10 1 hour tip    ", 10, monthEnd, monthTip, monthTip1Hour);
        benchSetDrips("1 month 10 wrong tip     ", 10, monthEnd, wrongTip1, wrongTip2);
        emit log_string("-----------------------------------------------");

        benchSetDrips("1 month 1 no tip         ", 1, monthEnd, 0, 0);
        benchSetDrips("1 month 1 perfect tip    ", 1, monthEnd, monthTip, monthTipPerfect);
        benchSetDrips("1 month 1 1 minute tip   ", 1, monthEnd, monthTip, monthTip1Minute);
        benchSetDrips("1 month 1 1 hour tip     ", 1, monthEnd, monthTip, monthTip1Hour);
        benchSetDrips("1 month 1 wrong tip      ", 1, monthEnd, wrongTip1, wrongTip2);
    }

    function benchSetDrips(
        string memory testName,
        uint256 count,
        uint256 maxEnd,
        uint32 maxEndTip1,
        uint32 maxEndTip2
    ) public {
        uint256 senderId = random(type(uint256).max);
        DripsReceiver[] memory receivers = new DripsReceiver[](count);
        for (uint256 i = 0; i < count; i++) {
            receivers[i] = recv(senderId + 1 + i, 1, 0, 0)[0];
        }
        int128 amt = int128(int256((maxEnd - block.timestamp) * count));
        uint256 gas = gasleft();
        Drips._setDrips(senderId, assetId, recv(), amt, receivers, maxEndTip1, maxEndTip2);
        gas -= gasleft();
        emit log_named_uint(string.concat("Gas used for ", testName), gas);
    }

    function testRejectsZeroAmtPerSecReceivers() public {
        assertSetDripsReverts(sender, 0, 0, recv(receiver, 0), "Drips receiver amtPerSec is zero");
    }

    function testDripsNotSortedByReceiverAreRejected() public {
        assertSetDripsReverts(
            sender, 0, 0, recv(recv(receiver2, 1), recv(receiver1, 1)), ERROR_NOT_SORTED
        );
    }

    function testDripsNotSortedByDripIdAreRejected() public {
        assertSetDripsReverts(
            sender,
            0,
            0,
            recv(recv(receiver, 1, 1, 0, 0, 0), recv(receiver, 0, 1, 0, 0, 0)),
            ERROR_NOT_SORTED
        );
    }

    function testDripsNotSortedByAmtPerSecAreRejected() public {
        assertSetDripsReverts(
            sender, 0, 0, recv(recv(receiver, 2), recv(receiver, 1)), ERROR_NOT_SORTED
        );
    }

    function testDripsNotSortedByStartAreRejected() public {
        assertSetDripsReverts(
            sender, 0, 0, recv(recv(receiver, 1, 2, 0), recv(receiver, 1, 1, 0)), ERROR_NOT_SORTED
        );
    }

    function testDripsNotSortedByDurationAreRejected() public {
        assertSetDripsReverts(
            sender, 0, 0, recv(recv(receiver, 1, 1, 2), recv(receiver, 1, 1, 1)), ERROR_NOT_SORTED
        );
    }

    function testRejectsDuplicateReceivers() public {
        assertSetDripsReverts(
            sender, 0, 0, recv(recv(receiver, 1), recv(receiver, 1)), ERROR_NOT_SORTED
        );
    }

    function testSetDripsRevertsIfInvalidCurrReceivers() public {
        setDrips(sender, 0, 1, recv(receiver, 1), 1);
        assertSetDripsReverts(sender, recv(receiver, 2), 0, 0, recv(), ERROR_INVALID_DRIPS_LIST);
    }

    function testAllowsAnAddressToDripAndReceiveIndependently() public {
        setDrips(sender, 0, 10, recv(sender, 10), 1);
        skip(1);
        // Sender had 1 second paying 10 per second
        assertBalance(sender, 0);
        skipToCycleEnd();
        // Sender had 1 second paying 10 per second
        receiveDrips(sender, 10);
    }

    function testCapsWithdrawalOfMoreThanDripsBalance() public {
        DripsReceiver[] memory receivers = recv(receiver, 1);
        setDrips(sender, 0, 10, receivers, 10);
        skip(4);
        // Sender had 4 second paying 1 per second

        DripsReceiver[] memory newReceivers = recv();
        int128 realBalanceDelta =
            Drips._setDrips(sender, assetId, receivers, type(int128).min, newReceivers, 0, 0);
        storeCurrReceivers(sender, newReceivers);
        assertBalance(sender, 0);
        assertEq(realBalanceDelta, -6, "Invalid real balance delta");
        assertBalance(sender, 0);
        skipToCycleEnd();
        // Receiver had 4 seconds paying 1 per second
        receiveDrips(receiver, 4);
    }

    function testReceiveNotAllDripsCycles() public {
        // Enough for 3 cycles
        uint128 amt = cycleSecs * 3;
        skipToCycleEnd();
        setDrips(sender, 0, amt, recv(receiver, 1), cycleSecs * 3);
        skipToCycleEnd();
        skipToCycleEnd();
        skipToCycleEnd();
        receiveDrips({
            userId: receiver,
            maxCycles: 2,
            expectedReceivedAmt: cycleSecs * 2,
            expectedReceivedCycles: 2,
            expectedAmtAfter: cycleSecs,
            expectedCyclesAfter: 1
        });
        receiveDrips(receiver, cycleSecs);
    }

    function testSenderCanDripToThemselves() public {
        uint128 amt = cycleSecs * 3;
        skipToCycleEnd();
        setDrips(sender, 0, amt, recv(recv(sender, 1), recv(receiver, 2)), cycleSecs);
        skipToCycleEnd();
        receiveDrips(sender, cycleSecs);
        receiveDrips(receiver, cycleSecs * 2);
    }

    function testUpdateDefaultStartDrip() public {
        setDrips(sender, 0, 3 * cycleSecs, recv(receiver, 1), 3 * cycleSecs);
        skipToCycleEnd();
        skipToCycleEnd();
        // remove drips after two cycles, no balance change
        setDrips(sender, 10, 10, recv(), 0);

        skipToCycleEnd();
        // only two cycles should be dripped
        receiveDrips(receiver, 2 * cycleSecs);
    }

    function testDripsOfDifferentAssetsAreIndependent() public {
        // Covers 1.5 cycles of dripping
        assetId = defaultAssetId;
        setDrips(
            sender,
            0,
            9 * cycleSecs,
            recv(recv(receiver1, 4), recv(receiver2, 2)),
            cycleSecs + cycleSecs / 2
        );

        skipToCycleEnd();
        // Covers 2 cycles of dripping
        assetId = otherAssetId;
        setDrips(sender, 0, 6 * cycleSecs, recv(receiver1, 3), cycleSecs * 2);

        skipToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        assetId = defaultAssetId;
        receiveDrips(receiver1, 6 * cycleSecs);
        // receiver1 had 1.5 cycles of 2 per second
        assetId = defaultAssetId;
        receiveDrips(receiver2, 3 * cycleSecs);
        // receiver1 had 1 cycle of 3 per second
        assetId = otherAssetId;
        receiveDrips(receiver1, 3 * cycleSecs);
        // receiver2 received nothing
        assetId = otherAssetId;
        receiveDrips(receiver2, 0);

        skipToCycleEnd();
        // receiver1 received nothing
        assetId = defaultAssetId;
        receiveDrips(receiver1, 0);
        // receiver2 received nothing
        assetId = defaultAssetId;
        receiveDrips(receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        assetId = otherAssetId;
        receiveDrips(receiver1, 3 * cycleSecs);
        // receiver2 received nothing
        assetId = otherAssetId;
        receiveDrips(receiver2, 0);
    }

    function testBalanceAtReturnsCurrentBalance() public {
        setDrips(sender, 0, 10, recv(receiver, 1), 10);
        skip(2);
        assertBalanceAt(sender, 8, block.timestamp);
    }

    function testBalanceAtReturnsFutureBalance() public {
        setDrips(sender, 0, 10, recv(receiver, 1), 10);
        skip(2);
        assertBalanceAt(sender, 6, block.timestamp + 2);
    }

    function testBalanceAtReturnsPastBalanceAfterSetDelta() public {
        setDrips(sender, 0, 10, recv(receiver, 1), 10);
        skip(2);
        assertBalanceAt(sender, 10, block.timestamp - 2);
    }

    function testBalanceAtRevertsForTimestampBeforeSetDelta() public {
        DripsReceiver[] memory receivers = recv(receiver, 1);
        setDrips(sender, 0, 10, receivers, 10);
        skip(2);
        assertBalanceAtReverts(sender, receivers, block.timestamp - 3, ERROR_TIMESTAMP_EARLY);
    }

    function testBalanceAtRevertsForInvalidDripsList() public {
        DripsReceiver[] memory receivers = recv(receiver, 1);
        setDrips(sender, 0, 10, receivers, 10);
        skip(2);
        receivers = recv(receiver, 2);
        assertBalanceAtReverts(sender, receivers, block.timestamp, ERROR_INVALID_DRIPS_LIST);
    }

    function testFuzzDripsReceiver(bytes32 seed) public {
        initSeed(seed);
        uint8 amountReceivers = 10;
        uint128 maxAmtPerSec = 50;
        uint32 maxDuration = 100;
        uint32 maxStart = 100;

        uint128 maxCosts = amountReceivers * maxAmtPerSec * maxDuration;
        emit log_named_uint("topUp", maxCosts);
        uint128 maxAllDripsFinished = maxStart + maxDuration;

        DripsReceiver[] memory receivers =
            genRandomRecv(amountReceivers, maxAmtPerSec, maxStart, maxDuration);
        emit log_named_uint("setDrips.updateTime", block.timestamp);
        Drips._setDrips(sender, assetId, recv(), int128(maxCosts), receivers, 0, 0);

        (,, uint32 updateTime,, uint32 maxEnd) = Drips._dripsState(sender, assetId);

        if (maxEnd > maxAllDripsFinished && maxEnd != type(uint32).max) {
            maxAllDripsFinished = maxEnd;
        }

        skip(maxAllDripsFinished);
        skipToCycleEnd();
        emit log_named_uint("receiveDrips.time", block.timestamp);
        receiveDrips(receivers, maxEnd, updateTime);
    }

    function testReceiverMaxEndExampleA() public {
        skipTo(0);
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 1, start: 50, duration: 0}),
            recv({userId: receiver2, amtPerSec: 1, start: 0, duration: 0})
        );
        setDrips(sender, 0, 100, receivers, 75);
    }

    function testReceiverMaxEndExampleB() public {
        skipTo(70);
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 2, start: 100, duration: 0}),
            recv({userId: receiver2, amtPerSec: 4, start: 120, duration: 0})
        );
        // in the past
        setDrips(sender, 0, 100, receivers, 60);
    }

    function testReceiverMaxEndEdgeCaseA() public {
        skipTo(0);
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 2, start: 0, duration: 0}),
            recv({userId: receiver2, amtPerSec: 1, start: 2, duration: 0})
        );
        setDrips(sender, 0, 7, receivers, 3);
    }

    function testReceiverMaxEndEdgeCaseB() public {
        skipTo(0);
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 2, start: 0, duration: 0}),
            recv({userId: receiver2, amtPerSec: 1, start: 2, duration: 0})
        );
        setDrips(sender, 0, 6, receivers, 2);
    }

    function testReceiverMaxEndNotEnoughToCoverAll() public {
        skipTo(0);
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 1, start: 50, duration: 0}),
            recv({userId: receiver2, amtPerSec: 1, start: 1000, duration: 0})
        );
        setDrips(sender, 0, 100, receivers, 150);
    }

    function testMaxEndTipsDoNotAffectMaxEnd() public {
        skipTo(10);
        setDripsPermuteTips({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndTip1: 15,
            maxEndTip2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndTipsPerfectlyAccurateDoNotAffectMaxEnd() public {
        skipTo(10);
        setDripsPermuteTips({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndTip1: 20,
            maxEndTip2: 21,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndTipsInThePastDoNotAffectMaxEnd() public {
        skipTo(10);
        setDripsPermuteTips({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndTip1: 5,
            maxEndTip2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndTipsAtTheEndOfTimeDoNotAffectMaxEnd() public {
        skipTo(10);
        setDripsPermuteTips({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndTip1: type(uint32).max,
            maxEndTip2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function setDripsPermuteTips(
        uint128 amt,
        DripsReceiver[] memory receivers,
        uint32 maxEndTip1,
        uint32 maxEndTip2,
        uint256 expectedMaxEndFromNow
    ) internal {
        setDripsPermuteTipsCase(amt, receivers, 0, 0, expectedMaxEndFromNow);
        setDripsPermuteTipsCase(amt, receivers, 0, maxEndTip1, expectedMaxEndFromNow);
        setDripsPermuteTipsCase(amt, receivers, 0, maxEndTip2, expectedMaxEndFromNow);
        setDripsPermuteTipsCase(amt, receivers, maxEndTip1, 0, expectedMaxEndFromNow);
        setDripsPermuteTipsCase(amt, receivers, maxEndTip2, 0, expectedMaxEndFromNow);
        setDripsPermuteTipsCase(amt, receivers, maxEndTip1, maxEndTip2, expectedMaxEndFromNow);
        setDripsPermuteTipsCase(amt, receivers, maxEndTip2, maxEndTip1, expectedMaxEndFromNow);
        setDripsPermuteTipsCase(amt, receivers, maxEndTip1, maxEndTip1, expectedMaxEndFromNow);
        setDripsPermuteTipsCase(amt, receivers, maxEndTip2, maxEndTip2, expectedMaxEndFromNow);
    }

    function setDripsPermuteTipsCase(
        uint128 amt,
        DripsReceiver[] memory receivers,
        uint32 maxEndTip1,
        uint32 maxEndTip2,
        uint256 expectedMaxEndFromNow
    ) internal {
        emit log_named_uint("Setting drips with tip 1", maxEndTip1);
        emit log_named_uint("               and tip 2", maxEndTip1);
        uint256 snapshot = vm.snapshot();
        setDrips(sender, 0, amt, receivers, maxEndTip1, maxEndTip2, expectedMaxEndFromNow);
        vm.revertTo(snapshot);
    }

    function testSqueezeDrips() public {
        uint128 amt = cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1), cycleSecs);
        skip(2);
        squeezeDrips(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveDrips(receiver, amt - 2);
    }

    function testSqueezeDripsRevertsWhenInvalidHistory() public {
        uint128 amt = cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1), cycleSecs);
        DripsHistory[] memory history = hist(sender);
        history[0].maxEnd += 1;
        skip(2);
        assertSqueezeDripsReverts(receiver, sender, 0, history, ERROR_HISTORY_INVALID);
    }

    function testSqueezeDripsRevertsWhenHistoryEntryContainsReceiversAndHash() public {
        uint128 amt = cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1), cycleSecs);
        DripsHistory[] memory history = hist(sender);
        history[0].dripsHash = Drips._hashDrips(history[0].receivers);
        skip(2);
        assertSqueezeDripsReverts(receiver, sender, 0, history, ERROR_HISTORY_UNCLEAR);
    }

    function testFundsAreNotSqueezeTwice() public {
        uint128 amt = cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1), cycleSecs);
        DripsHistory[] memory history = hist(sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 1);
        skip(2);
        squeezeDrips(receiver, sender, history, 2);
        skipToCycleEnd();
        receiveDrips(receiver, amt - 3);
    }

    function testFundsFromOldHistoryEntriesAreNotSqueezedTwice() public {
        setDrips(sender, 0, 9, recv(receiver, 1), 9);
        DripsHistory[] memory history = hist(sender);
        skip(1);
        setDrips(sender, 8, 8, recv(receiver, 2), 4);
        history = hist(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 3);
        skip(1);
        squeezeDrips(receiver, sender, history, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 4);
    }

    function testFundsFromFinishedCyclesAreNotSqueezed() public {
        uint128 amt = cycleSecs * 2;
        setDrips(sender, 0, amt, recv(receiver, 1), cycleSecs * 2);
        skipToCycleEnd();
        skip(2);
        squeezeDrips(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveDrips(receiver, amt - 2);
    }

    function testHistoryFromFinishedCyclesIsNotSqueezed() public {
        setDrips(sender, 0, 2, recv(receiver, 1), 2);
        DripsHistory[] memory history = hist(sender);
        skipToCycleEnd();
        setDrips(sender, 0, 6, recv(receiver, 3), 2);
        history = hist(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 3);
        skipToCycleEnd();
        receiveDrips(receiver, 5);
    }

    function testFundsFromAfterDripsRunOutAreNotSqueezed() public {
        uint128 amt = 2;
        setDrips(sender, 0, amt, recv(receiver, 1), 2);
        skip(3);
        squeezeDrips(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testOnFirstSecondOfCycleNoFundsCanBeSqueezed() public {
        uint128 amt = cycleSecs * 2;
        setDrips(sender, 0, amt, recv(receiver, 1), cycleSecs * 2);
        skipToCycleEnd();
        squeezeDrips(receiver, sender, hist(sender), 0);
        skipToCycleEnd();
        receiveDrips(receiver, amt);
    }

    function testDripsWithStartAndDurationCanBeSqueezed() public {
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp + 2, 2), maxEndMax());
        skip(5);
        squeezeDrips(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testEmptyHistoryCanBeSqueezed() public {
        skip(1);
        squeezeDrips(receiver, sender, hist(), 0);
    }

    function testHistoryWithoutTheSqueezingReceiverCanBeSqueezed() public {
        setDrips(sender, 0, 1, recv(receiver1, 1), 1);
        DripsHistory[] memory history = hist(sender);
        skip(1);
        squeezeDrips(receiver2, sender, history, 0);
        skipToCycleEnd();
        receiveDrips(receiver1, 1);
    }

    function testSendersCanBeSqueezedIndependently() public {
        setDrips(sender1, 0, 4, recv(receiver, 2), 2);
        DripsHistory[] memory history1 = hist(sender1);
        setDrips(sender2, 0, 6, recv(receiver, 3), 2);
        DripsHistory[] memory history2 = hist(sender2);
        skip(1);
        squeezeDrips(receiver, sender1, history1, 2);
        skip(1);
        squeezeDrips(receiver, sender2, history2, 6);
        skipToCycleEnd();
        receiveDrips(receiver, 2);
    }

    function testMultipleHistoryEntriesCanBeSqueezed() public {
        setDrips(sender, 0, 5, recv(receiver, 1), 5);
        DripsHistory[] memory history = hist(sender);
        skip(1);
        setDrips(sender, 4, 4, recv(receiver, 2), 2);
        history = hist(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 3);
        skipToCycleEnd();
        receiveDrips(receiver, 2);
    }

    function testMiddleHistoryEntryCanBeSkippedWhenSqueezing() public {
        DripsHistory[] memory history = hist();
        setDrips(sender, 0, 1, recv(receiver, 1), 1);
        history = hist(history, sender);
        skip(1);
        setDrips(sender, 0, 2, recv(receiver, 2), 1);
        history = histSkip(history, sender);
        skip(1);
        setDrips(sender, 0, 4, recv(receiver, 4), 1);
        history = hist(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 5);
        skipToCycleEnd();
        receiveDrips(receiver, 2);
    }

    function testFirstAndLastHistoryEntriesCanBeSkippedWhenSqueezing() public {
        DripsHistory[] memory history = hist();
        setDrips(sender, 0, 1, recv(receiver, 1), 1);
        history = histSkip(history, sender);
        skip(1);
        setDrips(sender, 0, 2, recv(receiver, 2), 1);
        history = hist(history, sender);
        skip(1);
        setDrips(sender, 0, 4, recv(receiver, 4), 1);
        history = histSkip(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 5);
    }

    function testPartOfTheWholeHistoryCanBeSqueezed() public {
        setDrips(sender, 0, 1, recv(receiver, 1), 1);
        (, bytes32 historyHash,,,) = Drips._dripsState(sender, assetId);
        skip(1);
        setDrips(sender, 0, 2, recv(receiver, 2), 1);
        DripsHistory[] memory history = hist(sender);
        skip(1);
        squeezeDrips(receiver, sender, historyHash, history, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
    }

    function testDripsWithCopiesOfTheReceiverCanBeSqueezed() public {
        setDrips(sender, 0, 6, recv(recv(receiver, 1), recv(receiver, 2)), 2);
        skip(1);
        squeezeDrips(receiver, sender, hist(sender), 3);
        skipToCycleEnd();
        receiveDrips(receiver, 3);
    }

    function testDripsWithManyReceiversCanBeSqueezed() public {
        setDrips(sender, 0, 14, recv(recv(receiver1, 1), recv(receiver2, 2), recv(receiver3, 4)), 2);
        skip(1);
        squeezeDrips(receiver2, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveDrips(receiver1, 2);
        receiveDrips(receiver2, 2);
        receiveDrips(receiver3, 8);
    }

    function testPartiallySqueezedOldHistoryEntryCanBeSqueezedFully() public {
        setDrips(sender, 0, 8, recv(receiver, 1), 8);
        DripsHistory[] memory history = hist(sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 1);
        skip(1);
        setDrips(sender, 6, 6, recv(receiver, 2), 3);
        history = hist(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 3);
        skipToCycleEnd();
        receiveDrips(receiver, 4);
    }

    function testUnsqueezedHistoryEntriesFromBeforeLastSqueezeCanBeSqueezed() public {
        setDrips(sender, 0, 9, recv(receiver, 1), 9);
        DripsHistory[] memory history1 = histSkip(sender);
        DripsHistory[] memory history2 = hist(sender);
        skip(1);
        setDrips(sender, 8, 8, recv(receiver, 2), 4);
        history1 = hist(history1, sender);
        history2 = histSkip(history2, sender);
        skip(1);
        squeezeDrips(receiver, sender, history1, 2);
        squeezeDrips(receiver, sender, history2, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 6);
    }

    function testLastSqueezedForPastCycleIsIgnored() public {
        setDrips(sender, 0, 3, recv(receiver, 1), 3);
        DripsHistory[] memory history = hist(sender);
        skip(1);
        // Set the first element of the next squeezed table
        squeezeDrips(receiver, sender, history, 1);
        setDrips(sender, 2, 2, recv(receiver, 2), 1);
        history = hist(history, sender);
        skip(1);
        // Set the second element of the next squeezed table
        squeezeDrips(receiver, sender, history, 2);
        skipToCycleEnd();
        setDrips(sender, 0, 8, recv(receiver, 3), 2);
        history = hist(history, sender);
        skip(1);
        setDrips(sender, 5, 5, recv(receiver, 5), 1);
        history = hist(history, sender);
        skip(1);
        // The next squeezed table entries are ignored
        squeezeDrips(receiver, sender, history, 8);
    }

    function testLastSqueezedForConfigurationSetInPastCycleIsKeptAfterUpdatingDrips() public {
        setDrips(sender, 0, 2, recv(receiver, 2), 1);
        DripsHistory[] memory history = hist(sender);
        skip(1);
        // Set the first element of the next squeezed table
        squeezeDrips(receiver, sender, history, 2);
        setDrips(sender, 0, cycleSecs + 1, recv(receiver, 1), cycleSecs + 1);
        history = hist(history, sender);
        skip(1);
        // Set the second element of the next squeezed table
        squeezeDrips(receiver, sender, history, 1);
        skipToCycleEnd();
        skip(1);
        // Set the first element of the next squeezed table
        squeezeDrips(receiver, sender, history, 1);
        skip(1);
        setDrips(sender, 0, 3, recv(receiver, 3), 1);
        history = hist(history, sender);
        skip(1);
        // There's 1 second of unsqueezed dripping of 1 per second in the current cycle
        squeezeDrips(receiver, sender, history, 4);
    }
}
