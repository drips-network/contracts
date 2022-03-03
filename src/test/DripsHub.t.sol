// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DSTest} from "ds-test/test.sol";
import {DripsHubUserUtils} from "./DripsHubUserUtils.t.sol";
import {DripsHubUser} from "./DripsHubUser.t.sol";
import {Hevm} from "./Hevm.t.sol";
import {SplitsReceiver, DripsHub, DripsReceiver} from "../DripsHub.sol";

abstract contract DripsHubTest is DripsHubUserUtils {
    DripsHub private dripsHub;

    DripsHubUser private user;
    DripsHubUser private receiver;
    DripsHubUser private user1;
    DripsHubUser private receiver1;
    DripsHubUser private user2;
    DripsHubUser private receiver2;
    DripsHubUser private receiver3;
    uint256 private constant ACCOUNT_1 = 1;
    uint256 private constant ACCOUNT_2 = 2;

    // Must be called once from child contract `setUp`
    function setUp(DripsHub dripsHub_) internal {
        dripsHub = dripsHub_;
        user = createUser();
        user1 = createUser();
        user2 = createUser();
        receiver = createUser();
        receiver1 = createUser();
        receiver2 = createUser();
        receiver3 = createUser();
        // Sort receivers by address
        if (receiver1 > receiver2) (receiver1, receiver2) = (receiver2, receiver1);
        if (receiver2 > receiver3) (receiver2, receiver3) = (receiver3, receiver2);
        if (receiver1 > receiver2) (receiver1, receiver2) = (receiver2, receiver1);
    }

    function createUser() internal virtual returns (DripsHubUser);

    function warpToCycleEnd() internal {
        warpBy(dripsHub.cycleSecs() - (block.timestamp % dripsHub.cycleSecs()));
    }

    function warpBy(uint256 secs) internal {
        Hevm(HEVM_ADDRESS).warp(block.timestamp + secs);
    }

    function testAllowsDrippingToASingleReceiver() public {
        setDrips(user, 0, 100, dripsReceivers(receiver, 1));
        warpBy(15);
        // User had 15 seconds paying 1 per second
        changeBalance(user, 85, 0);
        warpToCycleEnd();
        // Receiver 1 had 15 seconds paying 1 per second
        collect(receiver, 15);
    }

    function testAllowsDrippingToASingleReceiverForFuzzyTime(uint8 cycles, uint8 timeInCycle)
        public
    {
        uint128 time = (cycles / 10) * dripsHub.cycleSecs() + (timeInCycle % dripsHub.cycleSecs());
        uint128 balance = 25 * dripsHub.cycleSecs() + 256;
        setDrips(user, 0, balance, dripsReceivers(receiver, 1));
        warpBy(time);
        // User had `time` seconds paying 1 per second
        changeBalance(user, balance - time, 0);
        warpToCycleEnd();
        // User had `time` seconds paying 1 per second
        collect(receiver, time);
    }

    function testAllowsDrippingToMultipleReceivers() public {
        setDrips(user, 0, 6, dripsReceivers(receiver1, 1, receiver2, 2));
        warpToCycleEnd();
        // User had 2 seconds paying 1 per second
        collect(receiver1, 2);
        // User had 2 seconds paying 2 per second
        collect(receiver2, 4);
    }

    function testDripsSomeFundsToTwoReceivers() public {
        setDrips(user, 0, 100, dripsReceivers(receiver1, 1, receiver2, 1));
        warpBy(14);
        // User had 14 seconds paying 2 per second
        changeBalance(user, 72, 0);
        warpToCycleEnd();
        // Receiver 1 had 14 seconds paying 1 per second
        collect(receiver1, 14);
        // Receiver 2 had 14 seconds paying 1 per second
        collect(receiver2, 14);
    }

    function testDripsSomeFundsFromTwoUsersToASingleReceiver() public {
        setDrips(user1, 0, 100, dripsReceivers(receiver, 1));
        warpBy(2);
        setDrips(user2, 0, 100, dripsReceivers(receiver, 2));
        warpBy(15);
        // User1 had 17 seconds paying 1 per second
        changeBalance(user1, 83, 0);
        // User2 had 15 seconds paying 2 per second
        changeBalance(user2, 70, 0);
        warpToCycleEnd();
        // Receiver had 2 seconds paying 1 per second and 15 seconds paying 3 per second
        collect(receiver, 47);
    }

    function testDoesNotRequireReceiverToBeInitialized() public {
        collect(receiver, 0);
    }

    function testAllowsCollectingFundsWhileTheyAreBeingDripped() public {
        setDrips(user, 0, dripsHub.cycleSecs() + 10, dripsReceivers(receiver, 1));
        warpToCycleEnd();
        // Receiver had cycleSecs seconds paying 1 per second
        collect(receiver, dripsHub.cycleSecs());
        warpBy(7);
        // User had cycleSecs + 7 seconds paying 1 per second
        changeBalance(user, 3, 0);
        warpToCycleEnd();
        // Receiver had 7 seconds paying 1 per second
        collect(receiver, 7);
    }

    function testCollectRevertsIfInvalidCurrSplitsReceivers() public {
        setSplits(user, splitsReceivers(receiver, 1));
        try user.collect(address(user), defaultAsset, splitsReceivers(receiver, 2)) {
            assertTrue(false, "Collect hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, "Invalid current splits receivers", "Invalid collect revert reason");
        }
    }

    function testDripsFundsUntilTheyRunOut() public {
        setDrips(user, 0, 100, dripsReceivers(receiver, 9));
        warpBy(10);
        // User had 10 seconds paying 9 per second, drips balance is about to run out
        assertDripsBalance(user, 10);
        warpBy(1);
        // User had 11 seconds paying 9 per second, drips balance has run out
        assertDripsBalance(user, 1);
        // Nothing more will be dripped
        warpToCycleEnd();
        changeBalance(user, 1, 0);
        collect(receiver, 99);
    }

    function testCollectableAllRevertsIfInvalidCurrSplitsReceivers() public {
        setSplits(user, splitsReceivers(receiver, 1));
        try user.collectableAll(defaultAsset, splitsReceivers(receiver, 2)) {
            assertTrue(false, "Collectable hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(
                reason,
                "Invalid current splits receivers",
                "Invalid collectable revert reason"
            );
        }
    }

    function testAllowsToppingUpWhileDripping() public {
        setDrips(user, 0, 100, dripsReceivers(receiver, 10));
        warpBy(6);
        // User had 6 seconds paying 10 per second
        changeBalance(user, 40, 60);
        warpBy(5);
        // User had 5 seconds paying 10 per second
        changeBalance(user, 10, 0);
        warpToCycleEnd();
        // Receiver had 11 seconds paying 10 per second
        collect(receiver, 110);
    }

    function testAllowsToppingUpAfterFundsRunOut() public {
        setDrips(user, 0, 100, dripsReceivers(receiver, 10));
        warpBy(10);
        // User had 10 seconds paying 10 per second
        assertDripsBalance(user, 0);
        warpToCycleEnd();
        // Receiver had 10 seconds paying 10 per second
        assertCollectableAll(receiver, 100);
        changeBalance(user, 0, 60);
        warpBy(5);
        // User had 5 seconds paying 10 per second
        changeBalance(user, 10, 0);
        warpToCycleEnd();
        // Receiver had 15 seconds paying 10 per second
        collect(receiver, 150);
    }

    function testAllowsDrippingWhichShouldEndAfterMaxTimestamp() public {
        uint128 balance = type(uint64).max + uint128(6);
        setDrips(user, 0, balance, dripsReceivers(receiver, 1));
        warpBy(10);
        // User had 10 seconds paying 1 per second
        changeBalance(user, balance - 10, 0);
        warpToCycleEnd();
        // Receiver had 10 seconds paying 1 per second
        collect(receiver, 10);
    }

    function testAllowsNoDripsReceiversUpdate() public {
        setDrips(user, 0, 6, dripsReceivers(receiver, 3));
        warpBy(1);
        // User had 1 second paying 3 per second
        setDrips(user, 3, 3, dripsReceivers(receiver, 3));
        warpToCycleEnd();
        collect(receiver, 6);
    }

    function testAllowsChangingReceiversWhileDripping() public {
        setDrips(user, 0, 100, dripsReceivers(receiver1, 6, receiver2, 6));
        warpBy(3);
        setDrips(user, 64, 64, dripsReceivers(receiver1, 4, receiver2, 8));
        warpBy(4);
        // User had 7 seconds paying 12 per second
        changeBalance(user, 16, 0);
        warpToCycleEnd();
        // Receiver1 had 3 seconds paying 6 per second and 4 seconds paying 4 per second
        collect(receiver1, 34);
        // Receiver2 had 3 seconds paying 6 per second and 4 seconds paying 8 per second
        collect(receiver2, 50);
    }

    function testAllowsRemovingReceiversWhileDripping() public {
        setDrips(user, 0, 100, dripsReceivers(receiver1, 5, receiver2, 5));
        warpBy(3);
        setDrips(user, 70, 70, dripsReceivers(receiver2, 10));
        warpBy(4);
        setDrips(user, 30, 30, dripsReceivers());
        warpBy(10);
        // User had 7 seconds paying 10 per second
        changeBalance(user, 30, 0);
        warpToCycleEnd();
        // Receiver1 had 3 seconds paying 5 per second
        collect(receiver1, 15);
        // Receiver2 had 3 seconds paying 5 per second and 4 seconds paying 10 per second
        collect(receiver2, 55);
    }

    function testLimitsTheTotalReceiversCount() public {
        uint160 countMax = dripsHub.MAX_DRIPS_RECEIVERS();
        DripsReceiver[] memory receiversGood = new DripsReceiver[](countMax);
        DripsReceiver[] memory receiversBad = new DripsReceiver[](countMax + 1);
        for (uint160 i = 0; i < countMax; i++) {
            receiversGood[i] = DripsReceiver(address(i + 1), 1);
            receiversBad[i] = receiversGood[i];
        }
        receiversBad[countMax] = DripsReceiver(address(countMax + 1), 1);

        setDrips(user, 0, 0, receiversGood);
        assertSetReceiversReverts(user, receiversBad, "Too many drips receivers");
    }

    function testRejectsOverflowingTotalAmtPerSec() public {
        setDrips(user, 0, 0, dripsReceivers(receiver1, type(uint128).max));
        assertSetReceiversReverts(
            user,
            dripsReceivers(receiver1, type(uint128).max, receiver2, 1),
            "Total drips receivers amtPerSec too high"
        );
    }

    function testRejectsZeroAmtPerSecReceivers() public {
        assertSetReceiversReverts(
            user,
            dripsReceivers(receiver, 0),
            "Drips receiver amtPerSec is zero"
        );
    }

    function testRejectsUnsortedReceivers() public {
        assertSetReceiversReverts(
            user,
            dripsReceivers(receiver2, 1, receiver1, 1),
            "Drips receivers not sorted by address"
        );
    }

    function testRejectsDuplicateReceivers() public {
        assertSetReceiversReverts(
            user,
            dripsReceivers(receiver, 1, receiver, 2),
            "Duplicate drips receivers"
        );
    }

    function testSetDripsRevertsIfInvalidLastUpdate() public {
        setDrips(user, 0, 0, dripsReceivers(receiver, 1));
        assertSetDripsReverts(
            user,
            uint64(block.timestamp) + 1,
            0,
            dripsReceivers(receiver, 1),
            0,
            dripsReceivers(),
            "Invalid current drips configuration"
        );
    }

    function testSetDripsRevertsIfInvalidLastBalance() public {
        setDrips(user, 0, 1, dripsReceivers(receiver, 1));
        assertSetDripsReverts(
            user,
            uint64(block.timestamp),
            2,
            dripsReceivers(receiver, 1),
            0,
            dripsReceivers(),
            "Invalid current drips configuration"
        );
    }

    function testSetDripsRevertsIfInvalidCurrReceivers() public {
        setDrips(user, 0, 0, dripsReceivers(receiver, 1));
        assertSetDripsReverts(
            user,
            uint64(block.timestamp),
            0,
            dripsReceivers(receiver, 2),
            0,
            dripsReceivers(),
            "Invalid current drips configuration"
        );
    }

    function testAllowsAnAddressToDripAndReceiveIndependently() public {
        setDrips(user, 0, 10, dripsReceivers(user, 10));
        warpBy(1);
        // User had 1 second paying 10 per second
        assertDripsBalance(user, 0);
        warpToCycleEnd();
        // User had 1 second paying 10 per second
        collect(user, 10);
    }

    function testAllowsWithdrawalOfMoreThanDripsBalance() public {
        DripsReceiver[] memory receivers = dripsReceivers(receiver, 1);
        setDrips(user, 0, 10, receivers);
        uint64 lastUpdate = uint64(block.timestamp);
        warpBy(4);
        // User had 4 second paying 1 per second
        uint256 expectedBalance = user.balance(defaultAsset) + 6;
        (uint128 newBalance, int128 realBalanceDelta) = user.setDrips(
            defaultAsset,
            lastUpdate,
            10,
            receivers,
            type(int128).min,
            receivers
        );
        storeDrips(user, newBalance, receivers);
        assertEq(newBalance, 0, "Invalid balance");
        assertEq(realBalanceDelta, -6, "Invalid real balance delta");
        assertDripsBalance(user, 0);
        assertBalance(user, expectedBalance);
        warpToCycleEnd();
        // Receiver had 4 seconds paying 1 per second
        collect(receiver, 4);
    }

    function testAnybodyCanCallCollect() public {
        setDrips(user1, 0, 10, dripsReceivers(receiver, 10));
        warpToCycleEnd();
        // Receiver had 1 second paying 10 per second
        collect(user2, receiver, 10);
    }

    function testUserAndTheirAccountAreIndependent() public {
        setDrips(user, 0, 5, dripsReceivers(receiver1, 1));
        warpBy(3);
        setDrips(user, ACCOUNT_1, 0, 8, dripsReceivers(receiver1, 2, receiver2, 1));
        warpBy(1);
        // User had 4 seconds paying 1 per second
        changeBalance(user, 1, 0);
        warpBy(1);
        // User account1 had 2 seconds paying 3 per second
        changeBalance(user, ACCOUNT_1, 2, 0);
        warpToCycleEnd();
        // Receiver1 had 4 second paying 1 per second and 2 seconds paying 2 per second
        collect(receiver1, 8);
        // Receiver2 had 2 second paying 1 per second
        collect(receiver2, 2);
    }

    function testUserAccountsAreIndependent() public {
        setDrips(user, ACCOUNT_1, 0, 5, dripsReceivers(receiver1, 1));
        warpBy(3);
        setDrips(user, ACCOUNT_2, 0, 8, dripsReceivers(receiver1, 2, receiver2, 1));
        warpBy(1);
        // User account1 had 4 seconds paying 1 per second
        changeBalance(user, ACCOUNT_1, 1, 0);
        warpBy(1);
        // User account2 had 2 seconds paying 3 per second
        changeBalance(user, ACCOUNT_2, 2, 0);
        warpToCycleEnd();
        // Receiver1 had 4 second paying 1 per second and 2 seconds paying 2 per second
        collect(receiver1, 8);
        // Receiver2 had 2 second paying 1 per second
        collect(receiver2, 2);
    }

    function testAccountsOfDifferentUsersAreIndependent() public {
        setDrips(user1, ACCOUNT_1, 0, 5, dripsReceivers(receiver1, 1));
        warpBy(3);
        setDrips(user2, ACCOUNT_1, 0, 8, dripsReceivers(receiver1, 2, receiver2, 1));
        warpBy(1);
        // User1 account1 had 4 seconds paying 1 per second
        changeBalance(user1, ACCOUNT_1, 1, 0);
        warpBy(1);
        // User2 account1 had 2 seconds paying 3 per second
        changeBalance(user2, ACCOUNT_1, 2, 0);
        warpToCycleEnd();
        // Receiver1 had 4 second paying 1 per second and 2 seconds paying 2 per second
        collect(receiver1, 8);
        // Receiver2 had 2 second paying 1 per second
        collect(receiver2, 2);
    }

    function testLimitsTheTotalSplitsReceiversCount() public {
        uint160 countMax = dripsHub.MAX_SPLITS_RECEIVERS();
        SplitsReceiver[] memory receiversGood = new SplitsReceiver[](countMax);
        SplitsReceiver[] memory receiversBad = new SplitsReceiver[](countMax + 1);
        for (uint160 i = 0; i < countMax; i++) {
            receiversGood[i] = SplitsReceiver(address(i + 1), 1);
            receiversBad[i] = receiversGood[i];
        }
        receiversBad[countMax] = SplitsReceiver(address(countMax + 1), 1);

        setSplits(user, receiversGood);
        assertSetSplitsReverts(user, receiversBad, "Too many splits receivers");
    }

    function testRejectsTooHighTotalWeightSplitsReceivers() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setSplits(user, splitsReceivers(receiver, totalWeight));
        assertSetSplitsReverts(
            user,
            splitsReceivers(receiver, totalWeight + 1),
            "Splits weights sum too high"
        );
    }

    function testRejectsZeroWeightSplitsReceivers() public {
        assertSetSplitsReverts(
            user,
            splitsReceivers(receiver, 0),
            "Splits receiver weight is zero"
        );
    }

    function testRejectsUnsortedSplitsReceivers() public {
        assertSetSplitsReverts(
            user,
            splitsReceivers(receiver2, 1, receiver1, 1),
            "Splits receivers not sorted by address"
        );
    }

    function testRejectsDuplicateSplitsReceivers() public {
        assertSetSplitsReverts(
            user,
            splitsReceivers(receiver, 1, receiver, 2),
            "Duplicate splits receivers"
        );
    }

    function testCollectSplits() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setDrips(user, 0, 10, dripsReceivers(receiver1, 10));
        setSplits(receiver1, splitsReceivers(receiver2, totalWeight));
        warpToCycleEnd();
        assertCollectableAll(receiver2, 0);
        // Receiver1 had 1 second paying 10 per second of which 10 is split
        collect(receiver1, 0, 10);
        // Receiver2 got 10 split from receiver1
        collect(receiver2, 10);
    }

    function testUncollectedFundsAreSplitUsingCurrentConfig() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setSplits(user1, splitsReceivers(receiver1, totalWeight));
        setDrips(user2, 0, 5, dripsReceivers(user1, 5));
        warpToCycleEnd();
        give(user2, user1, 5);
        setSplits(user1, splitsReceivers(receiver2, totalWeight));
        // Receiver1 had 1 second paying 5 per second and was given 5 of which 10 is split
        collect(user1, 0, 10);
        // Receiver1 wasn't a splits receiver when user1 was collecting
        assertCollectableAll(receiver1, 0);
        // Receiver2 was a splits receiver when user1 was collecting
        collect(receiver2, 10);
    }

    function testCollectSplitsFundsFromSplits() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setDrips(user, 0, 10, dripsReceivers(receiver1, 10));
        setSplits(receiver1, splitsReceivers(receiver2, totalWeight));
        setSplits(receiver2, splitsReceivers(receiver3, totalWeight));
        warpToCycleEnd();
        assertCollectableAll(receiver2, 0);
        assertCollectableAll(receiver3, 0);
        // Receiver1 had 1 second paying 10 per second of which 10 is split
        collect(receiver1, 0, 10);
        // Receiver2 got 10 split from receiver1 of which 10 is split
        collect(receiver2, 0, 10);
        // Receiver3 got 10 split from receiver2
        collect(receiver3, 10);
    }

    function testCollectMixesDripsAndSplits() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setDrips(user, 0, 10, dripsReceivers(receiver1, 5, receiver2, 5));
        setSplits(receiver1, splitsReceivers(receiver2, totalWeight));
        warpToCycleEnd();
        // Receiver2 had 1 second paying 5 per second
        assertCollectableAll(receiver2, 5);
        // Receiver1 had 1 second paying 5 per second
        collect(receiver1, 0, 5);
        // Receiver2 had 1 second paying 5 per second and got 5 split from receiver1
        collect(receiver2, 10);
    }

    function testCollectSplitsFundsBetweenReceiverAndSplits() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setDrips(user, 0, 10, dripsReceivers(receiver1, 10));
        setSplits(
            receiver1,
            splitsReceivers(receiver2, totalWeight / 4, receiver3, totalWeight / 2)
        );
        warpToCycleEnd();
        assertCollectableAll(receiver2, 0);
        assertCollectableAll(receiver3, 0);
        // Receiver1 had 1 second paying 10 per second, of which 3/4 is split, which is 7
        collect(receiver1, 3, 7);
        // Receiver2 got 1/3 of 7 split from receiver1, which is 2
        collect(receiver2, 2);
        // Receiver3 got 2/3 of 7 split from receiver1, which is 5
        collect(receiver3, 5);
    }

    function testCanSplitAllWhenCollectedDoesntSplitEvenly() public {
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setDrips(user, 0, 3, dripsReceivers(receiver1, 3));
        setSplits(
            receiver1,
            splitsReceivers(receiver2, totalWeight / 2, receiver3, totalWeight / 2)
        );
        warpToCycleEnd();
        // Receiver1 had 1 second paying 3 per second of which 3 is split
        collect(receiver1, 0, 3);
        // Receiver2 got 1 split from receiver
        collect(receiver2, 1);
        // Receiver3 got 2 split from receiver
        collect(receiver3, 2);
    }

    function testFlushSomeCycles() public {
        // Enough for 3 cycles
        uint128 amt = dripsHub.cycleSecs() * 3;
        warpToCycleEnd();
        setDrips(user, 0, amt, dripsReceivers(receiver, 1));
        warpToCycleEnd();
        warpToCycleEnd();
        warpToCycleEnd();
        flushCycles(receiver, 3, 2, 1);
        collect(receiver, amt);
    }

    function testFlushAllCycles() public {
        // Enough for 3 cycles
        uint128 amt = dripsHub.cycleSecs() * 3;
        warpToCycleEnd();
        setDrips(user, 0, amt, dripsReceivers(receiver, 1));
        warpToCycleEnd();
        warpToCycleEnd();
        warpToCycleEnd();
        flushCycles(receiver, 3, type(uint64).max, 0);
        collect(receiver, amt);
    }

    function testFundsGivenFromUserCanBeCollected() public {
        give(user, receiver, 10);
        collect(receiver, 10);
    }

    function testFundsGivenFromAccountCanBeCollected() public {
        give(user, ACCOUNT_1, receiver, 10);
        collect(receiver, 10);
    }
}
