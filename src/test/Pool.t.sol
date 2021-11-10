// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DSTest} from "ds-test/test.sol";
import {PoolUserUtils} from "./UserUtils.t.sol";
import {PoolUser} from "./User.t.sol";
import {Hevm} from "./BaseTest.t.sol";
import {DripsReceiver, Pool, Receiver} from "../Pool.sol";

abstract contract PoolTest is PoolUserUtils {
    Pool private pool;

    PoolUser private sender;
    PoolUser private receiver;
    PoolUser private sender1;
    PoolUser private receiver1;
    PoolUser private sender2;
    PoolUser private receiver2;
    PoolUser private receiver3;
    uint256 private constant SUB_SENDER_1 = 1;
    uint256 private constant SUB_SENDER_2 = 2;

    // Must be called once from child contract `setUp`
    function setUp(Pool pool_) internal {
        pool = pool_;
        sender = createUser();
        sender1 = createUser();
        sender2 = createUser();
        receiver = createUser();
        receiver1 = createUser();
        receiver2 = createUser();
        receiver3 = createUser();
        // Sort receivers by address
        if (receiver1 > receiver2) (receiver1, receiver2) = (receiver2, receiver1);
        if (receiver2 > receiver3) (receiver2, receiver3) = (receiver3, receiver2);
        if (receiver1 > receiver2) (receiver1, receiver2) = (receiver2, receiver1);
    }

    function createUser() internal virtual returns (PoolUser);

    function warpToCycleEnd() internal {
        warpBy(pool.cycleSecs() - (block.timestamp % pool.cycleSecs()));
    }

    function warpBy(uint256 secs) internal {
        Hevm(HEVM_ADDRESS).warp(block.timestamp + secs);
    }

    function testAllowsSendingToASingleReceiver() public {
        updateSender(sender, 0, 100, receivers(receiver, 1));
        warpBy(15);
        // Sender had 15 seconds paying 1 per second
        changeBalance(sender, 85, 0);
        warpToCycleEnd();
        // Receiver 1 had 15 seconds paying 1 per second
        collect(receiver, 15);
    }

    function testAllowsSendingToASingleReceiverForFuzzyTime(uint8 cycles, uint8 timeInCycle)
        public
    {
        uint128 time = (cycles / 10) * pool.cycleSecs() + (timeInCycle % pool.cycleSecs());
        uint128 balance = 25 * pool.cycleSecs() + 256;
        updateSender(sender, 0, balance, receivers(receiver, 1));
        warpBy(time);
        // Sender had `time` seconds paying 1 per second
        changeBalance(sender, balance - time, 0);
        warpToCycleEnd();
        // Sender had `time` seconds paying 1 per second
        collect(receiver, time);
    }

    function testAllowsSendingToMultipleReceivers() public {
        updateSender(sender, 0, 6, receivers(receiver1, 1, receiver2, 2));
        warpToCycleEnd();
        // Sender had 2 seconds paying 1 per second
        collect(receiver1, 2);
        // Sender had 2 seconds paying 2 per second
        collect(receiver2, 4);
    }

    function testSendsSomeFundsFromASingleSenderToTwoReceivers() public {
        updateSender(sender, 0, 100, receivers(receiver1, 1, receiver2, 1));
        warpBy(14);
        // Sender had 14 seconds paying 2 per second
        changeBalance(sender, 72, 0);
        warpToCycleEnd();
        // Receiver 1 had 14 seconds paying 1 per second
        collect(receiver1, 14);
        // Receiver 2 had 14 seconds paying 1 per second
        collect(receiver2, 14);
    }

    function testSendsSomeFundsFromATwoSendersToASingleReceiver() public {
        updateSender(sender1, 0, 100, receivers(receiver, 1));
        warpBy(2);
        updateSender(sender2, 0, 100, receivers(receiver, 2));
        warpBy(15);
        // Sender1 had 17 seconds paying 1 per second
        changeBalance(sender1, 83, 0);
        // Sender2 had 15 seconds paying 2 per second
        changeBalance(sender2, 70, 0);
        warpToCycleEnd();
        // Receiver had 2 seconds paying 1 per second and 15 seconds paying 3 per second
        collect(receiver, 47);
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        collect(receiver, 0);
    }

    function testAllowsCollectingFundsWhileTheyAreBeingSent() public {
        updateSender(sender, 0, pool.cycleSecs() + 10, receivers(receiver, 1));
        warpToCycleEnd();
        // Receiver had cycleSecs seconds paying 1 per second
        collect(receiver, pool.cycleSecs());
        warpBy(7);
        // Sender had cycleSecs + 7 seconds paying 1 per second
        changeBalance(sender, 3, 0);
        warpToCycleEnd();
        // Receiver had 7 seconds paying 1 per second
        collect(receiver, 7);
    }

    function testCollectRevertsIfInvalidCurrDripsReceivers() public {
        setDripsReceivers(sender, dripsReceivers(receiver, 1));
        try sender.collect(address(sender), dripsReceivers(receiver, 2)) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, "Invalid current drips receivers", "Invalid collect revert reason");
        }
    }

    function testSendsFundsUntilTheyRunOut() public {
        updateSender(sender, 0, 100, receivers(receiver, 9));
        warpBy(10);
        // Sender had 10 seconds paying 9 per second, funds are about to run out
        assertWithdrawable(sender, 10);
        warpBy(1);
        // Sender had 11 seconds paying 9 per second, funds have run out
        assertWithdrawable(sender, 1);
        // Nothing more will be sent
        warpToCycleEnd();
        changeBalance(sender, 1, 0);
        collect(receiver, 99);
    }

    function testCollectableRevertsIfInvalidCurrDripsReceivers() public {
        setDripsReceivers(sender, dripsReceivers(receiver, 1));
        try sender.collectable(dripsReceivers(receiver, 2)) {
            assertTrue(false, "Collectable hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(
                reason,
                "Invalid current drips receivers",
                "Invalid collectable revert reason"
            );
        }
    }

    function testAllowsToppingUpWhileSending() public {
        updateSender(sender, 0, 100, receivers(receiver, 10));
        warpBy(6);
        // Sender had 6 seconds paying 10 per second
        changeBalance(sender, 40, 60);
        warpBy(5);
        // Sender had 5 seconds paying 10 per second
        changeBalance(sender, 10, 0);
        warpToCycleEnd();
        // Receiver had 11 seconds paying 10 per second
        collect(receiver, 110);
    }

    function testAllowsToppingUpAfterFundsRunOut() public {
        updateSender(sender, 0, 100, receivers(receiver, 10));
        warpBy(10);
        // Sender had 10 seconds paying 10 per second
        assertWithdrawable(sender, 0);
        warpToCycleEnd();
        // Receiver had 10 seconds paying 10 per second
        assertCollectable(receiver, 100);
        changeBalance(sender, 0, 60);
        warpBy(5);
        // Sender had 5 seconds paying 10 per second
        changeBalance(sender, 10, 0);
        warpToCycleEnd();
        // Receiver had 15 seconds paying 10 per second
        collect(receiver, 150);
    }

    function testAllowsSendingWhichShouldEndAfterMaxTimestamp() public {
        uint128 balance = type(uint64).max + uint128(6);
        updateSender(sender, 0, balance, receivers(receiver, 1));
        warpBy(10);
        // Sender had 10 seconds paying 1 per second
        changeBalance(sender, balance - 10, 0);
        warpToCycleEnd();
        // Receiver had 10 seconds paying 1 per second
        collect(receiver, 10);
    }

    function testAllowsSenderUpdateWithTopUpAndWithdrawal() public {
        sender.updateSender(10, 3, receivers(), receivers());
        assertWithdrawable(sender, 7);
    }

    function testAllowsNoSenderUpdate() public {
        updateSender(sender, 0, 6, receivers(receiver, 3));
        warpBy(1);
        // Sender had 1 second paying 3 per second
        updateSender(sender, 3, 3, receivers(receiver, 1));
        warpToCycleEnd();
        collect(receiver, 6);
    }

    function testAllowsChangingReceiversWhileSending() public {
        updateSender(sender, 0, 100, receivers(receiver1, 6, receiver2, 6));
        warpBy(3);
        setReceivers(sender, receivers(receiver1, 4, receiver2, 8));
        warpBy(4);
        // Sender had 7 seconds paying 12 per second
        changeBalance(sender, 16, 0);
        warpToCycleEnd();
        // Receiver1 had 3 seconds paying 6 per second and 4 seconds paying 4 per second
        collect(receiver1, 34);
        // Receiver2 had 3 seconds paying 6 per second and 4 seconds paying 8 per second
        collect(receiver2, 50);
    }

    function testAllowsRemovingReceiversWhileSending() public {
        updateSender(sender, 0, 100, receivers(receiver1, 5, receiver2, 5));
        warpBy(3);
        setReceivers(sender, receivers(receiver2, 10));
        warpBy(4);
        setReceivers(sender, receivers());
        warpBy(10);
        // Sender had 7 seconds paying 10 per second
        changeBalance(sender, 30, 0);
        warpToCycleEnd();
        // Receiver1 had 3 seconds paying 5 per second
        collect(receiver1, 15);
        // Receiver2 had 3 seconds paying 5 per second and 4 seconds paying 10 per second
        collect(receiver2, 55);
    }

    function testLimitsTheTotalReceiversCount() public {
        uint160 countMax = pool.MAX_RECEIVERS();
        Receiver[] memory receiversGood = new Receiver[](countMax);
        Receiver[] memory receiversBad = new Receiver[](countMax + 1);
        for (uint160 i = 0; i < countMax; i++) {
            receiversGood[i] = Receiver(address(i + 1), 1);
            receiversBad[i] = receiversGood[i];
        }
        receiversBad[countMax] = Receiver(address(countMax + 1), 1);

        setReceivers(sender, receiversGood);
        assertSetReceiversReverts(sender, receiversBad, "Too many receivers");
    }

    function testRejectsOverflowingTotalAmtPerSec() public {
        setReceivers(sender, receivers(receiver1, type(uint128).max));
        assertSetReceiversReverts(
            sender,
            receivers(receiver1, type(uint128).max, receiver2, 1),
            "Total amtPerSec too high"
        );
    }

    function testRejectsZeroAmtPerSecReceivers() public {
        assertSetReceiversReverts(sender, receivers(receiver, 0), "Receiver amtPerSec is zero");
    }

    function testRejectsUnsortedReceivers() public {
        assertSetReceiversReverts(
            sender,
            receivers(receiver2, 1, receiver1, 1),
            "Receivers not sorted by address"
        );
    }

    function testRejectsDuplicateReceivers() public {
        assertSetReceiversReverts(
            sender,
            receivers(receiver, 1, receiver, 2),
            "Duplicate receivers"
        );
    }

    function testUpdateSenderRevertsIfInvalidCurrReceivers() public {
        updateSender(sender, 0, 0, receivers(receiver, 1));
        try sender.updateSender(0, 0, receivers(receiver, 2), receivers()) {
            assertTrue(false, "Sender update hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, "Invalid current receivers", "Invalid sender update revert reason");
        }
    }

    function testAllowsAnAddressToBeASenderAndAReceiverIndependently() public {
        updateSender(sender, 0, 10, receivers(sender, 10));
        warpBy(1);
        // Sender had 1 second paying 10 per second
        assertWithdrawable(sender, 0);
        warpToCycleEnd();
        // Sender had 1 second paying 10 per second
        collect(sender, 10);
    }

    function testAllowsWithdrawalOfAllFunds() public {
        updateSender(sender, 0, 10, receivers(receiver, 1));
        warpBy(4);
        // Sender had 4 second paying 1 per second
        assertWithdrawable(sender, 6);
        uint256 expectedBalance = sender.balance() + 6;
        sender.updateSender(0, pool.WITHDRAW_ALL(), receivers(receiver, 1), receivers(receiver, 1));
        assertWithdrawable(sender, 0);
        assertBalance(sender, expectedBalance);
        warpToCycleEnd();
        // Receiver had 4 seconds paying 1 per second
        collect(receiver, 4);
    }

    function testWithdrawableRevertsIfInvalidCurrReceivers() public {
        updateSender(sender, 0, 0, receivers(receiver, 1));
        try sender.withdrawable(receivers(receiver, 2)) {
            assertTrue(false, "Withdrawable hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, "Invalid current receivers", "Invalid withdrawable revert reason");
        }
    }

    function testWithdrawableSubSenderRevertsIfInvalidCurrReceivers() public {
        updateSubSender(sender, SUB_SENDER_1, 0, 0, receivers(receiver, 1));
        try sender.withdrawableSubSender(SUB_SENDER_1, receivers(receiver, 2)) {
            assertTrue(false, "Withdrawable hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, "Invalid current receivers", "Invalid withdrawable revert reason");
        }
    }

    function testAnybodyCanCallCollect() public {
        updateSender(sender1, 0, 10, receivers(receiver, 10));
        warpToCycleEnd();
        // Receiver had 1 second paying 10 per second
        collect(sender2, receiver, 10);
    }

    function testSenderAndSubSenderAreIndependent() public {
        updateSender(sender, 0, 5, receivers(receiver1, 1));
        warpBy(3);
        updateSubSender(sender, SUB_SENDER_1, 0, 8, receivers(receiver1, 2, receiver2, 1));
        warpBy(1);
        // Sender had 4 seconds paying 1 per second
        changeBalance(sender, 1, 0);
        warpBy(1);
        // Sender sub-sender1 had 2 seconds paying 3 per second
        changeBalanceSubSender(sender, SUB_SENDER_1, 2, 0);
        warpToCycleEnd();
        // Receiver1 had 4 second paying 1 per second and 2 seconds paying 2 per second
        collect(receiver1, 8);
        // Receiver2 had 2 second paying 1 per second
        collect(receiver2, 2);
    }

    function testUserSubSendersAreIndependent() public {
        updateSubSender(sender, SUB_SENDER_1, 0, 5, receivers(receiver1, 1));
        warpBy(3);
        updateSubSender(sender, SUB_SENDER_2, 0, 8, receivers(receiver1, 2, receiver2, 1));
        warpBy(1);
        // Sender sub-sender1 had 4 seconds paying 1 per second
        changeBalanceSubSender(sender, SUB_SENDER_1, 1, 0);
        warpBy(1);
        // Sender sub-sender2 had 2 seconds paying 3 per second
        changeBalanceSubSender(sender, SUB_SENDER_2, 2, 0);
        warpToCycleEnd();
        // Receiver1 had 4 second paying 1 per second and 2 seconds paying 2 per second
        collect(receiver1, 8);
        // Receiver2 had 2 second paying 1 per second
        collect(receiver2, 2);
    }

    function testSubSendersOfDifferentUsersAreIndependent() public {
        updateSubSender(sender1, SUB_SENDER_1, 0, 5, receivers(receiver1, 1));
        warpBy(3);
        updateSubSender(sender2, SUB_SENDER_1, 0, 8, receivers(receiver1, 2, receiver2, 1));
        warpBy(1);
        // Sender1 sub-sender1 had 4 seconds paying 1 per second
        changeBalanceSubSender(sender1, SUB_SENDER_1, 1, 0);
        warpBy(1);
        // Sender2 sub-sender1 had 2 seconds paying 3 per second
        changeBalanceSubSender(sender2, SUB_SENDER_1, 2, 0);
        warpToCycleEnd();
        // Receiver1 had 4 second paying 1 per second and 2 seconds paying 2 per second
        collect(receiver1, 8);
        // Receiver2 had 2 second paying 1 per second
        collect(receiver2, 2);
    }

    function testLimitsTheTotalDripsReceiversCount() public {
        uint160 countMax = pool.MAX_DRIPS_RECEIVERS();
        DripsReceiver[] memory receiversGood = new DripsReceiver[](countMax);
        DripsReceiver[] memory receiversBad = new DripsReceiver[](countMax + 1);
        for (uint160 i = 0; i < countMax; i++) {
            receiversGood[i] = DripsReceiver(address(i + 1), 1);
            receiversBad[i] = receiversGood[i];
        }
        receiversBad[countMax] = DripsReceiver(address(countMax + 1), 1);

        setDripsReceivers(sender, receiversGood);
        assertSetDripsReceiversReverts(sender, receiversBad, "Too many drips receivers");
    }

    function testRejectsTooHighTotalWeightDripsReceivers() public {
        uint32 totalWeight = pool.TOTAL_DRIPS_WEIGHTS();
        setDripsReceivers(sender, dripsReceivers(receiver, totalWeight));
        assertSetDripsReceiversReverts(
            sender,
            dripsReceivers(receiver, totalWeight + 1),
            "Drips weights sum too high"
        );
    }

    function testRejectsZeroWeightDripsReceivers() public {
        assertSetDripsReceiversReverts(
            sender,
            dripsReceivers(receiver, 0),
            "Drips receiver weight is zero"
        );
    }

    function testRejectsUnsortedDripsReceivers() public {
        assertSetDripsReceiversReverts(
            sender,
            dripsReceivers(receiver2, 1, receiver1, 1),
            "Drips receivers not sorted by address"
        );
    }

    function testRejectsDuplicateDripsReceivers() public {
        assertSetDripsReceiversReverts(
            sender,
            dripsReceivers(receiver, 1, receiver, 2),
            "Duplicate drips receivers"
        );
    }

    function testUpdateSenderRevertsIfInvalidCurrDripsReceivers() public {
        setDripsReceivers(sender, dripsReceivers(receiver, 1));
        try sender.setDripsReceivers(dripsReceivers(receiver, 2), dripsReceivers()) {
            assertTrue(false, "Sender update hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(
                reason,
                "Invalid current drips receivers",
                "Invalid sender update revert reason"
            );
        }
    }

    function testCollectDrips() public {
        uint32 totalWeight = pool.TOTAL_DRIPS_WEIGHTS();
        updateSender(sender, 0, 10, receivers(receiver1, 10));
        setDripsReceivers(receiver1, dripsReceivers(receiver2, totalWeight));
        warpToCycleEnd();
        assertCollectable(receiver2, 0);
        // Receiver1 had 1 second paying 10 per second of which 10 is dripped
        collect(receiver1, 0, 10);
        // Receiver2 got 10 dripped from receiver1
        collect(receiver2, 10);
    }

    function testCollectDripsFundsFromDrips() public {
        uint32 totalWeight = pool.TOTAL_DRIPS_WEIGHTS();
        updateSender(sender, 0, 10, receivers(receiver1, 10));
        setDripsReceivers(receiver1, dripsReceivers(receiver2, totalWeight));
        setDripsReceivers(receiver2, dripsReceivers(receiver3, totalWeight));
        warpToCycleEnd();
        assertCollectable(receiver2, 0);
        assertCollectable(receiver3, 0);
        // Receiver1 had 1 second paying 10 per second of which 10 is dripped
        collect(receiver1, 0, 10);
        // Receiver2 got 10 dripped from receiver1 of which 10 is dripped
        collect(receiver2, 0, 10);
        // Receiver3 got 10 dripped from receiver2
        collect(receiver3, 10);
    }

    function testCollectMixesStreamsAndDrips() public {
        uint32 totalWeight = pool.TOTAL_DRIPS_WEIGHTS();
        updateSender(sender, 0, 10, receivers(receiver1, 5, receiver2, 5));
        setDripsReceivers(receiver1, dripsReceivers(receiver2, totalWeight));
        warpToCycleEnd();
        // Receiver2 had 1 second paying 5 per second
        assertCollectable(receiver2, 5);
        // Receiver1 had 1 second paying 5 per second
        collect(receiver1, 0, 5);
        // Receiver2 had 1 second paying 5 per second and got 5 dripped from receiver1
        collect(receiver2, 10);
    }

    function testCollectSplitsFundsBetweenReceiverAndDrips() public {
        uint32 totalWeight = pool.TOTAL_DRIPS_WEIGHTS();
        updateSender(sender, 0, 10, receivers(receiver1, 10));
        setDripsReceivers(
            receiver1,
            dripsReceivers(receiver2, totalWeight / 4, receiver3, totalWeight / 2)
        );
        warpToCycleEnd();
        assertCollectable(receiver2, 0);
        assertCollectable(receiver3, 0);
        // Receiver1 had 1 second paying 10 per second, of which 3/4 is dripped, which is 7
        collect(receiver1, 3, 7);
        // Receiver2 got 1/3 of 7 dripped from receiver1, which is 2
        collect(receiver2, 2);
        // Receiver3 got 2/3 of 7 dripped from receiver1, which is 5
        collect(receiver3, 5);
    }

    function testCanDripAllWhenCollectedDoesntSplitEvenly() public {
        uint32 totalWeight = pool.TOTAL_DRIPS_WEIGHTS();
        updateSender(sender, 0, 3, receivers(receiver1, 3));
        setDripsReceivers(
            receiver1,
            dripsReceivers(receiver2, totalWeight / 2, receiver3, totalWeight / 2)
        );
        warpToCycleEnd();
        // Receiver1 had 1 second paying 3 per second of which 3 is dripped
        collect(receiver1, 0, 3);
        // Receiver2 got 1 dripped from receiver
        collect(receiver2, 1);
        // Receiver3 got 2 dripped from receiver
        collect(receiver3, 2);
    }

    function testFlushSomeCycles() public {
        // Enough for 3 cycles
        uint128 amt = pool.cycleSecs() * 3;
        warpToCycleEnd();
        updateSender(sender, 0, amt, receivers(receiver, 1));
        warpToCycleEnd();
        warpToCycleEnd();
        warpToCycleEnd();
        flushCycles(receiver, 3, 2, 1);
        collect(receiver, amt);
    }

    function testFlushAllCycles() public {
        // Enough for 3 cycles
        uint128 amt = pool.cycleSecs() * 3;
        warpToCycleEnd();
        updateSender(sender, 0, amt, receivers(receiver, 1));
        warpToCycleEnd();
        warpToCycleEnd();
        warpToCycleEnd();
        flushCycles(receiver, 3, type(uint64).max, 0);
        collect(receiver, amt);
    }

    function testFundsGivenFromSenderCanBeCollected() public {
        sender.give(address(receiver), 10);
        collect(receiver, 10);
    }

    function testFundsGivenFromSubSenderCanBeCollected() public {
        sender.giveFromSubSender(SUB_SENDER_1, address(receiver), 10);
        collect(receiver, 10);
    }
}
