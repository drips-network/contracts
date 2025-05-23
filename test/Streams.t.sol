// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {console, Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {
    Streams,
    StreamConfig,
    StreamsHistory,
    StreamConfigImpl,
    StreamReceiver
} from "src/Streams.sol";

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

contract StreamsWrapper is Streams {
    uint256 public constant MAX_STREAMS_RECEIVERS = _MAX_STREAMS_RECEIVERS;
    uint8 public constant AMT_PER_SEC_EXTRA_DECIMALS = _AMT_PER_SEC_EXTRA_DECIMALS;
    uint160 public constant AMT_PER_SEC_MULTIPLIER = _AMT_PER_SEC_MULTIPLIER;
    uint128 public constant MAX_STREAMS_BALANCE = _MAX_STREAMS_BALANCE;
    uint32 public immutable cycleSecs;
    uint160 public immutable minAmtPerSec;

    constructor(uint32 cycleSecs_, bytes32 streamsStorageSlot)
        Streams(cycleSecs_, streamsStorageSlot)
    {
        cycleSecs = _cycleSecs;
        minAmtPerSec = _minAmtPerSec;
    }

    function receiveStreams(uint256 accountId, IERC20 erc20, uint32 maxCycles)
        public
        returns (uint128 receivedAmt)
    {
        return _receiveStreams(accountId, erc20, maxCycles);
    }

    function receiveStreamsResult(uint256 accountId, IERC20 erc20, uint32 maxCycles)
        public
        view
        returns (
            uint128 receivedAmt,
            uint32 receivableCycles,
            uint32 fromCycle,
            uint32 toCycle,
            int128 amtPerCycle
        )
    {
        return _receiveStreamsResult(accountId, erc20, maxCycles);
    }

    function receivableStreamsCycles(uint256 accountId, IERC20 erc20)
        public
        view
        returns (uint32 cycles)
    {
        return _receivableStreamsCycles(accountId, erc20);
    }

    function squeezeStreams(
        uint256 accountId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        StreamsHistory[] memory streamsHistory
    ) public returns (uint128 amt) {
        return _squeezeStreams(accountId, erc20, senderId, historyHash, streamsHistory);
    }

    function squeezeStreamsResult(
        uint256 accountId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        StreamsHistory[] memory streamsHistory
    )
        public
        view
        returns (
            uint128 amt,
            uint256 squeezedNum,
            uint256[] memory squeezedRevIdxs,
            bytes32[] memory historyHashes,
            uint256 currCycleConfigs
        )
    {
        return _squeezeStreamsResult(accountId, erc20, senderId, historyHash, streamsHistory);
    }

    function streamsState(uint256 accountId, IERC20 erc20)
        public
        view
        returns (
            bytes32 streamsHash,
            bytes32 streamsHistoryHash,
            uint32 updateTime,
            uint128 balance,
            uint32 maxEnd
        )
    {
        return _streamsState(accountId, erc20);
    }

    function balanceAt(
        uint256 accountId,
        IERC20 erc20,
        StreamReceiver[] memory currReceivers,
        uint32 timestamp
    ) public view returns (uint128 balance) {
        return _balanceAt(accountId, erc20, currReceivers, timestamp);
    }

    function setStreams(
        uint256 accountId,
        IERC20 erc20,
        StreamReceiver[] memory currReceivers,
        int128 balanceDelta,
        StreamReceiver[] memory newReceivers,
        uint32 maxEndHint1,
        uint32 maxEndHint2
    ) public returns (int128 realBalanceDelta) {
        return _setStreams(
            accountId, erc20, currReceivers, balanceDelta, newReceivers, maxEndHint1, maxEndHint2
        );
    }

    function hashStreams(StreamReceiver[] memory receivers)
        public
        pure
        returns (bytes32 streamsHash)
    {
        return _hashStreams(receivers);
    }

    function hashStreamsHistory(
        bytes32 oldStreamsHistoryHash,
        bytes32 streamsHash,
        uint32 updateTime,
        uint32 maxEnd
    ) public pure returns (bytes32 streamsHistoryHash) {
        return _hashStreamsHistory(oldStreamsHistoryHash, streamsHash, updateTime, maxEnd);
    }
}

contract StreamsTest is Test, PseudoRandomUtils {
    bytes internal constant ERROR_NOT_SORTED = "Streams receivers not sorted";
    bytes internal constant ERROR_INVALID_STREAMS_LIST = "Invalid streams receivers list";
    bytes internal constant ERROR_TIMESTAMP_EARLY = "Timestamp before the last update";
    bytes internal constant ERROR_HISTORY_INVALID = "Invalid streams history";
    bytes internal constant ERROR_HISTORY_UNCLEAR = "Entry with hash and receivers";

    StreamsWrapper internal immutable streams;
    uint256 internal constant MAX_STREAMS_RECEIVERS = 100;
    uint32 internal immutable cycleSecs;
    uint160 internal immutable minAmtPerSec;
    uint160 internal immutable amtPerSecMultiplier;

    mapping(IERC20 erc20 => mapping(uint256 accountId => StreamReceiver[])) internal
        currReceiversStore;
    IERC20 internal defaultErc20 = IERC20(address(bytes20("defaultErc20")));
    IERC20 internal otherErc20 = IERC20(address(bytes20("otherErc20")));
    // The ERC-20 token used in all helper functions
    IERC20 internal erc20 = defaultErc20;
    uint256 internal immutable sender = 1;
    uint256 internal immutable sender1 = 2;
    uint256 internal immutable sender2 = 3;
    uint256 internal immutable receiver = 4;
    uint256 internal immutable receiver1 = 5;
    uint256 internal immutable receiver2 = 6;
    uint256 internal immutable receiver3 = 7;
    uint256 internal immutable receiver4 = 8;

    constructor() {
        streams = new StreamsWrapper(10, bytes32(uint256(1000)));
        assertEq(
            MAX_STREAMS_RECEIVERS, streams.MAX_STREAMS_RECEIVERS(), "Invalid MAX_STREAMS_RECEIVERS"
        );
        cycleSecs = streams.cycleSecs();
        minAmtPerSec = streams.minAmtPerSec();
        amtPerSecMultiplier = streams.AMT_PER_SEC_MULTIPLIER();
    }

    function setUp() public {
        skipToCycleEnd();
    }

    function skipToCycleEnd() internal {
        skip(cycleSecs - (vm.getBlockTimestamp() % cycleSecs));
    }

    function skipTo(uint256 timestamp) internal {
        vm.warp(timestamp);
    }

    function loadCurrReceivers(uint256 accountId)
        internal
        view
        returns (StreamReceiver[] memory currReceivers)
    {
        currReceivers = currReceiversStore[erc20][accountId];
        assertStreams(accountId, currReceivers);
    }

    function storeCurrReceivers(uint256 accountId, StreamReceiver[] memory newReceivers) internal {
        assertStreams(accountId, newReceivers);
        delete currReceiversStore[erc20][accountId];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currReceiversStore[erc20][accountId].push(newReceivers[i]);
        }
    }

    function recv() internal pure returns (StreamReceiver[] memory) {
        return new StreamReceiver[](0);
    }

    function recv(uint256 accountId, uint256 amtPerSec)
        internal
        view
        returns (StreamReceiver[] memory receivers)
    {
        return recv(accountId, amtPerSec, 0);
    }

    function recv(uint256 accountId, uint256 amtPerSec, uint256 amtPerSecFrac)
        internal
        view
        returns (StreamReceiver[] memory receivers)
    {
        return recv(accountId, amtPerSec, amtPerSecFrac, 0, 0);
    }

    function recv(uint256 accountId, uint256 amtPerSec, uint256 start, uint256 duration)
        internal
        view
        returns (StreamReceiver[] memory receivers)
    {
        return recv(accountId, amtPerSec, 0, start, duration);
    }

    function recv(
        uint256 accountId,
        uint256 amtPerSec,
        uint256 amtPerSecFrac,
        uint256 start,
        uint256 duration
    ) internal view returns (StreamReceiver[] memory receivers) {
        return recv(accountId, 0, amtPerSec, amtPerSecFrac, start, duration);
    }

    function recv(
        uint256 accountId,
        uint256 streamId,
        uint256 amtPerSec,
        uint256 amtPerSecFrac,
        uint256 start,
        uint256 duration
    ) internal view returns (StreamReceiver[] memory receivers) {
        receivers = new StreamReceiver[](1);
        uint256 amtPerSecFull = amtPerSec * amtPerSecMultiplier + amtPerSecFrac;
        StreamConfig config = StreamConfigImpl.create(
            uint32(streamId), uint160(amtPerSecFull), uint32(start), uint32(duration)
        );
        receivers[0] = StreamReceiver(accountId, config);
    }

    function recv(StreamReceiver[] memory recv1, StreamReceiver[] memory recv2)
        internal
        pure
        returns (StreamReceiver[] memory receivers)
    {
        receivers = new StreamReceiver[](recv1.length + recv2.length);
        for (uint256 i = 0; i < recv1.length; i++) {
            receivers[i] = recv1[i];
        }
        for (uint256 i = 0; i < recv2.length; i++) {
            receivers[recv1.length + i] = recv2[i];
        }
    }

    function recv(
        StreamReceiver[] memory recv1,
        StreamReceiver[] memory recv2,
        StreamReceiver[] memory recv3
    ) internal pure returns (StreamReceiver[] memory) {
        return recv(recv(recv1, recv2), recv3);
    }

    function recv(
        StreamReceiver[] memory recv1,
        StreamReceiver[] memory recv2,
        StreamReceiver[] memory recv3,
        StreamReceiver[] memory recv4
    ) internal pure returns (StreamReceiver[] memory) {
        return recv(recv(recv1, recv2, recv3), recv4);
    }

    function genRandomRecv(
        uint256 amountReceiver,
        uint160 maxAmtPerSec,
        uint32 maxStart,
        uint32 maxDuration
    ) internal returns (StreamReceiver[] memory) {
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
    ) internal returns (StreamReceiver[] memory) {
        StreamReceiver[] memory receivers = new StreamReceiver[](amountReceiver);
        for (uint256 i = 0; i < amountReceiver; i++) {
            uint256 streamId = random(type(uint32).max + uint256(1));
            uint256 amtPerSec = minAmtPerSec + random(maxAmtPerSec - minAmtPerSec);
            uint256 start = random(maxStart);
            if (start % 100 <= probStartNow) {
                start = 0;
            }
            uint256 duration = random(maxDuration);
            if (duration % 100 <= probMaxEnd) {
                duration = 0;
            }
            receivers[i] = recv(i, streamId, 0, amtPerSec, start, duration)[0];
        }
        return receivers;
    }

    function hist() internal pure returns (StreamsHistory[] memory) {
        return new StreamsHistory[](0);
    }

    function hist(StreamReceiver[] memory receivers, uint32 updateTime, uint32 maxEnd)
        internal
        pure
        returns (StreamsHistory[] memory history)
    {
        history = new StreamsHistory[](1);
        history[0] = StreamsHistory(0, receivers, updateTime, maxEnd);
    }

    function histSkip(bytes32 streamsHash, uint32 updateTime, uint32 maxEnd)
        internal
        pure
        returns (StreamsHistory[] memory history)
    {
        history = hist(recv(), updateTime, maxEnd);
        history[0].streamsHash = streamsHash;
    }

    function hist(uint256 accountId) internal view returns (StreamsHistory[] memory history) {
        StreamReceiver[] memory receivers = loadCurrReceivers(accountId);
        (,, uint32 updateTime,, uint32 maxEnd) = streams.streamsState(accountId, erc20);
        return hist(receivers, updateTime, maxEnd);
    }

    function histSkip(uint256 accountId) internal view returns (StreamsHistory[] memory history) {
        (bytes32 streamsHash,, uint32 updateTime,, uint32 maxEnd) =
            streams.streamsState(accountId, erc20);
        return histSkip(streamsHash, updateTime, maxEnd);
    }

    function hist(StreamsHistory[] memory history, uint256 accountId)
        internal
        view
        returns (StreamsHistory[] memory)
    {
        return hist(history, hist(accountId));
    }

    function histSkip(StreamsHistory[] memory history, uint256 accountId)
        internal
        view
        returns (StreamsHistory[] memory)
    {
        return hist(history, histSkip(accountId));
    }

    function hist(StreamsHistory[] memory history1, StreamsHistory[] memory history2)
        internal
        pure
        returns (StreamsHistory[] memory history)
    {
        history = new StreamsHistory[](history1.length + history2.length);
        for (uint256 i = 0; i < history1.length; i++) {
            history[i] = history1[i];
        }
        for (uint256 i = 0; i < history2.length; i++) {
            history[history1.length + i] = history2[i];
        }
    }

    function drainBalance(uint256 accountId, uint128 balanceFrom) internal {
        setStreams(accountId, balanceFrom, 0, loadCurrReceivers(accountId), 0);
    }

    function setStreams(
        uint256 accountId,
        uint128 balanceFrom,
        uint128 balanceTo,
        StreamReceiver[] memory newReceivers,
        uint256 expectedMaxEndFromNow
    ) internal {
        setStreams(accountId, balanceFrom, balanceTo, newReceivers, 0, 0, expectedMaxEndFromNow);
    }

    function setStreams(
        uint256 accountId,
        uint128 balanceFrom,
        uint128 balanceTo,
        StreamReceiver[] memory newReceivers,
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        uint256 expectedMaxEndFromNow
    ) internal {
        (, bytes32 oldHistoryHash,,,) = streams.streamsState(accountId, erc20);
        {
            int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);

            int128 realBalanceDelta = streams.setStreams(
                accountId,
                erc20,
                loadCurrReceivers(accountId),
                balanceDelta,
                newReceivers,
                maxEndHint1,
                maxEndHint2
            );

            assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        }
        storeCurrReceivers(accountId, newReceivers);
        (
            bytes32 streamsHash,
            bytes32 historyHash,
            uint32 updateTime,
            uint128 balance,
            uint32 maxEnd
        ) = streams.streamsState(accountId, erc20);
        assertEq(
            streams.hashStreamsHistory(oldHistoryHash, streamsHash, updateTime, maxEnd),
            historyHash,
            "Invalid history hash"
        );
        assertEq(updateTime, vm.getBlockTimestamp(), "Invalid new last update time");
        assertEq(balanceTo, balance, "Invalid streams balance");
        assertEq(maxEnd, vm.getBlockTimestamp() + expectedMaxEndFromNow, "Invalid max end");
    }

    function maxEndMax() internal view returns (uint32) {
        return type(uint32).max - uint32(vm.getBlockTimestamp());
    }

    function assertStreams(uint256 accountId, StreamReceiver[] memory currReceivers)
        internal
        view
    {
        (bytes32 actual,,,,) = streams.streamsState(accountId, erc20);
        bytes32 expected = streams.hashStreams(currReceivers);
        assertEq(actual, expected, "Invalid streams configuration");
    }

    function assertBalance(uint256 accountId, uint128 expected) internal view {
        assertBalanceAt(accountId, expected, vm.getBlockTimestamp());
    }

    function assertBalanceAt(uint256 accountId, uint128 expected, uint256 timestamp)
        internal
        view
    {
        uint128 balance =
            streams.balanceAt(accountId, erc20, loadCurrReceivers(accountId), uint32(timestamp));
        assertEq(balance, expected, "Invalid streams balance");
    }

    function assertSetStreamsReverts(
        uint256 accountId,
        uint128 balanceFrom,
        uint128 balanceTo,
        StreamReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        assertSetStreamsReverts(
            accountId,
            loadCurrReceivers(accountId),
            balanceFrom,
            balanceTo,
            newReceivers,
            expectedReason
        );
    }

    function assertSetStreamsReverts(
        uint256 accountId,
        StreamReceiver[] memory currReceivers,
        uint128 balanceFrom,
        uint128 balanceTo,
        StreamReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        vm.expectRevert(expectedReason);
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        streams.setStreams(accountId, erc20, currReceivers, balanceDelta, newReceivers, 0, 0);
    }

    function receiveStreams(uint256 accountId, uint128 expectedAmt) internal {
        uint128 actualAmt = streams.receiveStreams(accountId, erc20, type(uint32).max);
        assertEq(actualAmt, expectedAmt, "Invalid amount received from streams");
    }

    function receiveStreams(
        uint256 accountId,
        uint32 maxCycles,
        uint128 expectedReceivedAmt,
        uint32 expectedReceivedCycles,
        uint128 expectedAmtAfter,
        uint32 expectedCyclesAfter
    ) internal {
        uint128 expectedTotalAmt = expectedReceivedAmt + expectedAmtAfter;
        uint32 expectedTotalCycles = expectedReceivedCycles + expectedCyclesAfter;
        assertReceivableStreamsCycles(accountId, expectedTotalCycles);
        assertReceiveStreamsResult(accountId, type(uint32).max, expectedTotalAmt, 0);
        assertReceiveStreamsResult(accountId, maxCycles, expectedReceivedAmt, expectedCyclesAfter);

        uint128 receivedAmt = streams.receiveStreams(accountId, erc20, maxCycles);

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from streams");
        assertReceivableStreamsCycles(accountId, expectedCyclesAfter);
        assertReceiveStreamsResult(accountId, type(uint32).max, expectedAmtAfter, 0);
    }

    function receiveStreams(StreamReceiver[] memory receivers, uint32 maxEnd, uint32 updateTime)
        internal
    {
        console.log("maxEnd:", maxEnd);
        for (uint256 i = 0; i < receivers.length; i++) {
            StreamReceiver memory r = receivers[i];
            uint32 duration = r.config.duration();
            uint32 start = r.config.start();
            if (start == 0) {
                start = updateTime;
            }
            if (duration == 0 && maxEnd > start) {
                duration = maxEnd - start;
            }
            // streams were in the past, not added
            if (start + duration < updateTime) {
                duration = 0;
            } else if (start < updateTime) {
                duration -= updateTime - start;
            }

            uint256 expectedAmt = (duration * r.config.amtPerSec()) >> 64;
            uint128 actualAmt = streams.receiveStreams(r.accountId, erc20, type(uint32).max);
            // only log if actualAmt doesn't match expectedAmt
            if (expectedAmt != actualAmt) {
                console.log("accountId:", r.accountId);
                console.log("start:", r.config.start());
                console.log("duration:", r.config.duration());
                console.log("amtPerSec:", r.config.amtPerSec());
            }
            assertEq(actualAmt, expectedAmt);
        }
    }

    function assertReceivableStreamsCycles(uint256 accountId, uint32 expectedCycles)
        internal
        view
    {
        uint32 actualCycles = streams.receivableStreamsCycles(accountId, erc20);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable streams cycles");
    }

    function assertReceiveStreamsResult(uint256 accountId, uint128 expectedAmt) internal view {
        (uint128 actualAmt,,,,) = streams.receiveStreamsResult(accountId, erc20, type(uint32).max);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
    }

    function assertReceiveStreamsResult(
        uint256 accountId,
        uint32 maxCycles,
        uint128 expectedAmt,
        uint32 expectedCycles
    ) internal view {
        (uint128 actualAmt, uint32 actualCycles,,,) =
            streams.receiveStreamsResult(accountId, erc20, maxCycles);
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
        assertEq(actualCycles, expectedCycles, "Invalid receivable streams cycles");
    }

    function squeezeStreams(
        uint256 accountId,
        uint256 senderId,
        StreamsHistory[] memory streamsHistory,
        uint256 expectedAmt
    ) internal {
        squeezeStreams(accountId, senderId, 0, streamsHistory, expectedAmt);
    }

    function squeezeStreams(
        uint256 accountId,
        uint256 senderId,
        bytes32 historyHash,
        StreamsHistory[] memory streamsHistory,
        uint256 expectedAmt
    ) internal {
        (uint128 amtBefore,,,,) =
            streams.squeezeStreamsResult(accountId, erc20, senderId, historyHash, streamsHistory);
        assertEq(amtBefore, expectedAmt, "Invalid squeezable amount before squeezing");

        uint128 amt =
            streams.squeezeStreams(accountId, erc20, senderId, historyHash, streamsHistory);

        assertEq(amt, expectedAmt, "Invalid squeezed amount");
        (uint128 amtAfter,,,,) =
            streams.squeezeStreamsResult(accountId, erc20, senderId, historyHash, streamsHistory);
        assertEq(amtAfter, 0, "Squeezable amount after squeezing non-zero");
    }

    function assertSqueezeStreamsReverts(
        uint256 accountId,
        uint256 senderId,
        bytes32 historyHash,
        StreamsHistory[] memory streamsHistory,
        bytes memory expectedReason
    ) internal {
        vm.expectRevert(expectedReason);
        streams.squeezeStreams(accountId, erc20, senderId, historyHash, streamsHistory);
        vm.expectRevert(expectedReason);
        streams.squeezeStreamsResult(accountId, erc20, senderId, historyHash, streamsHistory);
    }

    function testStreamsConfigStoresParameters() public pure {
        StreamConfig config = StreamConfigImpl.create(1, 2, 3, 4);
        assertEq(config.streamId(), 1, "Invalid streamId");
        assertEq(config.amtPerSec(), 2, "Invalid amtPerSec");
        assertEq(config.start(), 3, "Invalid start");
        assertEq(config.duration(), 4, "Invalid duration");
    }

    function testStreamsConfigChecksOrdering() public pure {
        StreamConfig config = StreamConfigImpl.create(1, 1, 1, 1);
        assertFalse(config.lt(config), "Configs equal");

        StreamConfig higherstreamId = StreamConfigImpl.create(2, 1, 1, 1);
        assertTrue(config.lt(higherstreamId), "streamId higher");
        assertFalse(higherstreamId.lt(config), "streamId lower");

        StreamConfig higherAmtPerSec = StreamConfigImpl.create(1, 2, 1, 1);
        assertTrue(config.lt(higherAmtPerSec), "AmtPerSec higher");
        assertFalse(higherAmtPerSec.lt(config), "AmtPerSec lower");

        StreamConfig higherStart = StreamConfigImpl.create(1, 1, 2, 1);
        assertTrue(config.lt(higherStart), "Start higher");
        assertFalse(higherStart.lt(config), "Start lower");

        StreamConfig higherDuration = StreamConfigImpl.create(1, 1, 1, 2);
        assertTrue(config.lt(higherDuration), "Duration higher");
        assertFalse(higherDuration.lt(config), "Duration lower");
    }

    function testAllowsStreamingToASingleReceiver() public {
        setStreams(sender, 0, 100, recv(receiver, 1), 100);
        skip(15);
        // Sender had 15 seconds paying 1 per second
        drainBalance(sender, 85);
        skipToCycleEnd();
        // Receiver 1 had 15 seconds paying 1 per second
        receiveStreams(receiver, 15);
    }

    function testStreamsToTwoReceivers() public {
        setStreams(sender, 0, 100, recv(recv(receiver1, 1), recv(receiver2, 1)), 50);
        skip(14);
        // Sender had 14 seconds paying 2 per second
        drainBalance(sender, 72);
        skipToCycleEnd();
        // Receiver 1 had 14 seconds paying 1 per second
        receiveStreams(receiver1, 14);
        // Receiver 2 had 14 seconds paying 1 per second
        receiveStreams(receiver2, 14);
    }

    function testStreamsFromTwoSendersToASingleReceiver() public {
        setStreams(sender1, 0, 100, recv(receiver, 1), 100);
        skip(2);
        setStreams(sender2, 0, 100, recv(receiver, 2), 50);
        skip(15);
        // Sender1 had 17 seconds paying 1 per second
        drainBalance(sender1, 83);
        // Sender2 had 15 seconds paying 2 per second
        drainBalance(sender2, 70);
        skipToCycleEnd();
        // Receiver had 2 seconds paying 1 per second and 15 seconds paying 3 per second
        receiveStreams(receiver, 47);
    }

    function testStreamsWithBalanceLowerThan1SecondOfStreaming() public {
        setStreams(sender, 0, 1, recv(receiver, 2), 0);
        skipToCycleEnd();
        drainBalance(sender, 1);
        receiveStreams(receiver, 0);
    }

    function testStreamsWithStartAndDuration() public {
        setStreams(sender, 0, 10, recv(receiver, 1, vm.getBlockTimestamp() + 5, 10), maxEndMax());
        skip(5);
        assertBalance(sender, 10);
        skip(10);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveStreams(receiver, 10);
    }

    function testStreamsWithStartAndDurationWithInsufficientBalance() public {
        setStreams(sender, 0, 1, recv(receiver, 1, vm.getBlockTimestamp() + 1, 2), 2);
        skip(1);
        assertBalance(sender, 1);
        skip(1);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveStreams(receiver, 1);
    }

    function testStreamsWithOnlyDuration() public {
        setStreams(sender, 0, 10, recv(receiver, 1, 0, 10), maxEndMax());
        skip(10);
        skipToCycleEnd();
        receiveStreams(receiver, 10);
    }

    function testStreamsWithOnlyDurationWithInsufficientBalance() public {
        setStreams(sender, 0, 1, recv(receiver, 1, 0, 2), 1);
        assertBalance(sender, 1);
        skip(1);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveStreams(receiver, 1);
    }

    function testStreamsWithOnlyStart() public {
        setStreams(sender, 0, 10, recv(receiver, 1, vm.getBlockTimestamp() + 5, 0), 15);
        skip(5);
        assertBalance(sender, 10);
        skip(10);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveStreams(receiver, 10);
    }

    function testStreamsWithoutDurationHaveCommonEndTime() public {
        // Enough for 8 seconds of streaming
        setStreams(
            sender,
            0,
            39,
            recv(
                recv(receiver1, 1, vm.getBlockTimestamp() + 5, 0),
                recv(receiver2, 2, 0, 0),
                recv(receiver3, 3, vm.getBlockTimestamp() + 3, 0)
            ),
            8
        );
        skip(8);
        assertBalance(sender, 5);
        skipToCycleEnd();
        receiveStreams(receiver1, 3);
        receiveStreams(receiver2, 16);
        receiveStreams(receiver3, 15);
        drainBalance(sender, 5);
    }

    function testTwoStreamsToSingleReceiver() public {
        setStreams(
            sender,
            0,
            28,
            recv(
                recv(receiver, 1, vm.getBlockTimestamp() + 5, 10),
                recv(receiver, 2, vm.getBlockTimestamp() + 10, 9)
            ),
            maxEndMax()
        );
        skip(19);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveStreams(receiver, 28);
    }

    function testStreamsOfAllSchedulingModes() public {
        setStreams(
            sender,
            0,
            62,
            recv(
                recv(receiver1, 1, 0, 0),
                recv(receiver2, 2, 0, 4),
                recv(receiver3, 3, vm.getBlockTimestamp() + 2, 0),
                recv(receiver4, 4, vm.getBlockTimestamp() + 3, 5)
            ),
            10
        );
        skip(10);
        skipToCycleEnd();
        receiveStreams(receiver1, 10);
        receiveStreams(receiver2, 8);
        receiveStreams(receiver3, 24);
        receiveStreams(receiver4, 20);
    }

    function testStreamsWithStartInThePast() public {
        skip(5);
        setStreams(sender, 0, 3, recv(receiver, 1, vm.getBlockTimestamp() - 5, 0), 3);
        skip(3);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveStreams(receiver, 3);
    }

    function testStreamsWithStartInThePastAndDurationIntoFuture() public {
        skip(5);
        setStreams(sender, 0, 3, recv(receiver, 1, vm.getBlockTimestamp() - 5, 8), maxEndMax());
        skip(3);
        assertBalance(sender, 0);
        skipToCycleEnd();
        receiveStreams(receiver, 3);
    }

    function testStreamsWithStartAndDurationInThePast() public {
        skip(5);
        setStreams(sender, 0, 1, recv(receiver, 1, vm.getBlockTimestamp() - 5, 3), 0);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testStreamsWithStartAfterFundsRunOut() public {
        setStreams(
            sender,
            0,
            4,
            recv(recv(receiver1, 1), recv(receiver2, 2, vm.getBlockTimestamp() + 5, 0)),
            4
        );
        skip(6);
        skipToCycleEnd();
        receiveStreams(receiver1, 4);
        receiveStreams(receiver2, 0);
    }

    function testStreamsWithStartInTheFutureCycleCanBeMovedToAnEarlierOne() public {
        setStreams(
            sender, 0, 1, recv(receiver, 1, vm.getBlockTimestamp() + cycleSecs, 0), cycleSecs + 1
        );
        setStreams(sender, 1, 1, recv(receiver, 1), 1);
        skipToCycleEnd();
        receiveStreams(receiver, 1);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testStreamsWithZeroDurationReceiversNotSortedByStart() public {
        setStreams(
            sender,
            0,
            7,
            recv(
                recv(receiver1, 2, vm.getBlockTimestamp() + 2, 0),
                recv(receiver2, 1, vm.getBlockTimestamp() + 1, 0)
            ),
            4
        );
        skip(4);
        skipToCycleEnd();
        // Has been receiving 2 per second for 2 seconds
        receiveStreams(receiver1, 4);
        // Has been receiving 1 per second for 3 seconds
        receiveStreams(receiver2, 3);
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        receiveStreams(receiver, 0);
    }

    function testDoesNotCollectCyclesBeforeFirstStreaming() public {
        skip(cycleSecs / 2);
        // Streaming starts in 2 cycles
        setStreams(
            sender,
            0,
            1,
            recv(receiver, 1, vm.getBlockTimestamp() + cycleSecs * 2, 0),
            cycleSecs * 2 + 1
        );
        // The first cycle hasn't been streaming
        skipToCycleEnd();
        assertReceivableStreamsCycles(receiver, 0);
        assertReceiveStreamsResult(receiver, 0);
        // The second cycle hasn't been streaming
        skipToCycleEnd();
        assertReceivableStreamsCycles(receiver, 0);
        assertReceiveStreamsResult(receiver, 0);
        // The third cycle has been streaming
        skipToCycleEnd();
        assertReceivableStreamsCycles(receiver, 1);
        receiveStreams(receiver, 1);
    }

    function testFirstCollectableCycleCanBeMovedEarlier() public {
        // Streaming start in the next cycle
        setStreams(
            sender1, 0, 1, recv(receiver, 1, vm.getBlockTimestamp() + cycleSecs, 0), cycleSecs + 1
        );
        // Streaming start in the current cycle
        setStreams(sender2, 0, 2, recv(receiver, 2), 1);
        skipToCycleEnd();
        receiveStreams(receiver, 2);
        skipToCycleEnd();
        receiveStreams(receiver, 1);
    }

    function testAllowsReceivingWhileBeingStreamedTo() public {
        setStreams(sender, 0, cycleSecs + 10, recv(receiver, 1), cycleSecs + 10);
        skipToCycleEnd();
        // Receiver had cycleSecs seconds paying 1 per second
        receiveStreams(receiver, cycleSecs);
        skip(7);
        // Sender had cycleSecs + 7 seconds paying 1 per second
        drainBalance(sender, 3);
        skipToCycleEnd();
        // Receiver had 7 seconds paying 1 per second
        receiveStreams(receiver, 7);
    }

    function testStreamsFundsUntilTheyRunOut() public {
        setStreams(sender, 0, 100, recv(receiver, 9), 11);
        skip(10);
        // Sender had 10 seconds paying 9 per second, streams balance is about to run out
        assertBalance(sender, 10);
        skip(1);
        // Sender had 11 seconds paying 9 per second, streams balance has run out
        assertBalance(sender, 1);
        // Nothing more will be streamed
        skipToCycleEnd();
        drainBalance(sender, 1);
        receiveStreams(receiver, 99);
    }

    function testAllowsStreamsConfigurationWithOverflowingTotalAmtPerSec() public {
        setStreams(sender, 0, 2, recv(recv(receiver, 1), recv(receiver, type(uint128).max)), 0);
        skipToCycleEnd();
        // Sender hasn't sent anything
        drainBalance(sender, 2);
        // Receiver hasn't received anything
        receiveStreams(receiver, 0);
    }

    function testAllowsStreamsConfigurationWithOverflowingAmtPerCycle() public {
        // amtPerSec is valid, but amtPerCycle is over 2 times higher than int128.max.
        // The multiplier is chosen to prevent the amounts from being "clean" binary numbers
        // which could make the overflowing behavior correct by coincidence.
        uint128 amtPerSec = (uint128(type(int128).max) / cycleSecs / 1000) * 2345;
        uint128 amt = amtPerSec * 4;
        setStreams(sender, 0, amt, recv(receiver, amtPerSec), 4);
        skipToCycleEnd();
        receiveStreams(receiver, amt);
    }

    function testAllowsStreamsConfigurationWithOverflowingAmtPerCycleAcrossCycleBoundaries()
        public
    {
        // amtPerSec is valid, but amtPerCycle is over 2 times higher than int128.max.
        // The multiplier is chosen to prevent the amounts from being "clean" binary numbers
        // which could make the overflowing behavior correct by coincidence.
        uint128 amtPerSec = (uint128(type(int128).max) / cycleSecs / 1000) * 2345;
        // Streaming time in the current and future cycle
        uint128 secs = 2;
        uint128 amt = amtPerSec * secs * 2;
        setStreams(
            sender,
            0,
            amt,
            recv(receiver, amtPerSec, vm.getBlockTimestamp() + cycleSecs - secs, 0),
            cycleSecs + 2
        );
        skipToCycleEnd();
        assertReceiveStreamsResult(receiver, amt / 2);
        skipToCycleEnd();
        receiveStreams(receiver, amt);
    }

    function testAllowsStreamsConfigurationWithOverflowingAmtDeltas() public {
        // The amounts in the comments are expressed as parts of `type(int128).max`.
        // AmtPerCycle is 0.812.
        // The multiplier is chosen to prevent the amounts from being "clean" binary numbers
        // which could make the overflowing behavior correct by coincidence.
        uint128 amtPerSec = (uint128(type(int128).max) / cycleSecs / 1000) * 812;
        uint128 amt = amtPerSec * cycleSecs;
        // Set amtDeltas to +0.812 for the current cycle and -0.812 for the next.
        setStreams(sender1, 0, amt, recv(receiver, amtPerSec), cycleSecs);
        // Alter amtDeltas by +0.0812 for the current cycle and -0.0812 for the next one
        // As an intermediate step when the stream start is applied in the middle of the cycle,
        // but the end not yet, apply +0.406 for the current cycle and -0.406 for the next one.
        // It makes amtDeltas reach +1.218 for the current cycle and -1.218 for the next one.
        setStreams(sender2, 0, amtPerSec, recv(receiver, amtPerSec, cycleSecs / 2, 0), 1);
        skipToCycleEnd();
        receiveStreams(receiver, amt + amtPerSec);
    }

    function testAllowsToppingUpWhileStreaming() public {
        StreamReceiver[] memory receivers = recv(receiver, 10);
        setStreams(sender, 0, 100, recv(receiver, 10), 10);
        skip(6);
        // Sender had 6 seconds paying 10 per second
        setStreams(sender, 40, 60, receivers, 6);
        skip(5);
        // Sender had 5 seconds paying 10 per second
        drainBalance(sender, 10);
        skipToCycleEnd();
        // Receiver had 11 seconds paying 10 per second
        receiveStreams(receiver, 110);
    }

    function testAllowsToppingUpAfterFundsRunOut() public {
        StreamReceiver[] memory receivers = recv(receiver, 10);
        setStreams(sender, 0, 100, receivers, 10);
        skip(10);
        // Sender had 10 seconds paying 10 per second
        assertBalance(sender, 0);
        skipToCycleEnd();
        // Receiver had 10 seconds paying 10 per second
        assertReceiveStreamsResult(receiver, 100);
        setStreams(sender, 0, 60, receivers, 6);
        skip(5);
        // Sender had 5 seconds paying 10 per second
        drainBalance(sender, 10);
        skipToCycleEnd();
        // Receiver had 15 seconds paying 10 per second
        receiveStreams(receiver, 150);
    }

    function testAllowsStreamingWhichShouldEndAfterMaxTimestamp() public {
        uint128 balance = type(uint32).max + uint128(6);
        setStreams(sender, 0, balance, recv(receiver, 1), maxEndMax());
        skip(10);
        // Sender had 10 seconds paying 1 per second
        drainBalance(sender, balance - 10);
        skipToCycleEnd();
        // Receiver had 10 seconds paying 1 per second
        receiveStreams(receiver, 10);
    }

    function testAllowsStreamingWithDurationEndingAfterMaxTimestamp() public {
        uint32 maxTimestamp = type(uint32).max;
        uint32 currTimestamp = uint32(vm.getBlockTimestamp());
        uint32 maxDuration = maxTimestamp - currTimestamp;
        uint32 duration = maxDuration + 5;
        setStreams(sender, 0, duration, recv(receiver, 1, 0, duration), maxEndMax());
        skipToCycleEnd();
        receiveStreams(receiver, cycleSecs);
        setStreams(sender, duration - cycleSecs, 0, recv(), 0);
    }

    function testAllowsChangingReceiversWhileStreaming() public {
        setStreams(sender, 0, 100, recv(recv(receiver1, 6), recv(receiver2, 6)), 8);
        skip(3);
        setStreams(sender, 64, 64, recv(recv(receiver1, 4), recv(receiver2, 8)), 5);
        skip(4);
        // Sender had 7 seconds paying 12 per second
        drainBalance(sender, 16);
        skipToCycleEnd();
        // Receiver1 had 3 seconds paying 6 per second and 4 seconds paying 4 per second
        receiveStreams(receiver1, 34);
        // Receiver2 had 3 seconds paying 6 per second and 4 seconds paying 8 per second
        receiveStreams(receiver2, 50);
    }

    function testAllowsRemovingReceiversWhileStreaming() public {
        setStreams(sender, 0, 100, recv(recv(receiver1, 5), recv(receiver2, 5)), 10);
        skip(3);
        setStreams(sender, 70, 70, recv(receiver2, 10), 7);
        skip(4);
        setStreams(sender, 30, 30, recv(), 0);
        skip(10);
        // Sender had 7 seconds paying 10 per second
        drainBalance(sender, 30);
        skipToCycleEnd();
        // Receiver1 had 3 seconds paying 5 per second
        receiveStreams(receiver1, 15);
        // Receiver2 had 3 seconds paying 5 per second and 4 seconds paying 10 per second
        receiveStreams(receiver2, 55);
    }

    function testStreamingFractions() public {
        uint256 onePerCycle = amtPerSecMultiplier / cycleSecs + 1;
        setStreams(sender, 0, 2, recv(receiver, 0, onePerCycle), cycleSecs * 3 - 1);
        skipToCycleEnd();
        receiveStreams(receiver, 1);
        skipToCycleEnd();
        receiveStreams(receiver, 1);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testStreamingFractionsWithFundsEnoughForHalfCycle() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = amtPerSecMultiplier / cycleSecs + 1;
        // Full units are streamed on cycle timestamps 4 and 9
        setStreams(sender, 0, 1, recv(receiver, 0, onePerCycle * 2), 9);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveStreams(receiver, 1);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testStreamingFractionsWithFundsEnoughForOneCycle() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = amtPerSecMultiplier / cycleSecs + 1;
        // Full units are streamed on cycle timestamps 4 and 9
        setStreams(sender, 0, 2, recv(receiver, 0, onePerCycle * 2), 14);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveStreams(receiver, 2);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testStreamingFractionsWithFundsEnoughForTwoCycles() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        uint256 onePerCycle = amtPerSecMultiplier / cycleSecs + 1;
        // Full units are streamed on cycle timestamps 4 and 9
        setStreams(sender, 0, 4, recv(receiver, 0, onePerCycle * 2), 24);
        skipToCycleEnd();
        assertBalance(sender, 2);
        receiveStreams(receiver, 2);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveStreams(receiver, 2);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testFractionsAreClearedOnCycleBoundary() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 per second
        // Full units are streamed on cycle timestamps 3 and 7
        setStreams(sender, 0, 3, recv(receiver, 0, amtPerSecMultiplier / 4 + 1), 17);
        skipToCycleEnd();
        assertBalance(sender, 1);
        receiveStreams(receiver, 2);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveStreams(receiver, 1);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testFractionsAreAppliedOnCycleSecondsWhenTheyAddUpToWholeUnits() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 per second
        // Full units are streamed on cycle timestamps 3 and 7
        setStreams(sender, 0, 3, recv(receiver, 0, amtPerSecMultiplier / 4 + 1), 17);
        assertBalanceAt(sender, 3, vm.getBlockTimestamp() + 3);
        assertBalanceAt(sender, 2, vm.getBlockTimestamp() + 4);
        assertBalanceAt(sender, 2, vm.getBlockTimestamp() + 7);
        assertBalanceAt(sender, 1, vm.getBlockTimestamp() + 8);
        assertBalanceAt(sender, 1, vm.getBlockTimestamp() + 13);
        assertBalanceAt(sender, 0, vm.getBlockTimestamp() + 14);
    }

    function testFractionsAreAppliedRegardlessOfStartTime() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        skip(3);
        // Rate of 0.4 per second
        // Full units are streamed on cycle timestamps 3, 5 and 8
        setStreams(sender, 0, 1, recv(receiver, 0, amtPerSecMultiplier / 10 * 4 + 1), 4);
        assertBalanceAt(sender, 1, vm.getBlockTimestamp() + 1);
        assertBalanceAt(sender, 0, vm.getBlockTimestamp() + 2);
    }

    function testStreamsWithFractionsCanBeSeamlesslyToppedUp() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 per second
        StreamReceiver[] memory receivers = recv(receiver, 0, amtPerSecMultiplier / 4 + 1);
        // Full units are streamed on cycle timestamps 3 and 7
        setStreams(sender, 0, 2, receivers, 13);
        // Top up 2
        setStreams(sender, 2, 4, receivers, 23);
        skipToCycleEnd();
        assertBalance(sender, 2);
        receiveStreams(receiver, 2);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveStreams(receiver, 2);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testFractionsDoNotCumulateOnSender() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 and 0.33 per second
        setStreams(
            sender,
            0,
            5,
            recv(
                recv(receiver1, 0, amtPerSecMultiplier / 4 + 1),
                recv(receiver2, 0, (amtPerSecMultiplier / 100 + 1) * 33)
            ),
            13
        );
        // Full units are streamed by 0.25 on cycle timestamps 3 and 7, 0.33 on 3, 6 and 9
        assertBalance(sender, 5);
        assertBalanceAt(sender, 5, vm.getBlockTimestamp() + 3);
        assertBalanceAt(sender, 3, vm.getBlockTimestamp() + 4);
        assertBalanceAt(sender, 3, vm.getBlockTimestamp() + 6);
        assertBalanceAt(sender, 2, vm.getBlockTimestamp() + 7);
        assertBalanceAt(sender, 1, vm.getBlockTimestamp() + 8);
        assertBalanceAt(sender, 1, vm.getBlockTimestamp() + 9);
        assertBalanceAt(sender, 0, vm.getBlockTimestamp() + 10);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveStreams(receiver1, 2);
        receiveStreams(receiver2, 3);
        skipToCycleEnd();
        assertBalance(sender, 0);
        receiveStreams(receiver1, 0);
        receiveStreams(receiver2, 0);
    }

    function testFractionsDoNotCumulateOnReceiver() public {
        assertEq(cycleSecs, 10, "Unexpected cycle length");
        // Rate of 0.25 per second or 2.5 per cycle
        setStreams(sender1, 0, 3, recv(receiver, 0, amtPerSecMultiplier / 4 + 1), 17);
        // Rate of 0.66 per second or 6.6 per cycle
        setStreams(sender2, 0, 7, recv(receiver, 0, (amtPerSecMultiplier / 100 + 1) * 66), 13);
        skipToCycleEnd();
        assertBalance(sender1, 1);
        assertBalance(sender2, 1);
        receiveStreams(receiver, 8);
        skipToCycleEnd();
        assertBalance(sender1, 0);
        assertBalance(sender2, 0);
        receiveStreams(receiver, 2);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testLimitsTheTotalReceiversCount() public {
        uint256 countMax = streams.MAX_STREAMS_RECEIVERS();
        StreamReceiver[] memory receivers = new StreamReceiver[](countMax);
        for (uint160 i = 0; i < countMax; i++) {
            receivers[i] = recv(i, 1, 0, 0)[0];
        }
        setStreams(sender, 0, uint128(countMax), receivers, 1);
        receivers = recv(receivers, recv(countMax, 1, 0, 0));
        assertSetStreamsReverts(
            sender,
            uint128(countMax),
            uint128(countMax + 1),
            receivers,
            "Too many streams receivers"
        );
    }

    function testBenchSetStreams() public {
        uint32 wrongHint1 = uint32(vm.getBlockTimestamp()) + 1;
        uint32 wrongHint2 = wrongHint1 + 1;

        uint32 worstEnd = type(uint32).max - 2;
        uint32 worstHint = worstEnd + 1;
        uint32 worstHintPerfect = worstEnd;
        uint32 worstHint1Minute = worstEnd - 1 minutes;
        uint32 worstHint1Hour = worstEnd - 1 hours;

        benchSetStreams("worst 100 no hint        ", 100, worstEnd, 0, 0);
        benchSetStreams("worst 100 perfect hint   ", 100, worstEnd, worstHint, worstHintPerfect);
        benchSetStreams("worst 100 1 minute hint  ", 100, worstEnd, worstHint, worstHint1Minute);
        benchSetStreams("worst 100 1 hour hint    ", 100, worstEnd, worstHint, worstHint1Hour);
        benchSetStreams("worst 100 wrong hint     ", 100, worstEnd, wrongHint1, wrongHint2);
        console.log("-----------------------------------------------");

        benchSetStreams("worst 10 no hint         ", 10, worstEnd, 0, 0);
        benchSetStreams("worst 10 perfect hint    ", 10, worstEnd, worstHint, worstHintPerfect);
        benchSetStreams("worst 10 1 minute hint   ", 10, worstEnd, worstHint, worstHint1Minute);
        benchSetStreams("worst 10 1 hour hint     ", 10, worstEnd, worstHint, worstHint1Hour);
        benchSetStreams("worst 10 wrong hint      ", 10, worstEnd, wrongHint1, wrongHint2);
        console.log("-----------------------------------------------");

        benchSetStreams("worst 1 no hint          ", 1, worstEnd, 0, 0);
        benchSetStreams("worst 1 perfect hint     ", 1, worstEnd, worstHint, worstHintPerfect);
        benchSetStreams("worst 1 1 minute hint    ", 1, worstEnd, worstHint, worstHint1Minute);
        benchSetStreams("worst 1 1 hour hint      ", 1, worstEnd, worstHint, worstHint1Hour);
        benchSetStreams("worst 1 wrong hint       ", 1, worstEnd, wrongHint1, wrongHint2);
        console.log("-----------------------------------------------");

        uint32 monthEnd = uint32(vm.getBlockTimestamp()) + 30 days;
        uint32 monthHint = monthEnd + 1;
        uint32 monthHintPerfect = monthEnd;
        uint32 monthHint1Minute = monthEnd - 1 minutes;
        uint32 monthHint1Hour = monthEnd - 1 hours;

        benchSetStreams("1 month 100 no hint      ", 100, monthEnd, 0, 0);
        benchSetStreams("1 month 100 perfect hint ", 100, monthEnd, monthHint, monthHintPerfect);
        benchSetStreams("1 month 100 1 minute hint", 100, monthEnd, monthHint, monthHint1Minute);
        benchSetStreams("1 month 100 1 hour hint  ", 100, monthEnd, monthHint, monthHint1Hour);
        benchSetStreams("1 month 100 wrong hint   ", 100, monthEnd, wrongHint1, wrongHint2);
        console.log("-----------------------------------------------");

        benchSetStreams("1 month 10 no hint       ", 10, monthEnd, 0, 0);
        benchSetStreams("1 month 10 perfect hint  ", 10, monthEnd, monthHint, monthHintPerfect);
        benchSetStreams("1 month 10 1 minute hint ", 10, monthEnd, monthHint, monthHint1Minute);
        benchSetStreams("1 month 10 1 hour hint   ", 10, monthEnd, monthHint, monthHint1Hour);
        benchSetStreams("1 month 10 wrong hint    ", 10, monthEnd, wrongHint1, wrongHint2);
        console.log("-----------------------------------------------");

        benchSetStreams("1 month 1 no hint        ", 1, monthEnd, 0, 0);
        benchSetStreams("1 month 1 perfect hint   ", 1, monthEnd, monthHint, monthHintPerfect);
        benchSetStreams("1 month 1 1 minute hint  ", 1, monthEnd, monthHint, monthHint1Minute);
        benchSetStreams("1 month 1 1 hour hint    ", 1, monthEnd, monthHint, monthHint1Hour);
        benchSetStreams("1 month 1 wrong hint     ", 1, monthEnd, wrongHint1, wrongHint2);
    }

    function benchSetStreams(
        string memory testName,
        uint256 count,
        uint256 maxEnd,
        uint32 maxEndHint1,
        uint32 maxEndHint2
    ) public {
        uint256 senderId = gasleft();
        StreamReceiver[] memory receivers = new StreamReceiver[](count);
        for (uint256 i = 0; i < count; i++) {
            receivers[i] = recv(senderId + 1 + i, 1, 0, 0)[0];
        }
        int128 amt = int128(int256((maxEnd - vm.getBlockTimestamp()) * count));
        uint256 gas = gasleft();
        streams.setStreams(senderId, erc20, recv(), amt, receivers, maxEndHint1, maxEndHint2);
        gas -= gasleft();
        console.log("Gas used for", testName, gas);
    }

    function testMinAmtPerSec() public {
        assertMinAmtPerSec(2, 500_000_000);
        assertMinAmtPerSec(3, 333_333_334);
        assertMinAmtPerSec(10, 100_000_000);
        assertMinAmtPerSec(11, 90_909_091);
        assertMinAmtPerSec(999_999_999, 2);
        assertMinAmtPerSec(1_000_000_000, 1);
        assertMinAmtPerSec(1_000_000_001, 1);
        assertMinAmtPerSec(2_000_000_000, 1);
    }

    function assertMinAmtPerSec(uint32 cycleSecs_, uint160 expectedMinAmtPerSec) internal {
        StreamsWrapper streams_ = new StreamsWrapper(cycleSecs_, 0);
        string memory assertMessage =
            string.concat("Invalid minAmtPerSec for cycleSecs ", vm.toString(cycleSecs_));
        assertEq(streams_.minAmtPerSec(), expectedMinAmtPerSec, assertMessage);
    }

    function testRejectsTooLowAmtPerSecReceivers() public {
        assertSetStreamsReverts(
            sender, 0, 0, recv(receiver, 0, minAmtPerSec - 1), "Stream receiver amtPerSec too low"
        );
    }

    function testAcceptMinAmtPerSecReceivers() public {
        setStreams(sender, 0, 2, recv(receiver, 0, minAmtPerSec), 3 * cycleSecs - 1);
        skipToCycleEnd();
        drainBalance(sender, 1);
        receiveStreams(receiver, 1);
    }

    function testStreamsNotSortedByReceiverAreRejected() public {
        assertSetStreamsReverts(
            sender, 0, 0, recv(recv(receiver2, 1), recv(receiver1, 1)), ERROR_NOT_SORTED
        );
    }

    function testStreamsNotSortedBystreamIdAreRejected() public {
        assertSetStreamsReverts(
            sender,
            0,
            0,
            recv(recv(receiver, 1, 1, 0, 0, 0), recv(receiver, 0, 1, 0, 0, 0)),
            ERROR_NOT_SORTED
        );
    }

    function testStreamsNotSortedByAmtPerSecAreRejected() public {
        assertSetStreamsReverts(
            sender, 0, 0, recv(recv(receiver, 2), recv(receiver, 1)), ERROR_NOT_SORTED
        );
    }

    function testStreamsNotSortedByStartAreRejected() public {
        assertSetStreamsReverts(
            sender, 0, 0, recv(recv(receiver, 1, 2, 0), recv(receiver, 1, 1, 0)), ERROR_NOT_SORTED
        );
    }

    function testStreamsNotSortedByDurationAreRejected() public {
        assertSetStreamsReverts(
            sender, 0, 0, recv(recv(receiver, 1, 1, 2), recv(receiver, 1, 1, 1)), ERROR_NOT_SORTED
        );
    }

    function testRejectsDuplicateReceivers() public {
        assertSetStreamsReverts(
            sender, 0, 0, recv(recv(receiver, 1), recv(receiver, 1)), ERROR_NOT_SORTED
        );
    }

    function testSetStreamsRevertsIfInvalidCurrReceivers() public {
        setStreams(sender, 0, 1, recv(receiver, 1), 1);
        assertSetStreamsReverts(sender, recv(receiver, 2), 0, 0, recv(), ERROR_INVALID_STREAMS_LIST);
    }

    function testAllowsAnAddressToStreamAndReceiveIndependently() public {
        setStreams(sender, 0, 10, recv(sender, 10), 1);
        skip(1);
        // Sender had 1 second paying 10 per second
        assertBalance(sender, 0);
        skipToCycleEnd();
        // Sender had 1 second paying 10 per second
        receiveStreams(sender, 10);
    }

    function testCapsWithdrawalOfMoreThanStreamsBalance() public {
        StreamReceiver[] memory receivers = recv(receiver, 1);
        setStreams(sender, 0, 10, receivers, 10);
        skip(4);
        // Sender had 4 second paying 1 per second

        StreamReceiver[] memory newReceivers = recv();
        int128 realBalanceDelta =
            streams.setStreams(sender, erc20, receivers, type(int128).min, newReceivers, 0, 0);
        storeCurrReceivers(sender, newReceivers);
        assertBalance(sender, 0);
        assertEq(realBalanceDelta, -6, "Invalid real balance delta");
        assertBalance(sender, 0);
        skipToCycleEnd();
        // Receiver had 4 seconds paying 1 per second
        receiveStreams(receiver, 4);
    }

    function testReceiveNotAllStreamsCycles() public {
        // Enough for 3 cycles
        uint128 amt = cycleSecs * 3;
        skipToCycleEnd();
        setStreams(sender, 0, amt, recv(receiver, 1), cycleSecs * 3);
        skipToCycleEnd();
        skipToCycleEnd();
        skipToCycleEnd();
        receiveStreams({
            accountId: receiver,
            maxCycles: 2,
            expectedReceivedAmt: cycleSecs * 2,
            expectedReceivedCycles: 2,
            expectedAmtAfter: cycleSecs,
            expectedCyclesAfter: 1
        });
        receiveStreams(receiver, cycleSecs);
    }

    function testSenderCanStreamToThemselves() public {
        uint128 amt = cycleSecs * 3;
        skipToCycleEnd();
        setStreams(sender, 0, amt, recv(recv(sender, 1), recv(receiver, 2)), cycleSecs);
        skipToCycleEnd();
        receiveStreams(sender, cycleSecs);
        receiveStreams(receiver, cycleSecs * 2);
    }

    function testUpdateDefaultStartStreams() public {
        setStreams(sender, 0, 3 * cycleSecs, recv(receiver, 1), 3 * cycleSecs);
        skipToCycleEnd();
        skipToCycleEnd();
        // remove streams after two cycles, no balance change
        setStreams(sender, 10, 10, recv(), 0);

        skipToCycleEnd();
        // only two cycles should be streaming
        receiveStreams(receiver, 2 * cycleSecs);
    }

    function testStreamsOfDifferentErc20TokensAreIndependent() public {
        // Covers 1.5 cycles of streaming
        erc20 = defaultErc20;
        setStreams(
            sender,
            0,
            9 * cycleSecs,
            recv(recv(receiver1, 4), recv(receiver2, 2)),
            cycleSecs + cycleSecs / 2
        );

        skipToCycleEnd();
        // Covers 2 cycles of streaming
        erc20 = otherErc20;
        setStreams(sender, 0, 6 * cycleSecs, recv(receiver1, 3), cycleSecs * 2);

        skipToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        erc20 = defaultErc20;
        receiveStreams(receiver1, 6 * cycleSecs);
        // receiver1 had 1.5 cycles of 2 per second
        erc20 = defaultErc20;
        receiveStreams(receiver2, 3 * cycleSecs);
        // receiver1 had 1 cycle of 3 per second
        erc20 = otherErc20;
        receiveStreams(receiver1, 3 * cycleSecs);
        // receiver2 received nothing
        erc20 = otherErc20;
        receiveStreams(receiver2, 0);

        skipToCycleEnd();
        // receiver1 received nothing
        erc20 = defaultErc20;
        receiveStreams(receiver1, 0);
        // receiver2 received nothing
        erc20 = defaultErc20;
        receiveStreams(receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        erc20 = otherErc20;
        receiveStreams(receiver1, 3 * cycleSecs);
        // receiver2 received nothing
        erc20 = otherErc20;
        receiveStreams(receiver2, 0);
    }

    function testBalanceAtReturnsCurrentBalance() public {
        setStreams(sender, 0, 10, recv(receiver, 1), 10);
        skip(2);
        assertBalanceAt(sender, 8, vm.getBlockTimestamp());
    }

    function testBalanceAtReturnsFutureBalance() public {
        setStreams(sender, 0, 10, recv(receiver, 1), 10);
        skip(2);
        assertBalanceAt(sender, 6, vm.getBlockTimestamp() + 2);
    }

    function testBalanceAtReturnsPastBalanceAfterSetDelta() public {
        setStreams(sender, 0, 10, recv(receiver, 1), 10);
        skip(2);
        assertBalanceAt(sender, 10, vm.getBlockTimestamp() - 2);
    }

    function testBalanceAtRevertsForTimestampBeforeSetDelta() public {
        StreamReceiver[] memory receivers = recv(receiver, 1);
        setStreams(sender, 0, 10, receivers, 10);
        skip(2);
        vm.expectRevert(ERROR_TIMESTAMP_EARLY);
        streams.balanceAt(sender, erc20, receivers, uint32(vm.getBlockTimestamp()) - 3);
    }

    function testBalanceAtRevertsForInvalidStreamsList() public {
        StreamReceiver[] memory receivers = recv(receiver, 1);
        setStreams(sender, 0, 10, receivers, 10);
        skip(2);
        receivers = recv(receiver, 2);
        vm.expectRevert(ERROR_INVALID_STREAMS_LIST);
        streams.balanceAt(sender, erc20, receivers, uint32(vm.getBlockTimestamp()));
    }

    function testFuzzStreamReceivers(bytes32 seed) public {
        initSeed(seed);
        uint8 amountReceivers = 10;
        uint160 maxAmtPerSec = minAmtPerSec + 50;
        uint32 maxDuration = 100;
        uint32 maxStart = 100;

        uint128 maxCosts =
            amountReceivers * uint128(maxAmtPerSec / amtPerSecMultiplier) * maxDuration;
        console.log("topUp", maxCosts);
        uint128 maxAllStreamsFinished = maxStart + maxDuration;

        StreamReceiver[] memory receivers =
            genRandomRecv(amountReceivers, maxAmtPerSec, maxStart, maxDuration);
        console.log("setStreams.updateTime", vm.getBlockTimestamp());
        streams.setStreams(sender, erc20, recv(), int128(maxCosts), receivers, 0, 0);

        (,, uint32 updateTime,, uint32 maxEnd) = streams.streamsState(sender, erc20);

        if (maxEnd > maxAllStreamsFinished && maxEnd != type(uint32).max) {
            maxAllStreamsFinished = maxEnd;
        }

        skip(maxAllStreamsFinished);
        skipToCycleEnd();
        console.log("receiveStreams.time", vm.getBlockTimestamp());
        receiveStreams(receivers, maxEnd, updateTime);
    }

    function sanitizeReceivers(
        StreamReceiver[MAX_STREAMS_RECEIVERS] memory receiversRaw,
        uint256 receiversLengthRaw
    ) internal view returns (StreamReceiver[] memory receivers) {
        receivers = new StreamReceiver[](bound(receiversLengthRaw, 0, receiversRaw.length));
        for (uint256 i = 0; i < receivers.length; i++) {
            receivers[i] = receiversRaw[i];
        }
        for (uint32 i = 0; i < receivers.length; i++) {
            for (uint256 j = i + 1; j < receivers.length; j++) {
                if (receivers[j].accountId < receivers[i].accountId) {
                    (receivers[j], receivers[i]) = (receivers[i], receivers[j]);
                }
            }
            StreamConfig cfg = receivers[i].config;
            uint160 amtPerSec = cfg.amtPerSec();
            if (amtPerSec < minAmtPerSec) amtPerSec = minAmtPerSec;
            receivers[i].config = StreamConfigImpl.create(i, amtPerSec, cfg.start(), cfg.duration());
        }
    }

    struct Sender {
        uint256 accountId;
        uint128 balance;
        StreamReceiver[] receivers;
    }

    function sanitizeSenders(
        uint256 receiverId,
        uint128 balance,
        StreamReceiver[100] memory sendersRaw,
        uint256 sendersLenRaw
    ) internal view returns (Sender[] memory senders) {
        uint256 sendersLen = bound(sendersLenRaw, 1, sendersRaw.length);
        senders = new Sender[](sendersLen);
        uint256 totalBalanceWeight = 0;
        for (uint32 i = 0; i < sendersLen; i++) {
            StreamConfig cfg = sendersRaw[i].config;
            senders[i].accountId = sendersRaw[i].accountId;
            senders[i].balance = cfg.streamId();
            totalBalanceWeight += cfg.streamId();
            senders[i].receivers = new StreamReceiver[](1);
            senders[i].receivers[0].accountId = receiverId;
            uint160 amtPerSec = cfg.amtPerSec();
            if (amtPerSec < minAmtPerSec) amtPerSec = minAmtPerSec;
            senders[i].receivers[0].config =
                StreamConfigImpl.create(i, amtPerSec, cfg.start(), cfg.duration());
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
                if (senders[i].accountId == senders[j].accountId) {
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

    function sanitizeStreamingTime(uint256 streamingTimeRaw, uint256 maxCycles)
        internal
        view
        returns (uint256 streamingTime)
    {
        return bound(streamingTimeRaw, 0, cycleSecs * maxCycles);
    }

    function sanitizeStreamsBalance(uint256 balanceRaw) internal view returns (uint128 balance) {
        return uint128(bound(balanceRaw, 0, streams.MAX_STREAMS_BALANCE()));
    }

    function testFundsStreamedToReceiversAddUp(
        uint256 senderId,
        IERC20 usedErc20,
        uint256 balanceRaw,
        StreamReceiver[MAX_STREAMS_RECEIVERS] memory receiversRaw,
        uint256 receiversLengthRaw,
        uint256 streamingTimeRaw
    ) public {
        uint128 balanceBefore = sanitizeStreamsBalance(balanceRaw);
        StreamReceiver[] memory receivers = sanitizeReceivers(receiversRaw, receiversLengthRaw);
        streams.setStreams(senderId, usedErc20, recv(), int128(balanceBefore), receivers, 0, 0);

        skip(sanitizeStreamingTime(streamingTimeRaw, 100));
        int128 realBalanceDelta =
            streams.setStreams(senderId, usedErc20, receivers, type(int128).min, receivers, 0, 0);

        skipToCycleEnd();
        uint256 balanceAfter = uint128(-realBalanceDelta);
        for (uint256 i = 0; i < receivers.length; i++) {
            balanceAfter +=
                streams.receiveStreams(receivers[i].accountId, usedErc20, type(uint32).max);
        }
        assertEq(balanceAfter, balanceBefore, "Streamed funds don't add up");
    }

    function testFundsStreamedToReceiversAddUpAfterStreamsUpdate(
        uint256 senderId,
        uint256 balanceRaw,
        IERC20 usedErc20,
        StreamReceiver[MAX_STREAMS_RECEIVERS] memory receiversRaw1,
        uint256 receiversLengthRaw1,
        uint256 streamingTimeRaw1,
        StreamReceiver[MAX_STREAMS_RECEIVERS] memory receiversRaw2,
        uint256 receiversLengthRaw2,
        uint256 streamingTimeRaw2
    ) public {
        uint128 balanceBefore = sanitizeStreamsBalance(balanceRaw);
        StreamReceiver[] memory receivers1 = sanitizeReceivers(receiversRaw1, receiversLengthRaw1);
        streams.setStreams(senderId, usedErc20, recv(), int128(balanceBefore), receivers1, 0, 0);

        skip(sanitizeStreamingTime(streamingTimeRaw1, 50));
        StreamReceiver[] memory receivers2 = sanitizeReceivers(receiversRaw2, receiversLengthRaw2);
        int128 realBalanceDelta =
            streams.setStreams(senderId, usedErc20, receivers1, 0, receivers2, 0, 0);
        assertEq(realBalanceDelta, 0, "Zero balance delta changed balance");

        skip(sanitizeStreamingTime(streamingTimeRaw2, 50));
        realBalanceDelta =
            streams.setStreams(senderId, usedErc20, receivers2, type(int128).min, receivers2, 0, 0);

        skipToCycleEnd();
        uint256 balanceAfter = uint128(-realBalanceDelta);
        for (uint256 i = 0; i < receivers1.length; i++) {
            balanceAfter +=
                streams.receiveStreams(receivers1[i].accountId, usedErc20, type(uint32).max);
        }
        for (uint256 i = 0; i < receivers2.length; i++) {
            balanceAfter +=
                streams.receiveStreams(receivers2[i].accountId, usedErc20, type(uint32).max);
        }
        assertEq(balanceAfter, balanceBefore, "Streamed funds don't add up");
    }

    function testFundsStreamedFromSendersAddUp(
        uint256 receiverId,
        IERC20 usedErc20,
        uint256 balanceRaw,
        StreamReceiver[100] memory sendersRaw,
        uint256 sendersLenRaw,
        uint256 streamingTimeRaw
    ) public {
        uint128 balanceBefore = sanitizeStreamsBalance(balanceRaw);
        Sender[] memory senders =
            sanitizeSenders(receiverId, balanceBefore, sendersRaw, sendersLenRaw);
        for (uint256 i = 0; i < senders.length; i++) {
            Sender memory snd = senders[i];
            streams.setStreams(
                snd.accountId, usedErc20, recv(), int128(snd.balance), snd.receivers, 0, 0
            );
        }

        skip(sanitizeStreamingTime(streamingTimeRaw, 1000));
        uint128 balanceAfter = 0;
        for (uint256 i = 0; i < senders.length; i++) {
            Sender memory snd = senders[i];
            int128 realBalanceDelta = streams.setStreams(
                snd.accountId, usedErc20, snd.receivers, type(int128).min, snd.receivers, 0, 0
            );
            balanceAfter += uint128(-realBalanceDelta);
        }

        skipToCycleEnd();
        balanceAfter += streams.receiveStreams(receiverId, usedErc20, type(uint32).max);
        assertEq(balanceAfter, balanceBefore, "Streamed funds don't add up");
    }

    function testMaxEndHintsDoNotAffectMaxEnd() public {
        skipTo(10);
        setStreamsPermuteHints({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndHint1: 15,
            maxEndHint2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndHintsPerfectlyAccurateDoNotAffectMaxEnd() public {
        skipTo(10);
        setStreamsPermuteHints({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndHint1: 20,
            maxEndHint2: 21,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndHintsInThePastDoNotAffectMaxEnd() public {
        skipTo(10);
        setStreamsPermuteHints({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndHint1: 5,
            maxEndHint2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function testMaxEndHintsAtTheEndOfTimeDoNotAffectMaxEnd() public {
        skipTo(10);
        setStreamsPermuteHints({
            amt: 10,
            receivers: recv(receiver, 1),
            maxEndHint1: type(uint32).max,
            maxEndHint2: 25,
            expectedMaxEndFromNow: 10
        });
    }

    function setStreamsPermuteHints(
        uint128 amt,
        StreamReceiver[] memory receivers,
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        uint256 expectedMaxEndFromNow
    ) internal {
        setStreamsPermuteHintsCase(amt, receivers, 0, 0, expectedMaxEndFromNow);
        setStreamsPermuteHintsCase(amt, receivers, 0, maxEndHint1, expectedMaxEndFromNow);
        setStreamsPermuteHintsCase(amt, receivers, 0, maxEndHint2, expectedMaxEndFromNow);
        setStreamsPermuteHintsCase(amt, receivers, maxEndHint1, 0, expectedMaxEndFromNow);
        setStreamsPermuteHintsCase(amt, receivers, maxEndHint2, 0, expectedMaxEndFromNow);
        setStreamsPermuteHintsCase(amt, receivers, maxEndHint1, maxEndHint2, expectedMaxEndFromNow);
        setStreamsPermuteHintsCase(amt, receivers, maxEndHint2, maxEndHint1, expectedMaxEndFromNow);
        setStreamsPermuteHintsCase(amt, receivers, maxEndHint1, maxEndHint1, expectedMaxEndFromNow);
        setStreamsPermuteHintsCase(amt, receivers, maxEndHint2, maxEndHint2, expectedMaxEndFromNow);
    }

    function setStreamsPermuteHintsCase(
        uint128 amt,
        StreamReceiver[] memory receivers,
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        uint256 expectedMaxEndFromNow
    ) internal {
        console.log("Setting streams with hint 1", maxEndHint1);
        console.log("                 and hint 2", maxEndHint2);
        uint256 snapshot = vm.snapshotState();
        setStreams(sender, 0, amt, receivers, maxEndHint1, maxEndHint2, expectedMaxEndFromNow);
        vm.revertToState(snapshot);
    }

    function testSqueezeStreams() public {
        uint128 amt = cycleSecs;
        setStreams(sender, 0, amt, recv(receiver, 1), cycleSecs);
        skip(2);
        squeezeStreams(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveStreams(receiver, amt - 2);
    }

    function testSqueezeStreamsRevertsWhenInvalidHistory() public {
        uint128 amt = cycleSecs;
        setStreams(sender, 0, amt, recv(receiver, 1), cycleSecs);
        StreamsHistory[] memory history = hist(sender);
        history[0].maxEnd += 1;
        skip(2);
        assertSqueezeStreamsReverts(receiver, sender, 0, history, ERROR_HISTORY_INVALID);
    }

    function testSqueezeStreamsRevertsWhenHistoryEntryContainsReceiversAndHash() public {
        uint128 amt = cycleSecs;
        setStreams(sender, 0, amt, recv(receiver, 1), cycleSecs);
        StreamsHistory[] memory history = hist(sender);
        history[0].streamsHash = streams.hashStreams(history[0].receivers);
        skip(2);
        assertSqueezeStreamsReverts(receiver, sender, 0, history, ERROR_HISTORY_UNCLEAR);
    }

    function testFundsAreNotSqueezeTwice() public {
        uint128 amt = cycleSecs;
        setStreams(sender, 0, amt, recv(receiver, 1), cycleSecs);
        StreamsHistory[] memory history = hist(sender);
        skip(1);
        squeezeStreams(receiver, sender, history, 1);
        skip(2);
        squeezeStreams(receiver, sender, history, 2);
        skipToCycleEnd();
        receiveStreams(receiver, amt - 3);
    }

    function testFundsFromOldHistoryEntriesAreNotSqueezedTwice() public {
        setStreams(sender, 0, 9, recv(receiver, 1), 9);
        StreamsHistory[] memory history = hist(sender);
        skip(1);
        setStreams(sender, 8, 8, recv(receiver, 2), 4);
        history = hist(history, sender);
        skip(1);
        squeezeStreams(receiver, sender, history, 3);
        skip(1);
        squeezeStreams(receiver, sender, history, 2);
        skipToCycleEnd();
        receiveStreams(receiver, 4);
    }

    function testFundsFromFinishedCyclesAreNotSqueezed() public {
        uint128 amt = cycleSecs * 2;
        setStreams(sender, 0, amt, recv(receiver, 1), cycleSecs * 2);
        skipToCycleEnd();
        skip(2);
        squeezeStreams(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveStreams(receiver, amt - 2);
    }

    function testHistoryFromFinishedCyclesIsNotSqueezed() public {
        setStreams(sender, 0, 2, recv(receiver, 1), 2);
        StreamsHistory[] memory history = hist(sender);
        skipToCycleEnd();
        setStreams(sender, 0, 6, recv(receiver, 3), 2);
        history = hist(history, sender);
        skip(1);
        squeezeStreams(receiver, sender, history, 3);
        skipToCycleEnd();
        receiveStreams(receiver, 5);
    }

    function testFundsFromBeforeStreamingStartedAreNotSqueezed() public {
        skip(1);
        setStreams(sender, 0, 10, recv(receiver, 1, vm.getBlockTimestamp() - 1, 0), 10);
        squeezeStreams(receiver, sender, hist(sender), 0);
        skip(2);
        drainBalance(sender, 8);
        skipToCycleEnd();
        receiveStreams(receiver, 2);
    }

    function testFundsFromAfterStreamsEndAreNotSqueezed() public {
        setStreams(sender, 0, 10, recv(receiver, 1, 0, 2), maxEndMax());
        skip(3);
        squeezeStreams(receiver, sender, hist(sender), 2);
        drainBalance(sender, 8);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testFundsFromAfterStreamsRunOutAreNotSqueezed() public {
        uint128 amt = 2;
        setStreams(sender, 0, amt, recv(receiver, 1), 2);
        skip(3);
        squeezeStreams(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testOnFirstSecondOfCycleNoFundsCanBeSqueezed() public {
        uint128 amt = cycleSecs * 2;
        setStreams(sender, 0, amt, recv(receiver, 1), cycleSecs * 2);
        skipToCycleEnd();
        squeezeStreams(receiver, sender, hist(sender), 0);
        skipToCycleEnd();
        receiveStreams(receiver, amt);
    }

    function testStreamsWithStartAndDurationCanBeSqueezed() public {
        setStreams(sender, 0, 10, recv(receiver, 1, vm.getBlockTimestamp() + 2, 2), maxEndMax());
        skip(5);
        squeezeStreams(receiver, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveStreams(receiver, 0);
    }

    function testEmptyHistoryCanBeSqueezed() public {
        skip(1);
        squeezeStreams(receiver, sender, hist(), 0);
    }

    function testHistoryWithoutTheSqueezingReceiverCanBeSqueezed() public {
        setStreams(sender, 0, 1, recv(receiver1, 1), 1);
        StreamsHistory[] memory history = hist(sender);
        skip(1);
        squeezeStreams(receiver2, sender, history, 0);
        skipToCycleEnd();
        receiveStreams(receiver1, 1);
    }

    function testSendersCanBeSqueezedIndependently() public {
        setStreams(sender1, 0, 4, recv(receiver, 2), 2);
        StreamsHistory[] memory history1 = hist(sender1);
        setStreams(sender2, 0, 6, recv(receiver, 3), 2);
        StreamsHistory[] memory history2 = hist(sender2);
        skip(1);
        squeezeStreams(receiver, sender1, history1, 2);
        skip(1);
        squeezeStreams(receiver, sender2, history2, 6);
        skipToCycleEnd();
        receiveStreams(receiver, 2);
    }

    function testMultipleHistoryEntriesCanBeSqueezed() public {
        setStreams(sender, 0, 5, recv(receiver, 1), 5);
        StreamsHistory[] memory history = hist(sender);
        skip(1);
        setStreams(sender, 4, 4, recv(receiver, 2), 2);
        history = hist(history, sender);
        skip(1);
        squeezeStreams(receiver, sender, history, 3);
        skipToCycleEnd();
        receiveStreams(receiver, 2);
    }

    function testMiddleHistoryEntryCanBeSkippedWhenSqueezing() public {
        StreamsHistory[] memory history = hist();
        setStreams(sender, 0, 1, recv(receiver, 1), 1);
        history = hist(history, sender);
        skip(1);
        setStreams(sender, 0, 2, recv(receiver, 2), 1);
        history = histSkip(history, sender);
        skip(1);
        setStreams(sender, 0, 4, recv(receiver, 4), 1);
        history = hist(history, sender);
        skip(1);
        squeezeStreams(receiver, sender, history, 5);
        skipToCycleEnd();
        receiveStreams(receiver, 2);
    }

    function testFirstAndLastHistoryEntriesCanBeSkippedWhenSqueezing() public {
        StreamsHistory[] memory history = hist();
        setStreams(sender, 0, 1, recv(receiver, 1), 1);
        history = histSkip(history, sender);
        skip(1);
        setStreams(sender, 0, 2, recv(receiver, 2), 1);
        history = hist(history, sender);
        skip(1);
        setStreams(sender, 0, 4, recv(receiver, 4), 1);
        history = histSkip(history, sender);
        skip(1);
        squeezeStreams(receiver, sender, history, 2);
        skipToCycleEnd();
        receiveStreams(receiver, 5);
    }

    function testPartOfTheWholeHistoryCanBeSqueezed() public {
        setStreams(sender, 0, 1, recv(receiver, 1), 1);
        (, bytes32 historyHash,,,) = streams.streamsState(sender, erc20);
        skip(1);
        setStreams(sender, 0, 2, recv(receiver, 2), 1);
        StreamsHistory[] memory history = hist(sender);
        skip(1);
        squeezeStreams(receiver, sender, historyHash, history, 2);
        skipToCycleEnd();
        receiveStreams(receiver, 1);
    }

    function testStreamsWithCopiesOfTheReceiverCanBeSqueezed() public {
        setStreams(sender, 0, 6, recv(recv(receiver, 1), recv(receiver, 2)), 2);
        skip(1);
        squeezeStreams(receiver, sender, hist(sender), 3);
        skipToCycleEnd();
        receiveStreams(receiver, 3);
    }

    function testStreamsWithManyReceiversCanBeSqueezed() public {
        setStreams(
            sender, 0, 14, recv(recv(receiver1, 1), recv(receiver2, 2), recv(receiver3, 4)), 2
        );
        skip(1);
        squeezeStreams(receiver2, sender, hist(sender), 2);
        skipToCycleEnd();
        receiveStreams(receiver1, 2);
        receiveStreams(receiver2, 2);
        receiveStreams(receiver3, 8);
    }

    function testPartiallySqueezedOldHistoryEntryCanBeSqueezedFully() public {
        setStreams(sender, 0, 8, recv(receiver, 1), 8);
        StreamsHistory[] memory history = hist(sender);
        skip(1);
        squeezeStreams(receiver, sender, history, 1);
        skip(1);
        setStreams(sender, 6, 6, recv(receiver, 2), 3);
        history = hist(history, sender);
        skip(1);
        squeezeStreams(receiver, sender, history, 3);
        skipToCycleEnd();
        receiveStreams(receiver, 4);
    }

    function testUnsqueezedHistoryEntriesFromBeforeLastSqueezeCanBeSqueezed() public {
        setStreams(sender, 0, 9, recv(receiver, 1), 9);
        StreamsHistory[] memory history1 = histSkip(sender);
        StreamsHistory[] memory history2 = hist(sender);
        skip(1);
        setStreams(sender, 8, 8, recv(receiver, 2), 4);
        history1 = hist(history1, sender);
        history2 = histSkip(history2, sender);
        skip(1);
        squeezeStreams(receiver, sender, history1, 2);
        squeezeStreams(receiver, sender, history2, 1);
        skipToCycleEnd();
        receiveStreams(receiver, 6);
    }

    function testLastSqueezedForPastCycleIsIgnored() public {
        setStreams(sender, 0, 3, recv(receiver, 1), 3);
        StreamsHistory[] memory history = hist(sender);
        skip(1);
        // Set the first element of the next squeezed table
        squeezeStreams(receiver, sender, history, 1);
        setStreams(sender, 2, 2, recv(receiver, 2), 1);
        history = hist(history, sender);
        skip(1);
        // Set the second element of the next squeezed table
        squeezeStreams(receiver, sender, history, 2);
        skipToCycleEnd();
        setStreams(sender, 0, 8, recv(receiver, 3), 2);
        history = hist(history, sender);
        skip(1);
        setStreams(sender, 5, 5, recv(receiver, 5), 1);
        history = hist(history, sender);
        skip(1);
        // The next squeezed table entries are ignored
        squeezeStreams(receiver, sender, history, 8);
    }

    function testLastSqueezedForConfigurationSetInPastCycleIsKeptAfterUpdatingStreams() public {
        setStreams(sender, 0, 2, recv(receiver, 2), 1);
        StreamsHistory[] memory history = hist(sender);
        skip(1);
        // Set the first element of the next squeezed table
        squeezeStreams(receiver, sender, history, 2);
        setStreams(sender, 0, cycleSecs + 1, recv(receiver, 1), cycleSecs + 1);
        history = hist(history, sender);
        skip(1);
        // Set the second element of the next squeezed table
        squeezeStreams(receiver, sender, history, 1);
        skipToCycleEnd();
        skip(1);
        // Set the first element of the next squeezed table
        squeezeStreams(receiver, sender, history, 1);
        skip(1);
        setStreams(sender, 0, 3, recv(receiver, 3), 1);
        history = hist(history, sender);
        skip(1);
        // There's 1 second of unsqueezed streaming of 1 per second in the current cycle
        squeezeStreams(receiver, sender, history, 4);
    }
}
