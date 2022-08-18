// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {Drips, DripsConfig, DripsHistory, DripsConfigImpl, DripsReceiver} from "../Drips.sol";

contract PseudoRandomUtils {
    bytes32 private salt;
    bool private initialized = false;

    // returns a pseudo-random number between 0 and range
    function random(uint256 range) public returns (uint256) {
        require(initialized, "salt not set for test run");
        salt = keccak256(bytes.concat(salt));
        return uint256(salt) % range;
    }

    function initSalt(bytes32 salt_) public {
        require(initialized == false, "only init salt once per test run");
        salt = salt_;
        initialized = true;
    }
}

contract DripsTest is Test, PseudoRandomUtils, Drips {
    string internal constant ERROR_NOT_SORTED = "Receivers not sorted";
    string internal constant ERROR_INVALID_DRIPS_LIST = "Invalid current drips list";
    string internal constant ERROR_TIMESTAMP_EARLY = "Timestamp before last drips update";
    string internal constant ERROR_HISTORY_INVALID = "Invalid drips history";
    string internal constant ERROR_HISTORY_UNCLEAR = "Drips history entry with hash and receivers";

    uint32 internal cycleSecs;
    // Keys are assetId and userId
    mapping(uint256 => mapping(uint256 => DripsReceiver[])) internal currReceiversStore;
    uint256 internal defaultAsset = 1;
    uint256 internal otherAsset = 2;
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

    function loadCurrReceivers(uint256 assetId, uint256 userId)
        internal
        returns (DripsReceiver[] memory currReceivers)
    {
        currReceivers = currReceiversStore[assetId][userId];
        assertDrips(assetId, userId, currReceivers);
    }

    function storeCurrReceivers(
        uint256 assetId,
        uint256 userId,
        DripsReceiver[] memory newReceivers
    ) internal {
        assertDrips(assetId, userId, newReceivers);
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

    function recv(
        uint256 userId,
        uint256 amtPerSec,
        uint256 amtPerSecFrac
    ) internal pure returns (DripsReceiver[] memory receivers) {
        return recv(userId, amtPerSec, amtPerSecFrac, 0, 0);
    }

    function recv(
        uint256 userId,
        uint256 amtPerSec,
        uint256 start,
        uint256 duration
    ) internal pure returns (DripsReceiver[] memory receivers) {
        return recv(userId, amtPerSec, 0, start, duration);
    }

    function recv(
        uint256 userId,
        uint256 amtPerSec,
        uint256 amtPerSecFrac,
        uint256 start,
        uint256 duration
    ) internal pure returns (DripsReceiver[] memory receivers) {
        receivers = new DripsReceiver[](1);
        uint192 amtPerSecFull = uint192(
            (amtPerSec * Drips._AMT_PER_SEC_MULTIPLIER) + amtPerSecFrac
        );
        DripsConfig config = DripsConfigImpl.create(amtPerSecFull, uint32(start), uint32(duration));
        receivers[0] = DripsReceiver(userId, config);
    }

    function recv(DripsReceiver[] memory recv1, DripsReceiver[] memory recv2)
        internal
        pure
        returns (DripsReceiver[] memory receivers)
    {
        receivers = new DripsReceiver[](recv1.length + recv2.length);
        for (uint256 i = 0; i < recv1.length; i++) receivers[i] = recv1[i];
        for (uint256 i = 0; i < recv2.length; i++) receivers[recv1.length + i] = recv2[i];
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
        uint8 amountReceiver,
        uint128 maxAmtPerSec,
        uint32 maxStart,
        uint32 maxDuration
    ) internal returns (DripsReceiver[] memory) {
        uint256 inPercent = 100;
        uint256 probMaxEnd = random(inPercent);
        uint256 probStartNow = random(inPercent);
        return
            genRandomRecv(
                amountReceiver,
                maxAmtPerSec,
                maxStart,
                maxDuration,
                probMaxEnd,
                probStartNow
            );
    }

    function genRandomRecv(
        uint8 amountReceiver,
        uint128 maxAmtPerSec,
        uint32 maxStart,
        uint32 maxDuration,
        uint256 probMaxEnd,
        uint256 probStartNow
    ) internal returns (DripsReceiver[] memory) {
        DripsReceiver[] memory receivers = new DripsReceiver[](amountReceiver);
        for (uint8 i = 0; i < amountReceiver; i++) {
            uint256 amtPerSec = random(maxAmtPerSec) + 1;
            uint256 start = random(maxStart);
            if (start % 100 <= probStartNow) start = 0;
            uint256 duration = random(maxDuration);
            if (duration % 100 <= probMaxEnd) duration = 0;

            receivers[i] = DripsReceiver(
                i,
                DripsConfigImpl.create(uint128(amtPerSec), uint32(start), uint32(duration))
            );
        }
        return receivers;
    }

    function hist() internal pure returns (DripsHistory[] memory) {
        return new DripsHistory[](0);
    }

    function hist(
        DripsReceiver[] memory receivers,
        uint32 updateTime,
        uint32 maxEnd
    ) internal pure returns (DripsHistory[] memory history) {
        history = new DripsHistory[](1);
        history[0] = DripsHistory(0, receivers, updateTime, maxEnd);
    }

    function hist(
        bytes32 dripsHash,
        uint32 updateTime,
        uint32 maxEnd
    ) internal pure returns (DripsHistory[] memory history) {
        history = hist(recv(), updateTime, maxEnd);
        history[0].dripsHash = dripsHash;
    }

    function hist(uint256 userId) internal returns (DripsHistory[] memory history) {
        DripsReceiver[] memory receivers = loadCurrReceivers(defaultAsset, userId);
        (, , uint32 updateTime, , uint32 maxEnd) = Drips._dripsState(userId, defaultAsset);
        return hist(receivers, updateTime, maxEnd);
    }

    function histSkip(uint256 userId) internal view returns (DripsHistory[] memory history) {
        (bytes32 dripsHash, , uint32 updateTime, , uint32 maxEnd) = Drips._dripsState(
            userId,
            defaultAsset
        );
        return hist(dripsHash, updateTime, maxEnd);
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
        for (uint256 i = 0; i < history1.length; i++) history[i] = history1[i];
        for (uint256 i = 0; i < history2.length; i++) history[history1.length + i] = history2[i];
    }

    function setDrips(
        uint256 user,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        setDrips(defaultAsset, user, balanceFrom, balanceTo, newReceivers);
    }

    function setDrips(
        uint256 assetId,
        uint256 userId,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        (, bytes32 oldHistoryHash, , , ) = Drips._dripsState(userId, assetId);
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);

        (uint128 newBalance, int128 realBalanceDelta) = Drips._setDrips(
            userId,
            assetId,
            loadCurrReceivers(assetId, userId),
            balanceDelta,
            newReceivers
        );

        storeCurrReceivers(assetId, userId, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid drips balance");
        (
            bytes32 dripsHash,
            bytes32 historyHash,
            uint32 updateTime,
            uint128 actualBalance,
            uint32 maxEnd
        ) = Drips._dripsState(userId, assetId);
        assertEq(
            Drips._hashDripsHistory(oldHistoryHash, dripsHash, updateTime, maxEnd),
            historyHash,
            "Invalid history hash"
        );
        assertEq(updateTime, block.timestamp, "Invalid new last update time");
        assertEq(balanceTo, actualBalance, "Invalid drips balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
    }

    function assertDrips(
        uint256 assetId,
        uint256 userId,
        DripsReceiver[] memory currReceivers
    ) internal {
        (bytes32 actual, , , , ) = Drips._dripsState(userId, assetId);
        bytes32 expected = Drips._hashDrips(currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function assertBalance(uint256 userId, uint128 expected) internal {
        assertBalanceAt(userId, expected, block.timestamp);
    }

    function assertBalanceAt(
        uint256 userId,
        uint128 expected,
        uint256 timestamp
    ) internal {
        uint128 balance = Drips._balanceAt(
            userId,
            defaultAsset,
            loadCurrReceivers(defaultAsset, userId),
            uint32(timestamp)
        );
        assertEq(balance, expected, "Invaild drips balance");
    }

    function assertBalanceAtReverts(
        uint256 userId,
        DripsReceiver[] memory receivers,
        uint256 timestamp,
        string memory expectedReason
    ) internal {
        try this.balanceAtExternal(userId, receivers, timestamp) {
            assertTrue(false, "BalanceAt hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid balanceAt revert reason");
        }
    }

    function balanceAtExternal(
        uint256 userId,
        DripsReceiver[] memory receivers,
        uint256 timestamp
    ) external view {
        Drips._balanceAt(userId, defaultAsset, receivers, uint32(timestamp));
    }

    function assetMaxEnd(uint256 userId, uint256 expected) public {
        (, , , , uint32 maxEnd) = Drips._dripsState(userId, defaultAsset);
        assertEq(maxEnd, expected, "Invalid max end");
    }

    function changeBalance(
        uint256 userId,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        DripsReceiver[] memory receivers = recv();
        if (balanceTo != 0) {
            receivers = loadCurrReceivers(defaultAsset, userId);
        }
        setDrips(userId, balanceFrom, balanceTo, receivers);
    }

    function assertSetDripsReverts(
        uint256 userId,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        assertSetDripsReverts(
            userId,
            loadCurrReceivers(defaultAsset, userId),
            balanceFrom,
            balanceTo,
            newReceivers,
            expectedReason
        );
    }

    function assertSetDripsReverts(
        uint256 userId,
        DripsReceiver[] memory currReceivers,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        try
            this.setDripsExternal(
                defaultAsset,
                userId,
                currReceivers,
                int128(balanceTo) - int128(balanceFrom),
                newReceivers
            )
        {
            assertTrue(false, "Set drips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid set drips revert reason");
        }
    }

    function setDripsExternal(
        uint256 assetId,
        uint256 userId,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) external {
        Drips._setDrips(userId, assetId, currReceivers, balanceDelta, newReceivers);
    }

    function receiveDrips(uint256 userId, uint128 expectedAmt) internal {
        receiveDrips(defaultAsset, userId, expectedAmt);
    }

    function receiveDrips(
        uint256 assetId,
        uint256 userId,
        uint128 expectedAmt
    ) internal {
        (uint128 actualAmt, ) = Drips._receiveDrips(userId, assetId, type(uint32).max);
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
        assertReceivableDrips(userId, type(uint32).max, expectedTotalAmt, 0);
        assertReceivableDrips(userId, maxCycles, expectedReceivedAmt, expectedCyclesAfter);

        (uint128 receivedAmt, uint32 receivableCycles) = Drips._receiveDrips(
            userId,
            defaultAsset,
            maxCycles
        );

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from drips");
        assertEq(receivableCycles, expectedCyclesAfter, "Invalid receivable drips cycles left");
        assertReceivableDripsCycles(userId, expectedCyclesAfter);
        assertReceivableDrips(userId, type(uint32).max, expectedAmtAfter, 0);
    }

    function receiveDrips(
        DripsReceiver[] memory receivers,
        uint32 maxEnd,
        uint32 updateTime
    ) internal {
        emit log_named_uint("maxEnd:", maxEnd);
        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory r = receivers[i];
            uint32 duration = r.config.duration();
            uint32 start = r.config.start();
            if (start == 0) start = updateTime;
            if (duration == 0) duration = maxEnd - start;
            // drips was in the past, not added
            if (start + duration < updateTime) duration = 0;
            else if (start < updateTime) duration -= updateTime - start;

            uint256 expectedAmt = (duration * r.config.amtPerSec()) >> 64;
            (uint128 actualAmt, ) = Drips._receiveDrips(r.userId, defaultAsset, type(uint32).max);
            // only log if acutalAmt doesn't match exptectedAmt
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
        uint32 actualCycles = Drips._receivableDripsCycles(userId, defaultAsset);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable drips cycles");
    }

    function assertReceivableDrips(uint256 userId, uint128 expectedAmt) internal {
        (uint128 actualAmt, ) = Drips._receivableDrips(userId, defaultAsset, type(uint32).max);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
    }

    function assertReceivableDrips(
        uint256 userId,
        uint32 maxCycles,
        uint128 expectedAmt,
        uint32 expectedCycles
    ) internal {
        (uint128 actualAmt, uint32 actualCycles) = Drips._receivableDrips(
            userId,
            defaultAsset,
            maxCycles
        );
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
        assertEq(actualCycles, expectedCycles, "Invalid receivable drips cycles");
    }

    function squeezeDrips(
        uint256 userId,
        uint256 senderId,
        DripsHistory[] memory dripsHistory,
        uint256 expectedAmt,
        uint256 expectedNextSqueezed
    ) internal {
        squeezeDrips(userId, senderId, 0, dripsHistory, expectedAmt, expectedNextSqueezed);
    }

    function squeezeDrips(
        uint256 userId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory,
        uint256 expectedAmt,
        uint256 expectedNextSqueezed
    ) internal {
        uint256 assetId = defaultAsset;
        (uint128 amtBefore, uint32 nextSqueezedBefore) = Drips._squeezableDrips(
            userId,
            assetId,
            senderId,
            historyHash,
            dripsHistory
        );

        (uint128 amt, uint32 nextSqueezed) = Drips._squeezeDrips(
            userId,
            assetId,
            senderId,
            historyHash,
            dripsHistory
        );

        assertEq(amt, expectedAmt, "Invalid squeezed amount");
        assertEq(nextSqueezed, expectedNextSqueezed, "Invalid next squeezed");
        assertEq(amtBefore, amt, "Invalid squeezable amount before squeezing");
        assertEq(nextSqueezedBefore, nextSqueezed, "Invalid next squeezed before squeezing");
        (uint128 amtAfter, uint32 nextSqueezedAfter) = Drips._squeezableDrips(
            userId,
            assetId,
            senderId,
            historyHash,
            dripsHistory
        );
        assertEq(amtAfter, 0, "Squeezable amount after squeezing non-zero");
        assertEq(nextSqueezedAfter, nextSqueezed, "Invalid next squeezed after squeezing");
        assertNextSqueezedDrips(userId, assetId, senderId, nextSqueezed);
    }

    function assertSqueezeDripsReverts(
        uint256 userId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory,
        string memory expectedReason
    ) internal {
        try this.squeezeDripsExternal(userId, defaultAsset, senderId, historyHash, dripsHistory) {
            assertTrue(false, "SqueezeDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid squeezeDrips revert reason");
        }
    }

    function squeezeDripsExternal(
        uint256 userId,
        uint256 assetId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) external {
        Drips._squeezeDrips(userId, assetId, senderId, historyHash, dripsHistory);
    }

    function assertSqueezableDripsReverts(
        uint256 userId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory,
        string memory expectedReason
    ) internal {
        try
            this.squeezableDripsExternal(userId, defaultAsset, senderId, historyHash, dripsHistory)
        {
            assertTrue(false, "SqueezableDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid squeezableDrips revert reason");
        }
    }

    function squeezableDripsExternal(
        uint256 userId,
        uint256 assetId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) external view {
        Drips._squeezableDrips(userId, assetId, senderId, historyHash, dripsHistory);
    }

    function assertNextSqueezedDrips(
        uint256 userId,
        uint256 assetId,
        uint256 senderId,
        uint256 expected
    ) internal {
        uint256 actual = Drips._nextSqueezedDrips(userId, assetId, senderId);
        assertEq(actual, expected, "Invalid next squeezable drips");
    }

    function testDripsConfigStoresParameters() public {
        DripsConfig config = DripsConfigImpl.create(1, 2, 3);
        assertEq(config.amtPerSec(), 1, "Invalid amtPerSec");
        assertEq(config.start(), 2, "Invalid start");
        assertEq(config.duration(), 3, "Invalid duration");
    }

    function testDripsConfigChecksOrdering() public {
        DripsConfig config = DripsConfigImpl.create(1, 1, 1);
        assertTrue(!config.lt(config), "Configs equal");

        DripsConfig higherAmtPerSec = DripsConfigImpl.create(2, 1, 1);
        assertTrue(config.lt(higherAmtPerSec), "AmtPerSec higher");
        assertTrue(!higherAmtPerSec.lt(config), "AmtPerSec lower");

        DripsConfig higherStart = DripsConfigImpl.create(1, 2, 1);
        assertTrue(config.lt(higherStart), "Start higher");
        assertTrue(!higherStart.lt(config), "Start lower");

        DripsConfig higherDuration = DripsConfigImpl.create(1, 1, 2);
        assertTrue(config.lt(higherDuration), "Duration higher");
        assertTrue(!higherDuration.lt(config), "Duration lower");
    }

    function testAllowsDrippingToASingleReceiver() public {
        setDrips(sender, 0, 100, recv(receiver, 1));
        skip(15);
        // Sender had 15 seconds paying 1 per second
        changeBalance(sender, 85, 0);
        skipToCycleEnd();
        // Receiver 1 had 15 seconds paying 1 per second
        receiveDrips(receiver, 15);
    }

    function testDripsToTwoReceivers() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 1), recv(receiver2, 1)));
        skip(14);
        // Sender had 14 seconds paying 2 per second
        changeBalance(sender, 72, 0);
        skipToCycleEnd();
        // Receiver 1 had 14 seconds paying 1 per second
        receiveDrips(receiver1, 14);
        // Receiver 2 had 14 seconds paying 1 per second
        receiveDrips(receiver2, 14);
    }

    function testDripsFromTwoSendersToASingleReceiver() public {
        setDrips(sender1, 0, 100, recv(receiver, 1));
        skip(2);
        setDrips(sender2, 0, 100, recv(receiver, 2));
        skip(15);
        // Sender1 had 17 seconds paying 1 per second
        changeBalance(sender1, 83, 0);
        // Sender2 had 15 seconds paying 2 per second
        changeBalance(sender2, 70, 0);
        skipToCycleEnd();
        // Receiver had 2 seconds paying 1 per second and 15 seconds paying 3 per second
        receiveDrips(receiver, 47);
    }

    function testDripsWithStartAndDuration() public {
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp + 5, 10));
        skip(5);
        assertBalance(sender, 10);
        skip(10);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 10);
    }

    function testDripsWithStartAndDurationWithInsufficientBalance() public {
        setDrips(sender, 0, 1, recv(receiver, 1, block.timestamp + 1, 2));
        skip(1);
        assertBalance(sender, 1);
        skip(1);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
    }

    function testDripsWithOnlyDuration() public {
        setDrips(sender, 0, 10, recv(receiver, 1, 0, 10));
        skip(10);
        skipToCycleEnd();
        receiveDrips(receiver, 10);
    }

    function testDripsWithOnlyDurationWithInsufficientBalance() public {
        setDrips(sender, 0, 1, recv(receiver, 1, 0, 2));
        assertBalance(sender, 1);
        skip(1);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
    }

    function testDripsWithOnlyStart() public {
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp + 5, 0));
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
            )
        );
        skip(8);
        assertBalance(sender, 5);
        skipToCycleEnd();
        receiveDrips(receiver1, 3);
        receiveDrips(receiver2, 16);
        receiveDrips(receiver3, 15);
        changeBalance(sender, 5, 0);
    }

    function testTwoDripsToSingleReceiver() public {
        setDrips(
            sender,
            0,
            28,
            recv(
                recv(receiver, 1, block.timestamp + 5, 10),
                recv(receiver, 2, block.timestamp + 10, 9)
            )
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
            )
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
        setDrips(sender, 0, 3, recv(receiver, 1, block.timestamp - 5, 0));
        skip(3);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 3);
    }

    function testDripsWithStartInThePastAndDurationIntoFuture() public {
        skip(5);
        setDrips(sender, 0, 3, recv(receiver, 1, block.timestamp - 5, 8));
        skip(3);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveDrips(receiver, 3);
    }

    function testDripsWithStartAndDurationInThePast() public {
        skip(5);
        setDrips(sender, 0, 0, recv(receiver, 1, block.timestamp - 5, 3));
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDripsWithStartAfterFundsRunOut() public {
        setDrips(
            sender,
            0,
            4,
            recv(recv(receiver1, 1), recv(receiver2, 2, block.timestamp + 5, 0))
        );
        skip(6);
        skipToCycleEnd();
        receiveDrips(receiver1, 4);
        receiveDrips(receiver2, 0);
    }

    function testDripsWithStartInTheFutureCycleCanBeMovedToAnEarlierOne() public {
        setDrips(sender, 0, 1, recv(receiver, 1, block.timestamp + cycleSecs, 0));
        setDrips(sender, 1, 1, recv(receiver, 1));
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
            )
        );
        skip(3);
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
        setDrips(sender, 0, 1, recv(receiver, 1, block.timestamp + cycleSecs * 2, 0));
        // The first cycle hasn't been dripping
        skipToCycleEnd();
        assertReceivableDripsCycles(receiver, 0);
        assertReceivableDrips(receiver, 0);
        // The second cycle hasn't been dripping
        skipToCycleEnd();
        assertReceivableDripsCycles(receiver, 0);
        assertReceivableDrips(receiver, 0);
        // The third cycle has been dripping
        skipToCycleEnd();
        assertReceivableDripsCycles(receiver, 1);
        receiveDrips(receiver, 1);
    }

    function testAllowsReceivingWhileBeingDrippedTo() public {
        setDrips(sender, 0, cycleSecs + 10, recv(receiver, 1));
        skipToCycleEnd();
        // Receiver had cycleSecs seconds paying 1 per second
        receiveDrips(receiver, cycleSecs);
        skip(7);
        // Sender had cycleSecs + 7 seconds paying 1 per second
        changeBalance(sender, 3, 0);
        skipToCycleEnd();
        // Receiver had 7 seconds paying 1 per second
        receiveDrips(receiver, 7);
    }

    function testDripsFundsUntilTheyRunOut() public {
        setDrips(sender, 0, 100, recv(receiver, 9));
        skip(10);
        // Sender had 10 seconds paying 9 per second, drips balance is about to run out
        assertBalance(sender, 10);
        skip(1);
        // Sender had 11 seconds paying 9 per second, drips balance has run out
        assertBalance(sender, 1);
        // Nothing more will be dripped
        skipToCycleEnd();
        changeBalance(sender, 1, 0);
        receiveDrips(receiver, 99);
    }

    function testAllowsDripsConfigurationWithOverflowingTotalAmtPerSec() public {
        setDrips(sender, 0, 2, recv(recv(receiver, 1), recv(receiver, type(uint128).max)));
        skipToCycleEnd();
        // Sender hasn't sent anything
        changeBalance(sender, 2, 0);
        // Receiver hasnt received anything
        receiveDrips(receiver, 0);
    }

    function testAllowsDripsConfigurationWithOverflowingAmtPerCycle() public {
        // amtPerSec is valid, but amtPerCycle is over 2 times higher than int128.max.
        // The multiplier is chosen to prevent the amounts from being "clean" binary numbers
        // which could make the overflowing behavior correct by coincidence.
        uint128 amtPerSec = (uint128(type(int128).max) / cycleSecs / 1000) * 2345;
        uint128 amt = amtPerSec * 4;
        setDrips(sender, 0, amt, recv(receiver, amtPerSec));
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
        setDrips(sender, 0, amt, recv(receiver, amtPerSec, block.timestamp + cycleSecs - secs, 0));
        skipToCycleEnd();
        assertReceivableDrips(receiver, amt / 2);
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
        setDrips(sender1, 0, amt, recv(receiver, amtPerSec));
        // Alter amtDeltas by +0.0812 for the current cycle and -0.0812 for the next one
        // As an intermediate step when the drips start is applied at the middle of the cycle,
        // but the end not yet, apply +0.406 for the current cycle and -0.406 for the next one.
        // It makes amtDeltas reach +1.218 for the current cycle and -1.218 for the next one.
        setDrips(sender2, 0, amtPerSec, recv(receiver, amtPerSec, cycleSecs / 2, 0));
        skipToCycleEnd();
        receiveDrips(receiver, amt + amtPerSec);
    }

    function testAllowsToppingUpWhileDripping() public {
        setDrips(sender, 0, 100, recv(receiver, 10));
        skip(6);
        // Sender had 6 seconds paying 10 per second
        changeBalance(sender, 40, 60);
        skip(5);
        // Sender had 5 seconds paying 10 per second
        changeBalance(sender, 10, 0);
        skipToCycleEnd();
        // Receiver had 11 seconds paying 10 per second
        receiveDrips(receiver, 110);
    }

    function testAllowsToppingUpAfterFundsRunOut() public {
        setDrips(sender, 0, 100, recv(receiver, 10));
        skip(10);
        // Sender had 10 seconds paying 10 per second
        assertBalance(sender, 0);
        skipToCycleEnd();
        // Receiver had 10 seconds paying 10 per second
        assertReceivableDrips(receiver, 100);
        changeBalance(sender, 0, 60);
        skip(5);
        // Sender had 5 seconds paying 10 per second
        changeBalance(sender, 10, 0);
        skipToCycleEnd();
        // Receiver had 15 seconds paying 10 per second
        receiveDrips(receiver, 150);
    }

    function testAllowsDrippingWhichShouldEndAfterMaxTimestamp() public {
        uint128 balance = type(uint32).max + uint128(6);
        setDrips(sender, 0, balance, recv(receiver, 1));
        skip(10);
        // Sender had 10 seconds paying 1 per second
        changeBalance(sender, balance - 10, 0);
        skipToCycleEnd();
        // Receiver had 10 seconds paying 1 per second
        receiveDrips(receiver, 10);
    }

    function testAllowsDrippingWithDurationEndingAfterMaxTimestamp() public {
        uint32 maxTimestamp = type(uint32).max;
        uint32 currTimestamp = uint32(block.timestamp);
        uint32 maxDuration = maxTimestamp - currTimestamp;
        uint32 duration = maxDuration + 5;
        setDrips(sender, 0, duration, recv(receiver, 1, 0, duration));
        skipToCycleEnd();
        receiveDrips(receiver, cycleSecs);
        setDrips(sender, duration - cycleSecs, 0, recv());
    }

    function testAllowsChangingReceiversWhileDripping() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 6), recv(receiver2, 6)));
        skip(3);
        setDrips(sender, 64, 64, recv(recv(receiver1, 4), recv(receiver2, 8)));
        skip(4);
        // Sender had 7 seconds paying 12 per second
        changeBalance(sender, 16, 0);
        skipToCycleEnd();
        // Receiver1 had 3 seconds paying 6 per second and 4 seconds paying 4 per second
        receiveDrips(receiver1, 34);
        // Receiver2 had 3 seconds paying 6 per second and 4 seconds paying 8 per second
        receiveDrips(receiver2, 50);
    }

    function testAllowsRemovingReceiversWhileDripping() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 5), recv(receiver2, 5)));
        skip(3);
        setDrips(sender, 70, 70, recv(receiver2, 10));
        skip(4);
        setDrips(sender, 30, 30, recv());
        skip(10);
        // Sender had 7 seconds paying 10 per second
        changeBalance(sender, 30, 0);
        skipToCycleEnd();
        // Receiver1 had 3 seconds paying 5 per second
        receiveDrips(receiver1, 15);
        // Receiver2 had 3 seconds paying 5 per second and 4 seconds paying 10 per second
        receiveDrips(receiver2, 55);
    }

    function testDrippingFractions() public {
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / cycleSecs + 1;
        setDrips(sender, 0, 2, recv(receiver, 0, onePerCycle));
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
        setDrips(sender, 0, 1, recv(receiver, 0, onePerCycle * 2));
        // Full units are dripped on cycle timestamps 4 and 9
        assetMaxEnd(sender, block.timestamp + 9);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 1);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDrippingFractionsWithFundsEnoughForOneCycle() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / cycleSecs + 1;
        setDrips(sender, 0, 2, recv(receiver, 0, onePerCycle * 2));
        // Full units are dripped on cycle timestamps 4 and 9
        assetMaxEnd(sender, block.timestamp + cycleSecs + 4);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveDrips(receiver, 2);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDrippingFractionsWithFundsEnoughForTwoCycles() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = Drips._AMT_PER_SEC_MULTIPLIER / cycleSecs + 1;
        setDrips(sender, 0, 4, recv(receiver, 0, onePerCycle * 2));
        // Full units are dripped on cycle timestamps 4 and 9
        assetMaxEnd(sender, block.timestamp + cycleSecs * 2 + 4);
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
        setDrips(sender, 0, 3, recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1));
        // Full units are dripped on cycle timestamps 3 and 7
        assetMaxEnd(sender, block.timestamp + cycleSecs + 7);
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
        setDrips(sender, 0, 3, recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1));
        // Full units are dripped on cycle timestamps 3 and 7
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
        setDrips(sender, 0, 2, recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1));
        // Full units are dripped on cycle timestamps 3 and 7
        assetMaxEnd(sender, block.timestamp + cycleSecs + 3);
        // Top up 2
        changeBalance(sender, 2, 4);
        assetMaxEnd(sender, block.timestamp + cycleSecs * 2 + 3);
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
            )
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
        assetMaxEnd(sender, block.timestamp + 13);
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
        setDrips(sender1, 0, 3, recv(receiver, 0, Drips._AMT_PER_SEC_MULTIPLIER / 4 + 1));
        // Rate of 0.66 per second or 6.6 per cycle
        setDrips(sender2, 0, 7, recv(receiver, 0, (Drips._AMT_PER_SEC_MULTIPLIER / 100 + 1) * 66));
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

    function testMaxEndSmallerThenScheduledDripStart() public {
        setDrips(sender, 0, 120, recv(recv(receiver1, 1), recv(receiver2, 1, 100, 100)));
    }

    function testLimitsTheTotalReceiversCount() public {
        uint160 countMax = Drips._MAX_DRIPS_RECEIVERS;
        DripsReceiver[] memory receivers = new DripsReceiver[](countMax);
        for (uint160 i = 0; i < countMax; i++) {
            receivers[i] = recv(i, 1, 0, 0)[0];
        }
        setDrips(sender, 0, uint128(countMax), receivers);
        receivers = recv(receivers, recv(countMax, 1, 0, 0));
        assertSetDripsReverts(
            sender,
            uint128(countMax),
            uint128(countMax + 1),
            receivers,
            "Too many drips receivers"
        );
    }

    function testBenchSetDrips100() public {
        uint160 countMax = Drips._MAX_DRIPS_RECEIVERS;
        DripsReceiver[] memory receivers = new DripsReceiver[](countMax);
        for (uint160 i = 0; i < countMax; i++) {
            receivers[i] = recv(i, 1, 1000 + i, 0)[0];
        }

        uint256 gas = gasleft();
        Drips._setDrips(
            sender,
            defaultAsset,
            new DripsReceiver[](0),
            int128(int160((countMax * countMax))),
            receivers
        );
        gas -= gasleft();
        emit log_named_uint("GAS USED", gas);
    }

    function testBenchSetDrips100Worst() public {
        // The worst possible case: dripping until the maximum timestamp minus 1 second.
        // Every candidate end time requires iterating over all the receivers to tell that
        // the balance is enough to cover it, but on the highest possible timestamp
        // there isn't enough funds, so we can't skip the whole search.
        uint160 countMax = Drips._MAX_DRIPS_RECEIVERS;
        DripsReceiver[] memory receivers = new DripsReceiver[](countMax);
        for (uint160 i = 0; i < countMax; i++) {
            receivers[i] = recv(i, 1, 0, 0)[0];
        }
        uint128 amt = (type(uint32).max - uint32(block.timestamp)) * uint128(countMax) - 1;

        uint256 gas = gasleft();
        Drips._setDrips(sender, defaultAsset, new DripsReceiver[](0), int128(amt), receivers);
        gas -= gasleft();
        emit log_named_uint("GAS USED", gas);
    }

    function testBenchSetDrips10() public {
        uint160 countMax = 10;
        DripsReceiver[] memory receivers = new DripsReceiver[](countMax);
        for (uint160 i = 0; i < countMax; i++) {
            receivers[i] = recv(i, 1, 1000 + i, 0)[0];
        }

        uint256 gas = gasleft();
        Drips._setDrips(
            sender,
            defaultAsset,
            new DripsReceiver[](0),
            int128(int160((countMax * countMax))),
            receivers
        );
        gas -= gasleft();
        emit log_named_uint("GAS USED", gas);
    }

    function testBenchSetDrips10Worst() public {
        // The worst possible case: dripping until the maximum timestamp minus 1 second.
        // Every candidate end time requires iterating over all the receivers to tell that
        // the balance is enough to cover it, but on the highest possible timestamp
        // there isn't enough funds, so we can't skip the whole search.
        uint160 countMax = 10;
        DripsReceiver[] memory receivers = new DripsReceiver[](countMax);
        for (uint160 i = 0; i < countMax; i++) {
            receivers[i] = recv(i, 1, 0, 0)[0];
        }
        uint128 amt = (type(uint32).max - uint32(block.timestamp)) * uint128(countMax) - 1;

        uint256 gas = gasleft();
        Drips._setDrips(sender, defaultAsset, new DripsReceiver[](0), int128(amt), receivers);
        gas -= gasleft();
        emit log_named_uint("GAS USED", gas);
    }

    function testBenchSetDrips1() public {
        DripsReceiver[] memory receivers = recv(1, 1, 1000, 0);
        uint256 gas = gasleft();
        Drips._setDrips(sender, defaultAsset, new DripsReceiver[](0), 1, receivers);
        gas -= gasleft();
        emit log_named_uint("GAS USED", gas);
    }

    function testRejectsZeroAmtPerSecReceivers() public {
        assertSetDripsReverts(sender, 0, 0, recv(receiver, 0), "Drips receiver amtPerSec is zero");
    }

    function testDripsNotSortedByReceiverAreRejected() public {
        assertSetDripsReverts(
            sender,
            0,
            0,
            recv(recv(receiver2, 1), recv(receiver1, 1)),
            ERROR_NOT_SORTED
        );
    }

    function testDripsNotSortedByAmtPerSecAreRejected() public {
        assertSetDripsReverts(
            sender,
            0,
            0,
            recv(recv(receiver, 2), recv(receiver, 1)),
            ERROR_NOT_SORTED
        );
    }

    function testDripsNotSortedByStartAreRejected() public {
        assertSetDripsReverts(
            sender,
            0,
            0,
            recv(recv(receiver, 1, 2, 0), recv(receiver, 1, 1, 0)),
            ERROR_NOT_SORTED
        );
    }

    function testDripsNotSortedByDurationAreRejected() public {
        assertSetDripsReverts(
            sender,
            0,
            0,
            recv(recv(receiver, 1, 1, 2), recv(receiver, 1, 1, 1)),
            ERROR_NOT_SORTED
        );
    }

    function testRejectsDuplicateReceivers() public {
        assertSetDripsReverts(
            sender,
            0,
            0,
            recv(recv(receiver, 1), recv(receiver, 1)),
            ERROR_NOT_SORTED
        );
    }

    function testSetDripsRevertsIfInvalidCurrReceivers() public {
        setDrips(sender, 0, 1, recv(receiver, 1));
        assertSetDripsReverts(sender, recv(receiver, 2), 0, 0, recv(), ERROR_INVALID_DRIPS_LIST);
    }

    function testAllowsAnAddressToDripAndReceiveIndependently() public {
        setDrips(sender, 0, 10, recv(sender, 10));
        skip(1);
        // Sender had 1 second paying 10 per second
        assertBalance(sender, 0);
        skipToCycleEnd();
        // Sender had 1 second paying 10 per second
        receiveDrips(sender, 10);
    }

    function testCapsWithdrawalOfMoreThanDripsBalance() public {
        DripsReceiver[] memory receivers = recv(receiver, 1, 0, 10);
        setDrips(sender, 0, 10, receivers);
        skip(4);
        // Sender had 4 second paying 1 per second

        DripsReceiver[] memory newRecv = recv();
        (uint128 newBalance, int128 realBalanceDelta) = Drips._setDrips(
            sender,
            defaultAsset,
            receivers,
            type(int128).min,
            newRecv
        );
        storeCurrReceivers(defaultAsset, sender, newRecv);
        assertEq(newBalance, 0, "Invalid balance");
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
        setDrips(sender, 0, amt, recv(receiver, 1));
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
        setDrips(sender, 0, amt, recv(recv(sender, 1), recv(receiver, 2)));
        skipToCycleEnd();
        receiveDrips(sender, cycleSecs);
        receiveDrips(receiver, cycleSecs * 2);
    }

    function testUpdateDefaultStartDrip() public {
        skipToCycleEnd();
        uint256 start = 0;
        uint128 amt = 3 * cycleSecs;
        uint32 duration = 3 * cycleSecs;
        uint256 amtPerSec = 1;
        // currRecv.start == 0 && currRecv.duration != 0
        setDrips(sender, 0, amt, recv(receiver, amtPerSec, start, duration));
        skipToCycleEnd();

        skip(cycleSecs);
        // remove drips after two cycles, no balance change
        setDrips(sender, 10, 10, recv());

        skip(cycleSecs * 5);
        // only two cycles should be dripped
        receiveDrips(defaultAsset, receiver, 2 * cycleSecs);
    }

    function testDripsOfDifferentAssetsAreIndependent() public {
        // Covers 1.5 cycles of dripping
        setDrips(
            defaultAsset,
            sender,
            0,
            9 * cycleSecs,
            recv(recv(receiver1, 4), recv(receiver2, 2))
        );

        skipToCycleEnd();
        // Covers 2 cycles of dripping
        setDrips(otherAsset, sender, 0, 6 * cycleSecs, recv(receiver1, 3));

        skipToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        receiveDrips(defaultAsset, receiver1, 6 * cycleSecs);
        // receiver1 had 1.5 cycles of 2 per second
        receiveDrips(defaultAsset, receiver2, 3 * cycleSecs);
        // receiver1 had 1 cycle of 3 per second
        receiveDrips(otherAsset, receiver1, 3 * cycleSecs);
        // receiver2 received nothing
        receiveDrips(otherAsset, receiver2, 0);

        skipToCycleEnd();
        // receiver1 received nothing
        receiveDrips(defaultAsset, receiver1, 0);
        // receiver2 received nothing
        receiveDrips(defaultAsset, receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        receiveDrips(otherAsset, receiver1, 3 * cycleSecs);
        // receiver2 received nothing
        receiveDrips(otherAsset, receiver2, 0);
    }

    function testBalanceAtReturnsCurrentBalance() public {
        setDrips(defaultAsset, sender, 0, 10, recv(receiver, 1));
        skip(2);
        assertBalanceAt(sender, 8, block.timestamp);
    }

    function testBalanceAtReturnsFutureBalance() public {
        setDrips(defaultAsset, sender, 0, 10, recv(receiver, 1));
        skip(2);
        assertBalanceAt(sender, 6, block.timestamp + 2);
    }

    function testBalanceAtReturnsPastBalanceAfterSetDelta() public {
        setDrips(defaultAsset, sender, 0, 10, recv(receiver, 1));
        skip(2);
        assertBalanceAt(sender, 10, block.timestamp - 2);
    }

    function testBalanceAtRevertsForTimestampBeforeSetDelta() public {
        DripsReceiver[] memory receivers = recv(receiver, 1);
        setDrips(defaultAsset, sender, 0, 10, receivers);
        skip(2);
        assertBalanceAtReverts(sender, receivers, block.timestamp - 3, ERROR_TIMESTAMP_EARLY);
    }

    function testBalanceAtRevertsForInvalidDripsList() public {
        DripsReceiver[] memory receivers = recv(receiver, 1);
        setDrips(defaultAsset, sender, 0, 10, receivers);
        skip(2);
        receivers = recv(receiver, 2);
        assertBalanceAtReverts(sender, receivers, block.timestamp, ERROR_INVALID_DRIPS_LIST);
    }

    function testFuzzDripsReceiver(bytes32 salt) public {
        initSalt(salt);
        uint8 amountReceivers = 10;
        uint128 maxAmtPerSec = 50;
        uint32 maxDuration = 100;
        uint32 maxStart = 100;

        uint128 maxCosts = amountReceivers * maxAmtPerSec * maxDuration;
        emit log_named_uint("topUp", maxCosts);
        uint128 maxAllDripsFinished = maxStart + maxDuration;

        DripsReceiver[] memory receivers = genRandomRecv(
            amountReceivers,
            maxAmtPerSec,
            maxStart,
            maxDuration
        );
        emit log_named_uint("setDrips.updateTime", block.timestamp);
        setDrips(sender, 0, maxCosts, receivers);

        (, , uint32 updateTime, , uint32 maxEnd) = Drips._dripsState(sender, defaultAsset);

        if (maxEnd > maxAllDripsFinished && maxEnd != type(uint32).max)
            maxAllDripsFinished = maxEnd;

        skip(maxAllDripsFinished);
        skipToCycleEnd();
        emit log_named_uint("receiveDrips.time", block.timestamp);
        receiveDrips(receivers, maxEnd, updateTime);
    }

    function testReceiverMaxEndExampleA() public {
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 1, start: 50, duration: 0}),
            recv({userId: receiver2, amtPerSec: 1, start: 0, duration: 0})
        );

        skipTo(0);
        assertEq(Drips._calcMaxEnd(100, receivers), 75);
    }

    function testReceiverMaxEndExampleB() public {
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 2, start: 100, duration: 0}),
            recv({userId: receiver2, amtPerSec: 4, start: 120, duration: 0})
        );

        // in the past
        skipTo(70);
        assertEq(Drips._calcMaxEnd(100, receivers), 130);
    }

    function _receiverMaxEndEdgeCase(uint128 balance) internal {
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 2, start: 0, duration: 0}),
            recv({userId: receiver2, amtPerSec: 1, start: 2, duration: 0})
        );
        skipTo(0);
        assertEq(Drips._calcMaxEnd(balance, receivers), 3);
    }

    function testReceiverMaxEndEdgeCase() public {
        _receiverMaxEndEdgeCase(7);
    }

    function testFailReceiverMaxEndEdgeCase() public {
        _receiverMaxEndEdgeCase(6);
    }

    function testReceiverMaxEndNotEnoughToCoverAll() public {
        DripsReceiver[] memory receivers = recv(
            recv({userId: receiver1, amtPerSec: 1, start: 50, duration: 0}),
            recv({userId: receiver2, amtPerSec: 1, start: 1000, duration: 0})
        );
        skipTo(0);
        assertEq(Drips._calcMaxEnd(100, receivers), 150);
    }

    function testSqueezeDrips() public {
        uint128 amt = cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1));
        skip(2);
        squeezeDrips(receiver, sender, hist(sender), 2, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, amt - 2);
    }

    function testSqueezeDripsRevertsWhenInvalidHistory() public {
        uint128 amt = cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1));
        DripsHistory[] memory history = hist(sender);
        history[0].maxEnd += 1;
        skip(2);
        assertSqueezeDripsReverts(receiver, sender, 0, history, ERROR_HISTORY_INVALID);
    }

    function testSqueezeDripsRevertsWhenHistoryEntryContainsReceiversAndHash() public {
        uint128 amt = cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1));
        DripsHistory[] memory history = hist(sender);
        history[0].dripsHash = Drips._hashDrips(history[0].receivers);
        skip(2);
        assertSqueezeDripsReverts(receiver, sender, 0, history, ERROR_HISTORY_UNCLEAR);
    }

    function testFundsAreNotSqueezeTwice() public {
        uint128 amt = cycleSecs;
        setDrips(sender, 0, amt, recv(receiver, 1));
        DripsHistory[] memory history = hist(sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 1, block.timestamp);
        skip(2);
        squeezeDrips(receiver, sender, history, 2, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, amt - 3);
    }

    function testFundsFromFinishedCyclesAreNotSqueezed() public {
        uint128 amt = cycleSecs * 2;
        setDrips(sender, 0, amt, recv(receiver, 1));
        skipToCycleEnd();
        skip(2);
        squeezeDrips(receiver, sender, hist(sender), 2, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, amt - 2);
    }

    function testHistoryFromFinishedCyclesIsNotSqueezed() public {
        setDrips(sender, 0, 2, recv(receiver, 1));
        DripsHistory[] memory history = hist(sender);
        skipToCycleEnd();
        setDrips(sender, 0, 6, recv(receiver, 3));
        history = hist(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 3, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, 5);
    }

    function testFundsFromAfterDripsRunOutAreNotSqueezed() public {
        uint128 amt = 2;
        setDrips(sender, 0, amt, recv(receiver, 1));
        skip(3);
        squeezeDrips(receiver, sender, hist(sender), 2, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testOnFirstSecondOfCycleNoFundsCanBeSqueezed() public {
        uint128 amt = cycleSecs * 2;
        setDrips(sender, 0, amt, recv(receiver, 1));
        skipToCycleEnd();
        squeezeDrips(receiver, sender, hist(sender), 0, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, amt);
    }

    function testDripsWithStartAndDurationCanBeSqueezed() public {
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp + 2, 2));
        skip(5);
        squeezeDrips(receiver, sender, hist(sender), 2, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testEmptyHistoryCanBeSqueezed() public {
        skip(1);
        squeezeDrips(receiver, sender, hist(), 0, block.timestamp - 1);
    }

    function testHistoryWithoutTheSqueezingReceiverCanBeSqueezed() public {
        setDrips(sender, 0, 1, recv(receiver1, 1));
        DripsHistory[] memory history = hist(sender);
        skip(1);
        squeezeDrips(receiver2, sender, history, 0, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver1, 1);
    }

    function testSendersCanBeSqueezedIndependently() public {
        setDrips(sender1, 0, 4, recv(receiver, 2));
        DripsHistory[] memory history1 = hist(sender1);
        setDrips(sender2, 0, 6, recv(receiver, 3));
        DripsHistory[] memory history2 = hist(sender2);
        skip(1);
        squeezeDrips(receiver, sender1, history1, 2, block.timestamp);
        skip(1);
        squeezeDrips(receiver, sender2, history2, 6, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, 2);
    }

    function testMultipleHistoryEntriesCanBeSqueezed() public {
        setDrips(sender, 0, 5, recv(receiver, 1));
        DripsHistory[] memory history = hist(sender);
        skip(1);
        setDrips(sender, 4, 4, recv(receiver, 2));
        history = hist(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 3, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, 2);
    }

    function testMiddleHistoryEntryCanBeSkippedWhenSqueezing() public {
        DripsHistory[] memory history = hist();
        setDrips(sender, 0, 1, recv(receiver, 1));
        history = hist(history, sender);
        skip(1);
        setDrips(sender, 0, 2, recv(receiver, 2));
        history = histSkip(history, sender);
        skip(1);
        setDrips(sender, 0, 4, recv(receiver, 4));
        history = hist(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 5, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, 2);
    }

    function testFirstAndLastHistoryEntriesCanBeSkippedWhenSqueezing() public {
        DripsHistory[] memory history = hist();
        setDrips(sender, 0, 1, recv(receiver, 1));
        history = histSkip(history, sender);
        skip(1);
        setDrips(sender, 0, 2, recv(receiver, 2));
        history = hist(history, sender);
        skip(1);
        setDrips(sender, 0, 4, recv(receiver, 4));
        history = histSkip(history, sender);
        skip(1);
        squeezeDrips(receiver, sender, history, 2, block.timestamp - 1);
        skipToCycleEnd();
        receiveDrips(receiver, 5);
    }

    function testPartOfTheWholeHistoryCanBeSqueezed() public {
        setDrips(sender, 0, 1, recv(receiver, 1));
        (, bytes32 historyHash, , , ) = Drips._dripsState(sender, defaultAsset);
        skip(1);
        setDrips(sender, 0, 2, recv(receiver, 2));
        DripsHistory[] memory history = hist(sender);
        skip(1);
        squeezeDrips(receiver, sender, historyHash, history, 2, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, 1);
    }

    function testDripsWithCopiesOfTheReceiverCanBeSqueezed() public {
        setDrips(sender, 0, 6, recv(recv(receiver, 1), recv(receiver, 2)));
        skip(1);
        squeezeDrips(receiver, sender, hist(sender), 3, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver, 3);
    }

    function testDripsWithManyReceiversCanBeSqueezed() public {
        setDrips(sender, 0, 14, recv(recv(receiver1, 1), recv(receiver2, 2), recv(receiver3, 4)));
        skip(1);
        squeezeDrips(receiver2, sender, hist(sender), 2, block.timestamp);
        skipToCycleEnd();
        receiveDrips(receiver1, 2);
        receiveDrips(receiver2, 2);
        receiveDrips(receiver3, 8);
    }

    function testNextSqueezableDripsIsAtLeastCurrentCycleStart() public {
        skipToCycleEnd();
        uint256 cycleStart = block.timestamp;
        assertNextSqueezedDrips(receiver, defaultAsset, sender, cycleStart);
        skip(cycleSecs - 1);
        assertNextSqueezedDrips(receiver, defaultAsset, sender, cycleStart);
        skip(1);
        assertNextSqueezedDrips(receiver, defaultAsset, sender, block.timestamp);
    }
}
