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

contract AssertMinAmtPerSec is Test, Drips {
    constructor(uint32 cycleSecs, uint160 expectedMinAmtPerSec) Drips(cycleSecs, 0) {
        string memory assertMessage =
            string.concat("Invalid minAmtPerSec for cycleSecs ", vm.toString(cycleSecs));
        assertEq(_minAmtPerSec, expectedMinAmtPerSec, assertMessage);
    }
}

contract DripsTest is Test, PseudoRandomUtils, Drips {
    bytes internal constant ERROR_NOT_SORTED = "Receivers not sorted";
    bytes internal constant ERROR_INVALID_DRIPS_LIST = "Invalid current drips list";
    bytes internal constant ERROR_TIMESTAMP_EARLY = "Timestamp before last drips update";
    bytes internal constant ERROR_HISTORY_INVALID = "Invalid drips history";
    bytes internal constant ERROR_HISTORY_UNCLEAR = "Drips history entry with hash and receivers";

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
        return;
    }

    function setUp() public {
        skipToCycleEnd();
    }

    function skipToCycleEnd() internal {
        skip(_cycleSecs - (block.timestamp % _cycleSecs));
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
        uint160 maxAmtPerSec,
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
        uint160 maxAmtPerSec,
        uint32 maxStart,
        uint32 maxDuration,
        uint256 probMaxEnd,
        uint256 probStartNow
    ) internal returns (DripsReceiver[] memory) {
        DripsReceiver[] memory receivers = new DripsReceiver[](amountReceiver);
        for (uint256 i = 0; i < amountReceiver; i++) {
            uint256 dripId = random(type(uint32).max + uint256(1));
            uint256 amtPerSec = _minAmtPerSec + random(maxAmtPerSec - _minAmtPerSec);
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
        uint32 maxEndHint1,
        uint32 maxEndHint2,
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
            maxEndHint1,
            maxEndHint2
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
            if (duration == 0 && maxEnd > start) {
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

    function testDripsWithBalanceLowerThan1SecondOfDripping() public {
        setDrips(sender, 0, 1, recv(receiver, 2), 0);
        skipToCycleEnd();
        drainBalance(sender, 1);
        receiveDrips(receiver, 0);
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
        setDrips(sender, 0, 1, recv(receiver, 1, block.timestamp + _cycleSecs, 0), _cycleSecs + 1);
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
        skip(_cycleSecs / 2);
        // Dripping starts in 2 cycles
        setDrips(
            sender, 0, 1, recv(receiver, 1, block.timestamp + _cycleSecs * 2, 0), _cycleSecs * 2 + 1
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
        setDrips(sender, 0, _cycleSecs + 10, recv(receiver, 1), _cycleSecs + 10);
        skipToCycleEnd();
        // Receiver had cycleSecs seconds paying 1 per second
        receiveDrips(receiver, _cycleSecs);
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
        uint128 amtPerSec = (uint128(type(int128).max) / _cycleSecs / 1000) * 2345;
        uint128 amt = amtPerSec * 4;
        setDrips(sender, 0, amt, recv(receiver, amtPerSec), 4);
        skipToCycleEnd();
        receiveDrips(receiver, amt);
    }

    function testAllowsDripsConfigurationWithOverflowingAmtPerCycleAcrossCycleBoundaries() public {
        // amtPerSec is valid, but amtPerCycle is over 2 times higher than int128.max.
        // The multiplier is chosen to prevent the amounts from being "clean" binary numbers
        // which could make the overflowing behavior correct by coincidence.
        uint128 amtPerSec = (uint128(type(int128).max) / _cycleSecs / 1000) * 2345;
        // Dripping time in the current and future cycle
        uint128 secs = 2;
        uint128 amt = amtPerSec * secs * 2;
        setDrips(
            sender,
            0,
            amt,
            recv(receiver, amtPerSec, block.timestamp + _cycleSecs - secs, 0),
            _cycleSecs + 2
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
        uint128 amtPerSec = (uint128(type(int128).max) / _cycleSecs / 1000) * 812;
        uint128 amt = amtPerSec * _cycleSecs;
        // Set amtDeltas to +0.812 for the current cycle and -0.812 for the next.
        setDrips(sender1, 0, amt, recv(receiver, amtPerSec), _cycleSecs);
        // Alter amtDeltas by +0.0812 for the current cycle and -0.0812 for the next one
        // As an intermediate step when the drips start is applied at the middle of the cycle,
        // but the end not yet, apply +0.406 for the current cycle and -0.406 for the next one.
        // It makes amtDeltas reach +1.218 for the current cycle and -1.218 for the next one.
        setDrips(sender2, 0, amtPerSec, recv(receiver, amtPerSec, _cycleSecs / 2, 0), 1);
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
        receiveDrips(receiver, _cycleSecs);
        setDrips(sender, duration - _cycleSecs, 0, recv(), 0);
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
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / _cycleSecs + 1;
        setDrips(sender, 0, 2, recv(receiver, 0, onePerCycle), _cycleSecs * 3 - 1);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDrippingFractionsWithFundsEnoughForHalfCycle() public {
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / _cycleSecs + 1;
        // Full units are dripped on cycle timestamps 4 and 9
        setDrips(sender, 0, 1, recv(receiver, 0, onePerCycle * 2), 9);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDrippingFractionsWithFundsEnoughForOneCycle() public {
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / _cycleSecs + 1;
        // Full units are dripped on cycle timestamps 4 and 9
        setDrips(sender, 0, 2, recv(receiver, 0, onePerCycle * 2), 14);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDrippingFractionsWithFundsEnoughForTwoCycles() public {
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / _cycleSecs + 1;
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
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
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
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
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

    function testFractionsAreAppliedRegardlessOfStartTime() public {
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
        skip(3);
        // Rate of 0.4 per second
        // Full units are dripped on cycle timestamps 3, 5 and 8
        setDrips(sender, 0, 1, recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 10 * 4 + 1), 4);
        assertBalanceAt(sender, 1, block.timestamp + 1);
        assertBalanceAt(sender, 0, block.timestamp + 2);
    }

    function testDripsWithFractionsCanBeSeamlesslyToppedUp() public {
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
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
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
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
        assertEq(_cycleSecs, 10, "Unexpected cycle length");
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
        uint32 wrongHint1 = uint32(block.timestamp) + 1;
        uint32 wrongHint2 = wrongHint1 + 1;

        uint32 worstEnd = type(uint32).max - 2;
        uint32 worstHint = worstEnd + 1;
        uint32 worstHintPerfect = worstEnd;
        uint32 worstHint1Minute = worstEnd - 1 minutes;
        uint32 worstHint1Hour = worstEnd - 1 hours;

        benchSetDrips("worst 100 no hint        ", 100, worstEnd, 0, 0);
        benchSetDrips("worst 100 perfect hint   ", 100, worstEnd, worstHint, worstHintPerfect);
        benchSetDrips("worst 100 1 minute hint  ", 100, worstEnd, worstHint, worstHint1Minute);
        benchSetDrips("worst 100 1 hour hint    ", 100, worstEnd, worstHint, worstHint1Hour);
        benchSetDrips("worst 100 wrong hint     ", 100, worstEnd, wrongHint1, wrongHint2);
        emit log_string("-----------------------------------------------");

        benchSetDrips("worst 10 no hint         ", 10, worstEnd, 0, 0);
        benchSetDrips("worst 10 perfect hint    ", 10, worstEnd, worstHint, worstHintPerfect);
        benchSetDrips("worst 10 1 minute hint   ", 10, worstEnd, worstHint, worstHint1Minute);
        benchSetDrips("worst 10 1 hour hint     ", 10, worstEnd, worstHint, worstHint1Hour);
        benchSetDrips("worst 10 wrong hint      ", 10, worstEnd, wrongHint1, wrongHint2);
        emit log_string("-----------------------------------------------");

        benchSetDrips("worst 1 no hint          ", 1, worstEnd, 0, 0);
        benchSetDrips("worst 1 perfect hint     ", 1, worstEnd, worstHint, worstHintPerfect);
        benchSetDrips("worst 1 1 minute hint    ", 1, worstEnd, worstHint, worstHint1Minute);
        benchSetDrips("worst 1 1 hour hint      ", 1, worstEnd, worstHint, worstHint1Hour);
        benchSetDrips("worst 1 wrong hint       ", 1, worstEnd, wrongHint1, wrongHint2);
        emit log_string("-----------------------------------------------");

        uint32 monthEnd = uint32(block.timestamp) + 30 days;
        uint32 monthHint = monthEnd + 1;
        uint32 monthHintPerfect = monthEnd;
        uint32 monthHint1Minute = monthEnd - 1 minutes;
        uint32 monthHint1Hour = monthEnd - 1 hours;

        benchSetDrips("1 month 100 no hint      ", 100, monthEnd, 0, 0);
        benchSetDrips("1 month 100 perfect hint ", 100, monthEnd, monthHint, monthHintPerfect);
        benchSetDrips("1 month 100 1 minute hint", 100, monthEnd, monthHint, monthHint1Minute);
        benchSetDrips("1 month 100 1 hour hint  ", 100, monthEnd, monthHint, monthHint1Hour);
        benchSetDrips("1 month 100 wrong hint   ", 100, monthEnd, wrongHint1, wrongHint2);
        emit log_string("-----------------------------------------------");

        benchSetDrips("1 month 10 no hint       ", 10, monthEnd, 0, 0);
        benchSetDrips("1 month 10 perfect hint  ", 10, monthEnd, monthHint, monthHintPerfect);
        benchSetDrips("1 month 10 1 minute hint ", 10, monthEnd, monthHint, monthHint1Minute);
        benchSetDrips("1 month 10 1 hour hint   ", 10, monthEnd, monthHint, monthHint1Hour);
        benchSetDrips("1 month 10 wrong hint    ", 10, monthEnd, wrongHint1, wrongHint2);
        emit log_string("-----------------------------------------------");

        benchSetDrips("1 month 1 no hint        ", 1, monthEnd, 0, 0);
        benchSetDrips("1 month 1 perfect hint   ", 1, monthEnd, monthHint, monthHintPerfect);
        benchSetDrips("1 month 1 1 minute hint  ", 1, monthEnd, monthHint, monthHint1Minute);
        benchSetDrips("1 month 1 1 hour hint    ", 1, monthEnd, monthHint, monthHint1Hour);
        benchSetDrips("1 month 1 wrong hint     ", 1, monthEnd, wrongHint1, wrongHint2);
    }

    function benchSetDrips(
        string memory testName,
        uint256 count,
        uint256 maxEnd,
        uint32 maxEndHint1,
        uint32 maxEndHint2
    ) public {
        uint256 senderId = random(type(uint256).max);
        DripsReceiver[] memory receivers = new DripsReceiver[](count);
        for (uint256 i = 0; i < count; i++) {
            receivers[i] = recv(senderId + 1 + i, 1, 0, 0)[0];
        }
        int128 amt = int128(int256((maxEnd - block.timestamp) * count));
        uint256 gas = gasleft();
        Drips._setDrips(senderId, assetId, recv(), amt, receivers, maxEndHint1, maxEndHint2);
        gas -= gasleft();
        emit log_named_uint(string.concat("Gas used for ", testName), gas);
    }

    function testMinAmtPerSec() public {
        new AssertMinAmtPerSec(2, 500_000_000);
        new AssertMinAmtPerSec(3, 333_333_334);
        new AssertMinAmtPerSec(10, 100_000_000);
        new AssertMinAmtPerSec(11, 90_909_091);
        new AssertMinAmtPerSec(999_999_999, 2);
        new AssertMinAmtPerSec(1_000_000_000, 1);
        new AssertMinAmtPerSec(1_000_000_001, 1);
        new AssertMinAmtPerSec(2_000_000_000, 1);
    }

    function testRejectsTooLowAmtPerSecReceivers() public {
        assertSetDripsReverts(
            sender, 0, 0, recv(receiver, 0, _minAmtPerSec - 1), "Drips receiver amtPerSec too low"
        );
    }

    function testAcceptMinAmtPerSecReceivers() public {
        setDrips(sender, 0, 2, recv(receiver, 0, _minAmtPerSec), 3 * _cycleSecs - 1);
        skipToCycleEnd();
        drainBalance(sender, 1);
        receiveDrips(receiver, 1);
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
        uint128 amt = _cycleSecs * 3;
        skipToCycleEnd();
        setDrips(sender, 0, amt, recv(receiver, 1), _cycleSecs * 3);
        skipToCycleEnd();
        skipToCycleEnd();
        skipToCycleEnd();
        receiveDrips({
            userId: receiver,
            maxCycles: 2,
            expectedReceivedAmt: _cycleSecs * 2,
            expectedReceivedCycles: 2,
            expectedAmtAfter: _cycleSecs,
            expectedCyclesAfter: 1
        });
        receiveDrips(receiver, _cycleSecs);
    }

    function testSenderCanDripToThemselves() public {
        uint128 amt = _cycleSecs * 3;
        skipToCycleEnd();
        setDrips(sender, 0, amt, recv(recv(sender, 1), recv(receiver, 2)), _cycleSecs);
        skipToCycleEnd();
        receiveDrips(sender, _cycleSecs);
        receiveDrips(receiver, _cycleSecs * 2);
    }

    function testUpdateDefaultStartDrip() public {
        setDrips(sender, 0, 3 * _cycleSecs, recv(receiver, 1), 3 * _cycleSecs);
        skipToCycleEnd();
        skipToCycleEnd();
        // remove drips after two cycles, no balance change
        setDrips(sender, 10, 10, recv(), 0);

        skipToCycleEnd();
        // only two cycles should be dripped
        receiveDrips(receiver, 2 * _cycleSecs);
    }

    function testDripsOfDifferentAssetsAreIndependent() public {
        // Covers 1.5 cycles of dripping
        assetId = defaultAssetId;
        setDrips(
            sender,
            0,
            9 * _cycleSecs,
            recv(recv(receiver1, 4), recv(receiver2, 2)),
            _cycleSecs + _cycleSecs / 2
        );

        skipToCycleEnd();
        // Covers 2 cycles of dripping
        assetId = otherAssetId;
        setDrips(sender, 0, 6 * _cycleSecs, recv(receiver1, 3), _cycleSecs * 2);

        skipToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        assetId = defaultAssetId;
        receiveDrips(receiver1, 6 * _cycleSecs);
        // receiver1 had 1.5 cycles of 2 per second
        assetId = defaultAssetId;
        receiveDrips(receiver2, 3 * _cycleSecs);
        // receiver1 had 1 cycle of 3 per second
        assetId = otherAssetId;
        receiveDrips(receiver1, 3 * _cycleSecs);
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
        receiveDrips(receiver1, 3 * _cycleSecs);
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
        uint160 maxAmtPerSec = _minAmtPerSec + 50;
        uint32 maxDuration = 100;
        uint32 maxStart = 100;

        uint128 maxCosts =
            amountReceivers * uint128(maxAmtPerSec / _AMT_PER_SEC_MULTIPLIER) * maxDuration;
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

    function sanitizeReceivers(
        DripsReceiver[_MAX_DRIPS_RECEIVERS] memory receiversRaw,
        uint256 receiversLengthRaw
    ) internal view returns (DripsReceiver[] memory receivers) {
        receivers = new DripsReceiver[](bound(receiversLengthRaw, 0, receiversRaw.length));
        for (uint256 i = 0; i < receivers.length; i++) {
            receivers[i] = receiversRaw[i];
        }
        for (uint32 i = 0; i < receivers.length; i++) {
            for (uint256 j = i + 1; j < receivers.length; j++) {
                if (receivers[j].userId < receivers[i].userId) {
                    (receivers[j], receivers[i]) = (receivers[i], receivers[j]);
                }
            }
            DripsConfig cfg = receivers[i].config;
            uint160 amtPerSec = cfg.amtPerSec();
            if (amtPerSec < _minAmtPerSec) amtPerSec = _minAmtPerSec;
            receivers[i].config = DripsConfigImpl.create(i, amtPerSec, cfg.start(), cfg.duration());
        }
    }

    struct Sender {
        uint256 userId;
        uint128 balance;
        DripsReceiver[] receivers;
    }

    function sanitizeSenders(
        uint256 receiverId,
        uint128 balance,
        DripsReceiver[100] memory sendersRaw,
        uint256 sendersLenRaw
    ) internal view returns (Sender[] memory senders) {
        uint256 sendersLen = bound(sendersLenRaw, 1, sendersRaw.length);
        senders = new Sender[](sendersLen);
        uint256 totalBalanceWeight = 0;
        for (uint32 i = 0; i < sendersLen; i++) {
            DripsConfig cfg = sendersRaw[i].config;
            senders[i].userId = sendersRaw[i].userId;
            senders[i].balance = cfg.dripId();
            totalBalanceWeight += cfg.dripId();
            senders[i].receivers = new DripsReceiver[](1);
            senders[i].receivers[0].userId = receiverId;
            uint160 amtPerSec = cfg.amtPerSec();
            if (amtPerSec < _minAmtPerSec) amtPerSec = _minAmtPerSec;
            senders[i].receivers[0].config =
                DripsConfigImpl.create(i, amtPerSec, cfg.start(), cfg.duration());
        }
        uint256 uniqueSenders = 0;
        uint256 usedBalance = 0;
        uint256 usedBalanceWeight = 0;
        if (totalBalanceWeight == 0) {
            totalBalanceWeight = 1;
            usedBalanceWeight = 1;
        }
        for (uint256 i = 0; i < sendersLen; i++) {
            usedBalanceWeight += senders[i].balance;
            uint256 newUsedBalance = usedBalanceWeight * balance / totalBalanceWeight;
            senders[i].balance = uint128(newUsedBalance - usedBalance);
            usedBalance = newUsedBalance;
            senders[uniqueSenders++] = senders[i];
            for (uint256 j = 0; j + 1 < uniqueSenders; j++) {
                if (senders[i].userId == senders[j].userId) {
                    senders[j].balance += senders[i].balance;
                    senders[j].receivers = recv(senders[j].receivers, senders[i].receivers);
                    uniqueSenders--;
                    break;
                }
            }
        }
        Sender[] memory sendersLong = senders;
        senders = new Sender[](uniqueSenders);
        for (uint256 i = 0; i < uniqueSenders; i++) {
            senders[i] = sendersLong[i];
        }
    }

    function sanitizeDripTime(uint256 dripTimeRaw, uint256 maxCycles)
        internal
        view
        returns (uint256 dripTime)
    {
        return bound(dripTimeRaw, 0, _cycleSecs * maxCycles);
    }

    function sanitizeDripBalance(uint256 balanceRaw) internal view returns (uint128 balance) {
        return uint128(bound(balanceRaw, 0, _MAX_TOTAL_DRIPS_BALANCE));
    }

    function testFundsDrippedToReceiversAddUp(
        uint256 senderId,
        uint256 asset,
        uint256 balanceRaw,
        DripsReceiver[_MAX_DRIPS_RECEIVERS] memory receiversRaw,
        uint256 receiversLengthRaw,
        uint256 dripTimeRaw
    ) public {
        uint128 balanceBefore = sanitizeDripBalance(balanceRaw);
        DripsReceiver[] memory receivers = sanitizeReceivers(receiversRaw, receiversLengthRaw);
        Drips._setDrips(senderId, asset, recv(), int128(balanceBefore), receivers, 0, 0);

        skip(sanitizeDripTime(dripTimeRaw, 100));
        int128 realBalanceDelta =
            Drips._setDrips(senderId, asset, receivers, type(int128).min, receivers, 0, 0);

        skipToCycleEnd();
        uint256 balanceAfter = uint128(-realBalanceDelta);
        for (uint256 i = 0; i < receivers.length; i++) {
            balanceAfter += Drips._receiveDrips(receivers[i].userId, asset, type(uint32).max);
        }
        assertEq(balanceAfter, balanceBefore, "Dripped funds don't add up");
    }

    function testFundsDrippedToReceiversAddUpAfterDripsUpdate(
        uint256 senderId,
        uint256 asset,
        uint256 balanceRaw,
        DripsReceiver[_MAX_DRIPS_RECEIVERS] memory receiversRaw1,
        uint256 receiversLengthRaw1,
        uint256 dripTimeRaw1,
        DripsReceiver[_MAX_DRIPS_RECEIVERS] memory receiversRaw2,
        uint256 receiversLengthRaw2,
        uint256 dripTimeRaw2
    ) public {
        uint128 balanceBefore = sanitizeDripBalance(balanceRaw);
        DripsReceiver[] memory receivers1 = sanitizeReceivers(receiversRaw1, receiversLengthRaw1);
        Drips._setDrips(senderId, asset, recv(), int128(balanceBefore), receivers1, 0, 0);

        skip(sanitizeDripTime(dripTimeRaw1, 50));
        DripsReceiver[] memory receivers2 = sanitizeReceivers(receiversRaw2, receiversLengthRaw2);
        int128 realBalanceDelta = Drips._setDrips(senderId, asset, receivers1, 0, receivers2, 0, 0);
        assertEq(realBalanceDelta, 0, "Zero balance delta changed balance");

        skip(sanitizeDripTime(dripTimeRaw2, 50));
        realBalanceDelta =
            Drips._setDrips(senderId, asset, receivers2, type(int128).min, receivers2, 0, 0);

        skipToCycleEnd();
        uint256 balanceAfter = uint128(-realBalanceDelta);
        for (uint256 i = 0; i < receivers1.length; i++) {
            balanceAfter += Drips._receiveDrips(receivers1[i].userId, asset, type(uint32).max);
        }
        for (uint256 i = 0; i < receivers2.length; i++) {
            balanceAfter += Drips._receiveDrips(receivers2[i].userId, asset, type(uint32).max);
        }
        assertEq(balanceAfter, balanceBefore, "Dripped funds don't add up");
    }

    function testFundsDrippedFromSendersAddUp(
        uint256 receiverId,
        uint256 asset,
        uint256 balanceRaw,
        DripsReceiver[100] memory sendersRaw,
        uint256 sendersLenRaw,
        uint256 dripTimeRaw
    ) public {
        uint128 balanceBefore = sanitizeDripBalance(balanceRaw);
        Sender[] memory senders =
            sanitizeSenders(receiverId, balanceBefore, sendersRaw, sendersLenRaw);
        for (uint256 i = 0; i < senders.length; i++) {
            Sender memory snd = senders[i];
            Drips._setDrips(snd.userId, asset, recv(), int128(snd.balance), snd.receivers, 0, 0);
        }

        skip(sanitizeDripTime(dripTimeRaw, 1000));
        uint128 balanceAfter = 0;
        for (uint256 i = 0; i < senders.length; i++) {
            Sender memory snd = senders[i];
            int128 realBalanceDelta = Drips._setDrips(
                snd.userId, asset, snd.receivers, type(int128).min, snd.receivers, 0, 0
            );
            balanceAfter += uint128(-realBalanceDelta);
        }

        skipToCycleEnd();
        balanceAfter += Drips._receiveDrips(receiverId, asset, type(uint32).max);
        assertEq(balanceAfter, balanceBefore, "Dripped funds don't add up");
    }

    function testMaxEndHintsDoNotAffectMaxEnd() public {
        skipTo(10);
        setDripsPermuteHints({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndHint1: 15,
            maxEndHint2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndHintsPerfectlyAccurateDoNotAffectMaxEnd() public {
        skipTo(10);
        setDripsPermuteHints({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndHint1: 20,
            maxEndHint2: 21,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndHintsInThePastDoNotAffectMaxEnd() public {
        skipTo(10);
        setDripsPermuteHints({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndHint1: 5,
            maxEndHint2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndHintsAtTheEndOfTimeDoNotAffectMaxEnd() public {
        skipTo(10);
        setDripsPermuteHints({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndHint1: type(uint32).max,
            maxEndHint2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function setDripsPermuteHints(
        uint128 amt,
        DripsReceiver[] memory receivers,
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        uint256 expectedMaxEndFromNow
    ) internal {
        setDripsPermuteHintsCase(amt, receivers, 0, 0, expectedMaxEndFromNow);
        setDripsPermuteHintsCase(amt, receivers, 0, maxEndHint1, expectedMaxEndFromNow);
        setDripsPermuteHintsCase(amt, receivers, 0, maxEndHint2, expectedMaxEndFromNow);
        setDripsPermuteHintsCase(amt, receivers, maxEndHint1, 0, expectedMaxEndFromNow);
        setDripsPermuteHintsCase(amt, receivers, maxEndHint2, 0, expectedMaxEndFromNow);
        setDripsPermuteHintsCase(amt, receivers, maxEndHint1, maxEndHint2, expectedMaxEndFromNow);
        setDripsPermuteHintsCase(amt, receivers, maxEndHint2, maxEndHint1, expectedMaxEndFromNow);
        setDripsPermuteHintsCase(amt, receivers, maxEndHint1, maxEndHint1, expectedMaxEndFromNow);
        setDripsPermuteHintsCase(amt, receivers, maxEndHint2, maxEndHint2, expectedMaxEndFromNow);
    }

    function setDripsPermuteHintsCase(
        uint128 amt,
        DripsReceiver[] memory receivers,
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        uint256 expectedMaxEndFromNow
    ) internal {
        emit log_named_uint("Setting drips with hint 1", maxEndHint1);
        emit log_named_uint("               and hint 2", maxEndHint2);
        uint256 snapshot = vm.snapshot();
        setDrips(sender, 0, amt, receivers, maxEndHint1, maxEndHint2, expectedMaxEndFromNow);
        vm.revertTo(snapshot);
    }

    function testSqueezeDrips() public {
        uint128 amt = _cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1), _cycleSecs);
        skip(2);
        squeezeDrips(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveDrips(receiver, amt - 2);
    }

    function testSqueezeDripsRevertsWhenInvalidHistory() public {
        uint128 amt = _cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1), _cycleSecs);
        DripsHistory[] memory history = hist(sender);
        history[0].maxEnd += 1;
        skip(2);
        assertSqueezeDripsReverts(receiver, sender, 0, history, ERROR_HISTORY_INVALID);
    }

    function testSqueezeDripsRevertsWhenHistoryEntryContainsReceiversAndHash() public {
        uint128 amt = _cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1), _cycleSecs);
        DripsHistory[] memory history = hist(sender);
        history[0].dripsHash = Drips._hashDrips(history[0].receivers);
        skip(2);
        assertSqueezeDripsReverts(receiver, sender, 0, history, ERROR_HISTORY_UNCLEAR);
    }

    function testFundsAreNotSqueezeTwice() public {
        uint128 amt = _cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1), _cycleSecs);
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
        uint128 amt = _cycleSecs * 2;
        setDrips(sender, 0, amt, recv(receiver, 1), _cycleSecs * 2);
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

    function testFundsFromBeforeDrippingStartedAreNotSqueezed() public {
        skip(1);
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp - 1, 0), 10);
        squeezeDrips(receiver, sender, hist(sender), 0);
        skip(2);
        drainBalance(sender, 8);
        skipToCycleEnd();
        receiveDrips(receiver, 2);
    }

    function testFundsFromAfterDripsEndAreNotSqueezed() public {
        setDrips(sender, 0, 10, recv(receiver, 1, 0, 2), maxEndMax());
        skip(3);
        squeezeDrips(receiver, sender, hist(sender), 2);
        drainBalance(sender, 8);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
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
        uint128 amt = _cycleSecs * 2;
        setDrips(sender, 0, amt, recv(receiver, 1), _cycleSecs * 2);
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
        setDrips(sender, 0, _cycleSecs + 1, recv(receiver, 1), _cycleSecs + 1);
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
