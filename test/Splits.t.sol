// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Splits, SplitsReceiver} from "src/Splits.sol";

contract SplitsTest is Test, Splits {
    bytes internal constant ERROR_NOT_SORTED = "Splits receivers not sorted";

    // Keys is user ID
    mapping(uint256 => SplitsReceiver[]) internal currSplitsReceivers;

    uint256 internal asset = defaultAsset;
    uint256 internal defaultAsset = 1;
    uint256 internal otherAsset = 2;
    uint256 internal user = 3;
    uint256 internal receiver = 4;
    uint256 internal receiver1 = 5;
    uint256 internal receiver2 = 6;

    constructor() Splits(bytes32(uint256(1000))) {
        return;
    }

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

    function splitsReceivers(uint256 user1, uint32 weight1, uint256 user2, uint32 weight2)
        internal
        pure
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](2);
        list[0] = SplitsReceiver(user1, weight1);
        list[1] = SplitsReceiver(user2, weight2);
    }

    function getCurrSplitsReceivers(uint256 userId)
        internal
        view
        returns (SplitsReceiver[] memory currSplits)
    {
        currSplits = currSplitsReceivers[userId];
        assertSplits(userId, currSplits);
    }

    function setSplitsExternal(uint256 userId, SplitsReceiver[] memory newReceivers) external {
        Splits._setSplits(userId, newReceivers);
    }

    function assertSetSplitsReverts(
        uint256 userId,
        SplitsReceiver[] memory newReceivers,
        bytes memory expectedReason
    ) internal {
        vm.expectRevert(expectedReason);
        this.setSplitsExternal(userId, newReceivers);
    }

    function assertSplits(uint256 userId, SplitsReceiver[] memory expectedReceivers)
        internal
        view
    {
        Splits._assertCurrSplits(userId, expectedReceivers);
    }

    function assertSplittable(uint256 userId, uint256 expected) internal {
        uint256 actual = Splits._splittable(userId, asset);
        assertEq(actual, expected, "Invalid splittable");
    }

    function setSplits(uint256 userId, SplitsReceiver[] memory newReceivers) internal {
        assertSplits(userId, currSplitsReceivers[userId]);
        Splits._setSplits(userId, newReceivers);
        assertSplits(userId, newReceivers);
        delete currSplitsReceivers[userId];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currSplitsReceivers[userId].push(newReceivers[i]);
        }
    }

    function splitExternal(uint256 userId, uint256 assetId, SplitsReceiver[] memory currReceivers)
        external
    {
        Splits._split(userId, assetId, currReceivers);
    }

    function split(uint256 userId, uint128 expectedCollectable, uint128 expectedSplit) internal {
        assertCollectable(userId, 0);
        assertSplittable(userId, expectedCollectable + expectedSplit);
        SplitsReceiver[] memory receivers = getCurrSplitsReceivers(userId);
        uint128 amt = Splits._splittable(userId, asset);
        (uint128 collectableRes, uint128 splitRes) = Splits._splitResult(userId, receivers, amt);
        assertEq(collectableRes, expectedCollectable, "Invalid result collectable amount");
        assertEq(splitRes, expectedSplit, "Invalid result split amount");

        (uint128 collectableAmt, uint128 splitAmt) = Splits._split(userId, asset, receivers);

        assertEq(collectableAmt, expectedCollectable, "Invalid collectable amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertCollectable(userId, expectedCollectable);
        assertSplittable(userId, 0);
    }

    function addSplittable(uint256 userId, uint128 amt) internal {
        assertSplittable(userId, 0);
        Splits._addSplittable(userId, asset, amt);
        assertSplittable(userId, amt);
    }

    function assertCollectable(uint256 userId, uint128 expected) internal {
        uint128 actual = Splits._collectable(userId, asset);
        assertEq(actual, expected, "Invalid collectable amount");
    }

    function collect(uint256 userId, uint128 expectedAmt) internal {
        assertCollectable(userId, expectedAmt);
        uint128 actualAmt = Splits._collect(userId, asset);
        assertEq(actualAmt, expectedAmt, "Invalid collected amount");
    }

    function splitCollect(uint256 userId, uint128 expectedCollected, uint128 expectedSplit)
        internal
    {
        split(userId, expectedCollected, expectedSplit);
        collect(userId, expectedCollected);
    }

    function testGive() public {
        Splits._give(user, receiver, asset, 5);
        assertSplittable(receiver, 5);
    }

    function testSimpleSplit() public {
        // 60% split
        setSplits(user, splitsReceivers(receiver, (Splits._TOTAL_SPLITS_WEIGHT / 10) * 6));
        addSplittable(user, 10);
        split(user, 4, 6);
    }

    function testLimitsTheTotalSplitsReceiversCount() public {
        uint256 countMax = Splits._MAX_SPLITS_RECEIVERS;
        SplitsReceiver[] memory receiversGood = new SplitsReceiver[](countMax);
        SplitsReceiver[] memory receiversBad = new SplitsReceiver[](countMax + 1);
        for (uint256 i = 0; i < countMax; i++) {
            receiversGood[i] = SplitsReceiver(i, 1);
            receiversBad[i] = receiversGood[i];
        }
        receiversBad[countMax] = SplitsReceiver(countMax, 1);

        setSplits(user, receiversGood);
        assertSetSplitsReverts(user, receiversBad, "Too many splits receivers");
    }

    function testRejectsTooHighTotalWeightSplitsReceivers() public {
        uint32 totalWeight = Splits._TOTAL_SPLITS_WEIGHT;
        setSplits(user, splitsReceivers(receiver, totalWeight));
        assertSetSplitsReverts(
            user, splitsReceivers(receiver, totalWeight + 1), "Splits weights sum too high"
        );
    }

    function testRejectsZeroWeightSplitsReceivers() public {
        assertSetSplitsReverts(user, splitsReceivers(receiver, 0), "Splits receiver weight is zero");
    }

    function testRejectsUnsortedSplitsReceivers() public {
        assertSetSplitsReverts(user, splitsReceivers(receiver2, 1, receiver1, 1), ERROR_NOT_SORTED);
    }

    function testRejectsDuplicateSplitsReceivers() public {
        assertSetSplitsReverts(user, splitsReceivers(receiver, 1, receiver, 2), ERROR_NOT_SORTED);
    }

    function testCanSplitAllWhenCollectedDoesNotSplitEvenly() public {
        uint32 totalWeight = Splits._TOTAL_SPLITS_WEIGHT;
        // 3 waiting for user
        addSplittable(user, 3);

        setSplits(user, splitsReceivers(receiver1, totalWeight / 2, receiver2, totalWeight / 2));

        // User received 3 which 100% is split
        split(user, 0, 3);
        // Receiver1 got 1 split from user
        split(receiver1, 1, 0);
        // Receiver2 got 2 split from user
        split(receiver2, 2, 0);
    }

    function testSplitRevertsIfInvalidCurrSplitsReceivers() public {
        setSplits(user, splitsReceivers(receiver, 1));
        vm.expectRevert("Invalid current splits receivers");
        this.splitExternal(user, asset, splitsReceivers(receiver, 2));
    }

    function testSplittingSplitsAllFundsEvenWhenTheyDoNotDivideEvenly() public {
        uint32 totalWeight = Splits._TOTAL_SPLITS_WEIGHT;
        setSplits(
            user, splitsReceivers(receiver1, (totalWeight / 5) * 2, receiver2, totalWeight / 5)
        );
        addSplittable(user, 9);
        // user gets 40% of 9, receiver1 40 % and receiver2 20%
        split(user, 4, 5);
        split(receiver1, 3, 0);
        split(receiver2, 2, 0);
    }

    function testUserCanSplitToThemselves() public {
        uint32 totalWeight = Splits._TOTAL_SPLITS_WEIGHT;
        // receiver1 receives 30%, gets 50% split to themselves and receiver2 gets split 20%
        setSplits(
            receiver1, splitsReceivers(receiver1, totalWeight / 2, receiver2, totalWeight / 5)
        );
        addSplittable(receiver1, 20);

        (uint128 collectableAmt, uint128 splitAmt) =
            Splits._split(receiver1, asset, getCurrSplitsReceivers(receiver1));

        assertEq(collectableAmt, 6, "Invalid collectable amount");
        assertEq(splitAmt, 14, "Invalid split amount");

        assertSplittable(receiver1, 10);
        collect(receiver1, 6);
        splitCollect(receiver2, 4, 0);

        // Splitting 10 which has been split to receiver1 themselves in the previous step
        (collectableAmt, splitAmt) =
            Splits._split(receiver1, asset, getCurrSplitsReceivers(receiver1));

        assertEq(collectableAmt, 3, "Invalid collectable amount");
        assertEq(splitAmt, 7, "Invalid split amount");
        assertSplittable(receiver1, 5);
        collect(receiver1, 3);
        split(receiver2, 2, 0);
    }

    function testSplitsConfigurationIsCommonBetweenTokens() public {
        uint32 totalWeight = Splits._TOTAL_SPLITS_WEIGHT;
        setSplits(user, splitsReceivers(receiver1, totalWeight / 10));
        asset = defaultAsset;
        addSplittable(user, 30);
        asset = otherAsset;
        addSplittable(user, 100);

        asset = defaultAsset;
        splitCollect(user, 27, 3);
        asset = otherAsset;
        splitCollect(user, 90, 10);
        asset = defaultAsset;
        splitCollect(receiver1, 3, 0);
        asset = otherAsset;
        splitCollect(receiver1, 10, 0);
    }

    function testForwardSplits() public {
        uint32 totalWeight = Splits._TOTAL_SPLITS_WEIGHT;

        addSplittable(user, 10);
        setSplits(user, splitsReceivers(receiver1, totalWeight));
        setSplits(receiver1, splitsReceivers(receiver2, totalWeight));

        assertSplittable(receiver1, 0);
        assertSplittable(receiver2, 0);
        // User has splittable 10 of which 10 is split
        splitCollect(user, 0, 10);
        // Receiver1 got 10 split from user of which 10 is split
        splitCollect(receiver1, 0, 10);
        // Receiver2 got 10 split from receiver1
        splitCollect(receiver2, 10, 0);
    }

    function testSplitMultipleReceivers() public {
        uint32 totalWeight = Splits._TOTAL_SPLITS_WEIGHT;
        addSplittable(user, 10);

        setSplits(user, splitsReceivers(receiver1, totalWeight / 4, receiver2, totalWeight / 2));
        assertSplittable(receiver1, 0);
        assertSplittable(receiver2, 0);
        // User has splittable 10, of which 3/4 is split, which is 7
        splitCollect(user, 3, 7);
        // Receiver1 got 1/3 of 7 split from user, which is 2
        splitCollect(receiver1, 2, 0);
        // Receiver2 got 2/3 of 7 split from user, which is 5
        splitCollect(receiver2, 5, 0);
    }

    function sanitizeReceivers(
        SplitsReceiver[_MAX_SPLITS_RECEIVERS] memory receiversRaw,
        uint256 receiversLengthRaw,
        uint256 totalWeightRaw
    ) internal view returns (SplitsReceiver[] memory receivers) {
        for (uint256 i = 0; i < receiversRaw.length; i++) {
            for (uint256 j = i + 1; j < receiversRaw.length; j++) {
                if (receiversRaw[i].userId > receiversRaw[j].userId) {
                    (receiversRaw[i], receiversRaw[j]) = (receiversRaw[j], receiversRaw[i]);
                }
            }
        }
        uint256 unique = 0;
        for (uint256 i = 1; i < receiversRaw.length; i++) {
            if (receiversRaw[i].userId != receiversRaw[unique].userId) unique++;
            receiversRaw[unique] = receiversRaw[i];
        }
        receivers = new SplitsReceiver[](bound(receiversLengthRaw, 0, unique));
        uint256 weightSum = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            receivers[i] = receiversRaw[i];
            weightSum += receivers[i].weight;
        }
        if (weightSum == 0) weightSum = 1;
        uint256 totalWeight = bound(totalWeightRaw, 0, (_TOTAL_SPLITS_WEIGHT - receivers.length));
        uint256 usedWeight = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            uint256 usedTotalWeight = totalWeight * usedWeight / weightSum;
            usedWeight += receivers[i].weight;
            receivers[i].weight =
                uint32((totalWeight * usedWeight / weightSum) - usedTotalWeight + 1);
        }
    }

    function testSplitFundsAddUp(
        uint256 userId,
        uint256 assetId,
        uint128 amt,
        SplitsReceiver[_MAX_SPLITS_RECEIVERS] memory receiversRaw,
        uint256 receiversLengthRaw,
        uint256 totalWeightRaw
    ) public {
        SplitsReceiver[] memory receivers =
            sanitizeReceivers(receiversRaw, receiversLengthRaw, totalWeightRaw);
        Splits._addSplittable(userId, assetId, amt);
        Splits._setSplits(userId, receivers);
        (uint128 collectableAmt, uint128 splitAmt) = Splits._split(userId, assetId, receivers);
        assertEq(collectableAmt + splitAmt, amt, "Invalid split results");
        uint128 collectedAmt = Splits._collect(userId, assetId);
        assertEq(collectedAmt, collectableAmt, "Invalid collected amount");
        uint256 splitSum = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            splitSum += Splits._splittable(receivers[i].userId, assetId);
        }
        assertEq(splitSum, splitAmt, "Invalid split amount");
    }
}
