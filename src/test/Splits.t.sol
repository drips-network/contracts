// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {DSTest} from "ds-test/test.sol";
import {Hevm} from "./Hevm.t.sol";
import {Splits, SplitsReceiver} from "../Splits.sol";

contract SplitsTest is DSTest {
    Splits.Storage internal s;
    // Keys is user ID
    mapping(uint256 => SplitsReceiver[]) internal currSplitsReceivers;

    uint256 internal defaultAsset = 1;
    uint256 internal otherAsset = 2;
    uint256 internal receiver = 4;
    uint256 internal receiver1 = 5;
    uint256 internal receiver2 = 6;
    uint256 internal receiver3 = 7;
    uint256 internal receiver4 = 8;
    uint256 internal user = 9;

    function splitsReceivers() internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](0);
    }

    function splitsReceivers(uint256 userId, uint32 weight)
        internal
        pure
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](1);
        list[0] = SplitsReceiver(userId, weight);
    }

    function splitsReceivers(
        uint256 user1,
        uint32 weight1,
        uint256 user2,
        uint32 weight2
    ) internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](2);
        list[0] = SplitsReceiver(user1, weight1);
        list[1] = SplitsReceiver(user2, weight2);
    }

    function getCurrSplitsReceivers(uint256 userId)
        internal
        returns (SplitsReceiver[] memory currSplits)
    {
        currSplits = currSplitsReceivers[userId];

        Splits.assertCurrSplits(s, userId, currSplits);
    }

    function setSplitsExternal(uint256 userId, SplitsReceiver[] memory newReceivers) external {
        Splits.setSplits(s, userId, newReceivers);
    }

    function assertSetSplitsReverts(
        uint256 userId,
        SplitsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(userId);
        Splits.assertCurrSplits(s, userId, curr);
        try this.setSplitsExternal(userId, newReceivers) {
            assertTrue(false, "setSplits hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid setSplits revert reason");
        }
    }

    function assertSplits(uint256 userId, SplitsReceiver[] memory expectedReceivers) internal view {
        Splits.assertCurrSplits(s, userId, expectedReceivers);
    }

    function assertSplittable(uint256 userId, uint256 expected) internal {
        uint256 actual = Splits.splittable(s, userId, defaultAsset);
        assertEq(actual, expected, "Invalid splittable");
    }

    function setSplits(uint256 userId, SplitsReceiver[] memory newReceivers) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(userId);
        assertSplits(userId, curr);

        Splits.setSplits(s, userId, newReceivers);

        setCurrSplitsReceivers(userId, newReceivers);
    }

    function setCurrSplitsReceivers(uint256 userId, SplitsReceiver[] memory newReceivers) internal {
        assertSplits(userId, newReceivers);
        delete currSplitsReceivers[userId];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currSplitsReceivers[userId].push(newReceivers[i]);
        }
    }

    function split(
        uint256 userId,
        uint128 expectedCollectable,
        uint128 expectedSplit
    ) internal {
        (uint128 collectableAmt, uint128 splitAmt) = Splits.split(
            s,
            userId,
            defaultAsset,
            getCurrSplitsReceivers(userId)
        );

        assertEq(collectableAmt, expectedCollectable, "Invalid collectable amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertSplittable(userId, 0);
    }

    // test cases
    function testSplitable() public {
        uint128 amt = 10;
        Splits.give(s, 0, user, defaultAsset, amt);
        assertSplittable(user, amt);
    }

    function testSimpleSplit() public {
        // 60% split
        setSplits(user, splitsReceivers(receiver, (Splits.TOTAL_SPLITS_WEIGHT / 10) * 6));
        uint128 amt = 10;
        Splits.give(s, 0, user, defaultAsset, amt);
        assertSplittable(user, amt);

        uint128 expectedCollectable = 4;
        uint128 expectedSplit = 6;
        split(user, expectedCollectable, expectedSplit);
    }

    function testLimitsTheTotalSplitsReceiversCount() public {
        uint160 countMax = Splits.MAX_SPLITS_RECEIVERS;
        SplitsReceiver[] memory receiversGood = new SplitsReceiver[](countMax);
        SplitsReceiver[] memory receiversBad = new SplitsReceiver[](countMax + 1);
        for (uint160 i = 0; i < countMax; i++) {
            receiversGood[i] = SplitsReceiver(i, 1);
            receiversBad[i] = receiversGood[i];
        }
        receiversBad[countMax] = SplitsReceiver(countMax, 1);

        setSplits(user, receiversGood);
        assertSetSplitsReverts(user, receiversBad, "Too many splits receivers");
    }

    function testRejectsTooHighTotalWeightSplitsReceivers() public {
        uint32 totalWeight = Splits.TOTAL_SPLITS_WEIGHT;
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
            "Splits receivers not sorted by user ID"
        );
    }

    function testRejectsDuplicateSplitsReceivers() public {
        assertSetSplitsReverts(
            user,
            splitsReceivers(receiver, 1, receiver, 2),
            "Duplicate splits receivers"
        );
    }

    function testCanSplitAllWhenCollectedDoesntSplitEvenly() public {
        uint32 totalWeight = Splits.TOTAL_SPLITS_WEIGHT;
        // 3 waiting for receiver 1
        Splits.give(s, user, receiver1, defaultAsset, 3);

        setSplits(
            receiver1,
            splitsReceivers(receiver2, totalWeight / 2, receiver3, totalWeight / 2)
        );

        // Receiver1 received 3 which 100% is split
        split(receiver1, 0, 3);
        // Receiver2 got 1 split from receiver
        split(receiver2, 1, 0);
        // Receiver3 got 2 split from receiver
        split(receiver3, 2, 0);
    }
}
