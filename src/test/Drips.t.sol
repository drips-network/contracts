// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {DSTest} from "ds-test/test.sol";
import {Hevm} from "./Hevm.t.sol";
import {Drips, DripsReceiver} from "../Drips.sol";

contract DripsTest is DSTest {
    string internal constant ERROR_NOT_SORTED = "Receivers not sorted";
    string internal constant ERROR_INVALID_DRIPS_LIST = "Invalid current drips list";
    string internal constant ERROR_BALANCE = "Insufficient balance";

    Drips.Storage internal s;
    uint32 internal cycleSecs = 10;
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

    function setUp() public {
        warpToCycleEnd();
    }

    function warpToCycleEnd() internal {
        warpBy(cycleSecs - (block.timestamp % cycleSecs));
    }

    function warpBy(uint256 secs) internal {
        Hevm(HEVM_ADDRESS).warp(block.timestamp + secs);
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

    function recv() internal pure returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](0);
    }

    function recv(uint256 userId, uint256 amtPerSec)
        internal
        pure
        returns (DripsReceiver[] memory receivers)
    {
        return recv(userId, amtPerSec, 0, 0);
    }

    function recv(
        uint256 userId,
        uint256 amtPerSec,
        uint256 start,
        uint256 duration
    ) internal pure returns (DripsReceiver[] memory receivers) {
        receivers = new DripsReceiver[](1);
        receivers[0] = DripsReceiver(userId, uint128(amtPerSec), uint32(start), uint32(duration));
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

    function random(
        bytes32 name,
        uint256 salt,
        uint256 range
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(name, salt))) % range;
    }

    function combineSalt(uint256 a, uint256 b) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(a, b)));
    }

    function genRandomRecv(
        uint256 randomSalt,
        uint8 amountReceiver,
        uint128 maxAmtPerSec,
        uint32 maxStart,
        uint32 maxDuration
    ) internal pure returns (DripsReceiver[] memory) {
        uint256 inPercent = 100;
        uint256 probDefaultEnd = random("default.end", randomSalt, inPercent);
        uint256 probStartNow = random("start.now", randomSalt, inPercent);
        DripsReceiver[] memory receivers = new DripsReceiver[](amountReceiver);
        for (uint8 i = 0; i < amountReceiver; i++) {
            uint256 salt = combineSalt(randomSalt, i);
            uint256 amtPerSec = random("amtPerSec", salt, maxAmtPerSec) + 1;
            uint256 start = random("start", salt, maxStart);
            if (start % 100 <= probStartNow) start = 0;
            uint256 duration = random("duration", salt, maxDuration);
            if (duration % 100 <= probDefaultEnd) duration = 0;

            receivers[i] = DripsReceiver(i, uint128(amtPerSec), uint32(start), uint32(duration));
        }
        return receivers;
    }

    function receiveDrips(
        DripsReceiver[] memory receivers,
        uint32 defaultEnd,
        uint32 updateTime
    ) internal {
        emit log_named_uint("defaultEnd:", defaultEnd);
        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory r = receivers[i];
            uint32 duration = r.duration;
            uint32 start = r.start;
            if (start == 0) start = updateTime;
            if (duration == 0) duration = defaultEnd - start;
            if (start < updateTime) duration -= updateTime - start;

            // drips was in the past, not added
            if (start + duration < updateTime) duration = 0;

            uint256 expectedAmt = duration * r.amtPerSec;
            (uint128 actualAmt, ) = Drips.receiveDrips(
                s,
                cycleSecs,
                r.userId,
                defaultAsset,
                type(uint32).max
            );
            // only log if acutalAmt doesn't match exptectedAmt
            if (expectedAmt != actualAmt) {
                emit log_named_uint("userId:", r.userId);
                emit log_named_uint("start:", r.start);
                emit log_named_uint("duration:", r.duration);
                emit log_named_uint("amtPerSec:", r.amtPerSec);
            }
            assertEq(actualAmt, expectedAmt);
        }
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
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        (uint128 newBalance, int128 realBalanceDelta) = Drips.setDrips(
            s,
            cycleSecs,
            userId,
            assetId,
            loadCurrReceivers(assetId, userId),
            balanceDelta,
            newReceivers
        );

        storeCurrReceivers(assetId, userId, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid drips balance");
        (, uint32 updateTime, uint128 actualBalance, ) = Drips.dripsState(s, userId, assetId);
        assertEq(updateTime, block.timestamp, "Invalid new last update time");
        assertEq(balanceTo, actualBalance, "Invalid drips balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
    }

    function assertDrips(
        uint256 assetId,
        uint256 userId,
        DripsReceiver[] memory currReceivers
    ) internal {
        (bytes32 actual, , , ) = Drips.dripsState(s, userId, assetId);
        bytes32 expected = Drips.hashDrips(currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function assertBalance(uint256 userId, uint128 expected) internal {
        changeBalance(userId, expected, expected);
    }

    function changeBalance(
        uint256 userId,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        setDrips(userId, balanceFrom, balanceTo, loadCurrReceivers(defaultAsset, userId));
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
        Drips.setDrips(s, cycleSecs, userId, assetId, currReceivers, balanceDelta, newReceivers);
    }

    function receiveDrips(uint256 userId, uint128 expectedAmt) internal {
        receiveDrips(defaultAsset, userId, expectedAmt);
    }

    function receiveDrips(
        uint256 assetId,
        uint256 userId,
        uint128 expectedAmt
    ) internal {
        (uint128 actualAmt, ) = Drips.receiveDrips(s, cycleSecs, userId, assetId, type(uint32).max);
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

        (uint128 receivedAmt, uint32 receivableCycles) = Drips.receiveDrips(
            s,
            cycleSecs,
            userId,
            defaultAsset,
            maxCycles
        );

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from drips");
        assertEq(receivableCycles, expectedCyclesAfter, "Invalid receivable drips cycles left");
        assertReceivableDripsCycles(userId, expectedCyclesAfter);
        assertReceivableDrips(userId, type(uint32).max, expectedAmtAfter, 0);
    }

    function assertReceivableDripsCycles(uint256 userId, uint32 expectedCycles) internal {
        uint32 actualCycles = Drips.receivableDripsCycles(s, cycleSecs, userId, defaultAsset);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable drips cycles");
    }

    function assertReceivableDrips(uint256 userId, uint128 expectedAmt) internal {
        (uint128 actualAmt, ) = Drips.receivableDrips(
            s,
            cycleSecs,
            userId,
            defaultAsset,
            type(uint32).max
        );
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
    }

    function assertReceivableDrips(
        uint256 userId,
        uint32 maxCycles,
        uint128 expectedAmt,
        uint32 expectedCycles
    ) internal {
        (uint128 actualAmt, uint32 actualCycles) = Drips.receivableDrips(
            s,
            cycleSecs,
            userId,
            defaultAsset,
            maxCycles
        );
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
        assertEq(actualCycles, expectedCycles, "Invalid receivable drips cycles");
    }

    function testAllowsDrippingToASingleReceiver() public {
        setDrips(sender, 0, 100, recv(receiver, 1));
        warpBy(15);
        // Sender had 15 seconds paying 1 per second
        changeBalance(sender, 85, 0);
        warpToCycleEnd();
        // Receiver 1 had 15 seconds paying 1 per second
        receiveDrips(receiver, 15);
    }

    function testDripsToTwoReceivers() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 1), recv(receiver2, 1)));
        warpBy(14);
        // Sender had 14 seconds paying 2 per second
        changeBalance(sender, 72, 0);
        warpToCycleEnd();
        // Receiver 1 had 14 seconds paying 1 per second
        receiveDrips(receiver1, 14);
        // Receiver 2 had 14 seconds paying 1 per second
        receiveDrips(receiver2, 14);
    }

    function testDripsFromTwoSendersToASingleReceiver() public {
        setDrips(sender1, 0, 100, recv(receiver, 1));
        warpBy(2);
        setDrips(sender2, 0, 100, recv(receiver, 2));
        warpBy(15);
        // Sender1 had 17 seconds paying 1 per second
        changeBalance(sender1, 83, 0);
        // Sender2 had 15 seconds paying 2 per second
        changeBalance(sender2, 70, 0);
        warpToCycleEnd();
        // Receiver had 2 seconds paying 1 per second and 15 seconds paying 3 per second
        receiveDrips(receiver, 47);
    }

    function testDripsWithStartAndDuration() public {
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp + 5, 10));
        warpBy(5);
        assertBalance(sender, 10);
        warpBy(10);
        assertBalance(sender, 0);
        warpToCycleEnd();
        receiveDrips(receiver, 10);
    }

    function testDripsWithStartAndDurationRequireSufficientBalance() public {
        assertSetDripsReverts(
            sender,
            0,
            1,
            recv(receiver, 1, block.timestamp + 1, 2),
            ERROR_BALANCE
        );
    }

    function testDripsWithOnlyDuration() public {
        setDrips(sender, 0, 10, recv(receiver, 1, 0, 10));
        warpBy(10);
        warpToCycleEnd();
        receiveDrips(receiver, 10);
    }

    function testDripsWithOnlyDurationRequireSufficientBalance() public {
        assertSetDripsReverts(sender, 0, 1, recv(receiver, 1, 0, 2), ERROR_BALANCE);
    }

    function testDripsWithOnlyStart() public {
        setDrips(sender, 0, 10, recv(receiver, 1, block.timestamp + 5, 0));
        warpBy(5);
        assertBalance(sender, 10);
        warpBy(10);
        assertBalance(sender, 0);
        warpToCycleEnd();
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
        warpBy(8);
        assertBalance(sender, 5);
        warpToCycleEnd();
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
        warpBy(19);
        assertBalance(sender, 0);
        warpToCycleEnd();
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
        warpBy(10);
        warpToCycleEnd();
        receiveDrips(receiver1, 10);
        receiveDrips(receiver2, 8);
        receiveDrips(receiver3, 24);
        receiveDrips(receiver4, 20);
    }

    function testDripsWithStartInThePast() public {
        warpBy(5);
        setDrips(sender, 0, 3, recv(receiver, 1, block.timestamp - 5, 0));
        warpBy(3);
        assertBalance(sender, 0);
        warpToCycleEnd();
        receiveDrips(receiver, 3);
    }

    function testDripsWithStartInThePastAndDurationIntoFuture() public {
        warpBy(5);
        setDrips(sender, 0, 3, recv(receiver, 1, block.timestamp - 5, 8));
        warpBy(3);
        assertBalance(sender, 0);
        warpToCycleEnd();
        receiveDrips(receiver, 3);
    }

    function testDripsWithStartAndDurationInThePast() public {
        warpBy(5);
        setDrips(sender, 0, 0, recv(receiver, 1, block.timestamp - 5, 3));
        warpToCycleEnd();
        receiveDrips(receiver, 0);
    }

    function testDripsWithStartAfterFundsRunOut() public {
        setDrips(
            sender,
            0,
            4,
            recv(recv(receiver1, 1), recv(receiver2, 2, block.timestamp + 5, 0))
        );
        warpBy(6);
        warpToCycleEnd();
        receiveDrips(receiver1, 4);
        receiveDrips(receiver2, 0);
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
        warpBy(3);
        warpToCycleEnd();
        // Has been receiving 2 per second for 2 seconds
        receiveDrips(receiver1, 4);
        // Has been receiving 1 per second for 3 seconds
        receiveDrips(receiver2, 3);
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        receiveDrips(receiver, 0);
    }

    function testDoesNotCollectCyclesBeforeFirstDrip() public {
        warpBy(cycleSecs / 2);
        // Dripping starts in 2 cycles
        setDrips(sender, 0, 1, recv(receiver, 1, block.timestamp + cycleSecs * 2, 0));
        // The first cycle hasn't been dripping
        warpToCycleEnd();
        assertReceivableDripsCycles(receiver, 0);
        assertReceivableDrips(receiver, 0);
        // The second cycle hasn't been dripping
        warpToCycleEnd();
        assertReceivableDripsCycles(receiver, 0);
        assertReceivableDrips(receiver, 0);
        // The third cycle has been dripping
        warpToCycleEnd();
        assertReceivableDripsCycles(receiver, 1);
        receiveDrips(receiver, 1);
    }

    function testAllowsReceivingWhileBeingDrippedTo() public {
        setDrips(sender, 0, cycleSecs + 10, recv(receiver, 1));
        warpToCycleEnd();
        // Receiver had cycleSecs seconds paying 1 per second
        receiveDrips(receiver, cycleSecs);
        warpBy(7);
        // Sender had cycleSecs + 7 seconds paying 1 per second
        changeBalance(sender, 3, 0);
        warpToCycleEnd();
        // Receiver had 7 seconds paying 1 per second
        receiveDrips(receiver, 7);
    }

    function testDripsFundsUntilTheyRunOut() public {
        setDrips(sender, 0, 100, recv(receiver, 9));
        warpBy(10);
        // Sender had 10 seconds paying 9 per second, drips balance is about to run out
        assertBalance(sender, 10);
        warpBy(1);
        // Sender had 11 seconds paying 9 per second, drips balance has run out
        assertBalance(sender, 1);
        // Nothing more will be dripped
        warpToCycleEnd();
        changeBalance(sender, 1, 0);
        receiveDrips(receiver, 99);
    }

    function testAllowsToppingUpWhileDripping() public {
        setDrips(sender, 0, 100, recv(receiver, 10));
        warpBy(6);
        // Sender had 6 seconds paying 10 per second
        changeBalance(sender, 40, 60);
        warpBy(5);
        // Sender had 5 seconds paying 10 per second
        changeBalance(sender, 10, 0);
        warpToCycleEnd();
        // Receiver had 11 seconds paying 10 per second
        receiveDrips(receiver, 110);
    }

    function testAllowsToppingUpAfterFundsRunOut() public {
        setDrips(sender, 0, 100, recv(receiver, 10));
        warpBy(10);
        // Sender had 10 seconds paying 10 per second
        assertBalance(sender, 0);
        warpToCycleEnd();
        // Receiver had 10 seconds paying 10 per second
        assertReceivableDrips(receiver, 100);
        changeBalance(sender, 0, 60);
        warpBy(5);
        // Sender had 5 seconds paying 10 per second
        changeBalance(sender, 10, 0);
        warpToCycleEnd();
        // Receiver had 15 seconds paying 10 per second
        receiveDrips(receiver, 150);
    }

    function testAllowsDrippingWhichShouldEndAfterMaxTimestamp() public {
        uint128 balance = type(uint32).max + uint128(6);
        setDrips(sender, 0, balance, recv(receiver, 1));
        warpBy(10);
        // Sender had 10 seconds paying 1 per second
        changeBalance(sender, balance - 10, 0);
        warpToCycleEnd();
        // Receiver had 10 seconds paying 1 per second
        receiveDrips(receiver, 10);
    }

    function testAllowsDripsConfigurationWithOverflowingTotalAmtPerSec() public {
        setDrips(sender, 0, 2, recv(recv(receiver, 1), recv(receiver, type(uint128).max)));
        warpToCycleEnd();
        // Sender hasn't sent anything
        changeBalance(sender, 2, 0);
        // Receiver hasnt received anything
        receiveDrips(receiver, 0);
    }

    function testAllowsDrippingWithDurationEndingAfterMaxTimestamp() public {
        uint32 maxTimestamp = type(uint32).max;
        uint32 currTimestamp = uint32(block.timestamp);
        uint32 maxDuration = maxTimestamp - currTimestamp;
        uint32 duration = maxDuration + 5;
        setDrips(sender, 0, duration, recv(receiver, 1, 0, duration));
        warpToCycleEnd();
        receiveDrips(receiver, cycleSecs);
        setDrips(sender, duration - cycleSecs, 0, recv());
    }

    function testAllowsChangingReceiversWhileDripping() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 6), recv(receiver2, 6)));
        warpBy(3);
        setDrips(sender, 64, 64, recv(recv(receiver1, 4), recv(receiver2, 8)));
        warpBy(4);
        // Sender had 7 seconds paying 12 per second
        changeBalance(sender, 16, 0);
        warpToCycleEnd();
        // Receiver1 had 3 seconds paying 6 per second and 4 seconds paying 4 per second
        receiveDrips(receiver1, 34);
        // Receiver2 had 3 seconds paying 6 per second and 4 seconds paying 8 per second
        receiveDrips(receiver2, 50);
    }

    function testAllowsRemovingReceiversWhileDripping() public {
        setDrips(sender, 0, 100, recv(recv(receiver1, 5), recv(receiver2, 5)));
        warpBy(3);
        setDrips(sender, 70, 70, recv(receiver2, 10));
        warpBy(4);
        setDrips(sender, 30, 30, recv());
        warpBy(10);
        // Sender had 7 seconds paying 10 per second
        changeBalance(sender, 30, 0);
        warpToCycleEnd();
        // Receiver1 had 3 seconds paying 5 per second
        receiveDrips(receiver1, 15);
        // Receiver2 had 3 seconds paying 5 per second and 4 seconds paying 10 per second
        receiveDrips(receiver2, 55);
    }

    function testLimitsTheTotalReceiversCount() public {
        uint160 countMax = Drips.MAX_DRIPS_RECEIVERS;
        DripsReceiver[] memory receivers = new DripsReceiver[](countMax);
        for (uint160 i = 0; i < countMax; i++) {
            receivers[i] = recv(i, 1, 0, 0)[0];
        }
        setDrips(sender, 0, 0, receivers);
        receivers = recv(receivers, recv(countMax, 1, 0, 0));
        assertSetDripsReverts(sender, 0, 0, receivers, "Too many drips receivers");
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
        setDrips(sender, 0, 0, recv(receiver, 1));
        assertSetDripsReverts(sender, recv(receiver, 2), 0, 0, recv(), ERROR_INVALID_DRIPS_LIST);
    }

    function testAllowsAnAddressToDripAndReceiveIndependently() public {
        setDrips(sender, 0, 10, recv(sender, 10));
        warpBy(1);
        // Sender had 1 second paying 10 per second
        assertBalance(sender, 0);
        warpToCycleEnd();
        // Sender had 1 second paying 10 per second
        receiveDrips(sender, 10);
    }

    function testCapsWithdrawalOfMoreThanDripsBalance() public {
        DripsReceiver[] memory receivers = recv(receiver, 1);
        setDrips(sender, 0, 10, receivers);
        warpBy(4);
        // Sender had 4 second paying 1 per second
        (uint128 newBalance, int128 realBalanceDelta) = Drips.setDrips(
            s,
            cycleSecs,
            sender,
            defaultAsset,
            receivers,
            type(int128).min,
            receivers
        );
        storeCurrReceivers(defaultAsset, sender, receivers);
        assertEq(newBalance, 0, "Invalid balance");
        assertEq(realBalanceDelta, -6, "Invalid real balance delta");
        assertBalance(sender, 0);
        warpToCycleEnd();
        // Receiver had 4 seconds paying 1 per second
        receiveDrips(receiver, 4);
    }

    function testReceiveNotAllDripsCycles() public {
        // Enough for 3 cycles
        uint128 amt = cycleSecs * 3;
        warpToCycleEnd();
        setDrips(sender, 0, amt, recv(receiver, 1));
        warpToCycleEnd();
        warpToCycleEnd();
        warpToCycleEnd();
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
        warpToCycleEnd();
        setDrips(sender, 0, amt, recv(recv(sender, 1), recv(receiver, 2)));
        warpToCycleEnd();
        receiveDrips(sender, cycleSecs);
        receiveDrips(receiver, cycleSecs * 2);
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

        warpToCycleEnd();
        // Covers 2 cycles of dripping
        setDrips(otherAsset, sender, 0, 6 * cycleSecs, recv(receiver1, 3));

        warpToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        receiveDrips(defaultAsset, receiver1, 6 * cycleSecs);
        // receiver1 had 1.5 cycles of 2 per second
        receiveDrips(defaultAsset, receiver2, 3 * cycleSecs);
        // receiver1 had 1 cycle of 3 per second
        receiveDrips(otherAsset, receiver1, 3 * cycleSecs);
        // receiver2 received nothing
        receiveDrips(otherAsset, receiver2, 0);

        warpToCycleEnd();
        // receiver1 received nothing
        receiveDrips(defaultAsset, receiver1, 0);
        // receiver2 received nothing
        receiveDrips(defaultAsset, receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        receiveDrips(otherAsset, receiver1, 3 * cycleSecs);
        // receiver2 received nothing
        receiveDrips(otherAsset, receiver2, 0);
    }

    function testFuzzDripsReceiver(uint256 salt) public {
        uint8 amountReceivers = 10;
        uint128 maxAmtPerSec = 50;
        uint32 maxDuration = 100;
        uint32 maxStart = 100;

        uint128 maxCosts = amountReceivers * maxAmtPerSec * maxDuration;
        emit log_named_uint("topUp", maxCosts);
        uint128 maxAllDripsFinished = maxStart + maxDuration;

        DripsReceiver[] memory receivers = genRandomRecv(
            salt,
            amountReceivers,
            maxAmtPerSec,
            maxStart,
            maxDuration
        );
        emit log_named_uint("setDrips.updateTime", block.timestamp);
        setDrips(sender, 0, maxCosts, receivers);

        (, uint32 updateTime, , uint32 defaultEnd) = Drips.dripsState(s, sender, defaultAsset);

        if (defaultEnd > maxAllDripsFinished && defaultEnd != type(uint32).max)
            maxAllDripsFinished = defaultEnd;

        warpBy(maxAllDripsFinished);
        warpToCycleEnd();
        emit log_named_uint("receiveDrips.time", block.timestamp);
        receiveDrips(receivers, defaultEnd, updateTime);
    }
}
