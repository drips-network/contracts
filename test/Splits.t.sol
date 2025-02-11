// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {console, Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Splits, SplitsReceiver} from "src/Splits.sol";

contract SplitsWrapper is Splits {
    uint256 public constant MAX_SPLITS_RECEIVERS = Splits._MAX_SPLITS_RECEIVERS;
    uint32 public constant TOTAL_SPLITS_WEIGHT = Splits._TOTAL_SPLITS_WEIGHT;
    uint128 public constant MAX_SPLITS_BALANCE = Splits._MAX_SPLITS_BALANCE;

    constructor(bytes32 splitsStorageSlot) Splits(splitsStorageSlot) {}

    function addSplittable(uint256 accountId, IERC20 erc20, uint128 amt) public {
        _addSplittable(accountId, erc20, amt);
    }

    function splittable(uint256 accountId, IERC20 erc20) public view returns (uint128 amt) {
        return _splittable(accountId, erc20);
    }

    function splitResult(uint256 accountId, SplitsReceiver[] memory currReceivers, uint128 amount)
        public
        view
        returns (uint128 collectableAmt, uint128 splitAmt)
    {
        return _splitResult(accountId, currReceivers, amount);
    }

    function split(uint256 accountId, IERC20 erc20, SplitsReceiver[] memory currReceivers)
        public
        returns (uint128 collectableAmt, uint128 splitAmt)
    {
        return _split(accountId, erc20, currReceivers);
    }

    function collectable(uint256 accountId, IERC20 erc20) public view returns (uint128 amt) {
        return _collectable(accountId, erc20);
    }

    function collect(uint256 accountId, IERC20 erc20) public returns (uint128 amt) {
        return _collect(accountId, erc20);
    }

    function give(uint256 accountId, uint256 receiver, IERC20 erc20, uint128 amt) public {
        _give(accountId, receiver, erc20, amt);
    }

    function setSplits(uint256 accountId, SplitsReceiver[] memory receivers) public {
        _setSplits(accountId, receivers);
    }

    function assertCurrSplits(uint256 accountId, SplitsReceiver[] memory currReceivers)
        public
        view
    {
        _assertCurrSplits(accountId, currReceivers);
    }

    function splitsHash(uint256 accountId) public view returns (bytes32 currSplitsHash) {
        return _splitsHash(accountId);
    }

    function hashSplits(SplitsReceiver[] memory receivers)
        public
        pure
        returns (bytes32 receiversHash)
    {
        return _hashSplits(receivers);
    }
}

contract SplitsTest is Test {
    bytes internal constant ERROR_NOT_SORTED = "Splits receivers not sorted";

    SplitsWrapper internal splits;
    uint256 internal constant MAX_SPLITS_RECEIVERS = 200;
    uint32 internal totalSplitsWeight;

    mapping(uint256 accountId => SplitsReceiver[]) internal currSplitsReceivers;

    // The ERC-20 token used in all helper functions
    IERC20 internal erc20 = defaultErc20;
    IERC20 internal defaultErc20 = IERC20(address(bytes20("defaultErc20")));
    IERC20 internal otherErc20 = IERC20(address(bytes20("otherErc20")));
    uint256 internal immutable accountId = 3;
    uint256 internal immutable receiver = 4;
    uint256 internal immutable receiver1 = 5;
    uint256 internal immutable receiver2 = 6;

    function setUp() public {
        splits = new SplitsWrapper(bytes32(uint256(1000)));
        assertEq(
            MAX_SPLITS_RECEIVERS, splits.MAX_SPLITS_RECEIVERS(), "Invalid MAX_SPLITS_RECEIVERS"
        );
        totalSplitsWeight = splits.TOTAL_SPLITS_WEIGHT();
    }

    function splitsReceivers() internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](0);
    }

    function splitsReceivers(uint256 usedAccountId, uint32 weight)
        internal
        pure
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](1);
        list[0] = SplitsReceiver(usedAccountId, weight);
    }

    function splitsReceivers(uint256 account1, uint32 weight1, uint256 account2, uint32 weight2)
        internal
        pure
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](2);
        list[0] = SplitsReceiver(account1, weight1);
        list[1] = SplitsReceiver(account2, weight2);
    }

    function getCurrSplitsReceivers(uint256 usedAccountId)
        internal
        view
        returns (SplitsReceiver[] memory currSplits)
    {
        currSplits = currSplitsReceivers[usedAccountId];
        assertSplits(usedAccountId, currSplits);
    }

    function assertSplits(uint256 usedAccountId, SplitsReceiver[] memory expectedReceivers)
        internal
        view
    {
        splits.assertCurrSplits(usedAccountId, expectedReceivers);
    }

    function assertSplittable(uint256 usedAccountId, uint256 expected) internal view {
        uint256 actual = splits.splittable(usedAccountId, erc20);
        assertEq(actual, expected, "Invalid splittable");
    }

    function setSplits(uint256 usedAccountId, SplitsReceiver[] memory newReceivers) internal {
        assertSplits(usedAccountId, currSplitsReceivers[usedAccountId]);
        splits.setSplits(usedAccountId, newReceivers);
        assertSplits(usedAccountId, newReceivers);
        delete currSplitsReceivers[usedAccountId];
        for (uint256 i = 0; i < newReceivers.length; i++) {
            currSplitsReceivers[usedAccountId].push(newReceivers[i]);
        }
    }

    function split(uint256 usedAccountId, uint128 expectedCollectable, uint128 expectedSplit)
        internal
    {
        assertCollectable(usedAccountId, 0);
        assertSplittable(usedAccountId, expectedCollectable + expectedSplit);
        SplitsReceiver[] memory receivers = getCurrSplitsReceivers(usedAccountId);
        uint128 amt = splits.splittable(usedAccountId, erc20);
        (uint128 collectableRes, uint128 splitRes) =
            splits.splitResult(usedAccountId, receivers, amt);
        assertEq(collectableRes, expectedCollectable, "Invalid result collectable amount");
        assertEq(splitRes, expectedSplit, "Invalid result split amount");

        (uint128 collectableAmt, uint128 splitAmt) = splits.split(usedAccountId, erc20, receivers);

        assertEq(collectableAmt, expectedCollectable, "Invalid collectable amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertCollectable(usedAccountId, expectedCollectable);
        assertSplittable(usedAccountId, 0);
    }

    function addSplittable(uint256 usedAccountId, uint128 amt) internal {
        assertSplittable(usedAccountId, 0);
        splits.addSplittable(usedAccountId, erc20, amt);
        assertSplittable(usedAccountId, amt);
    }

    function assertCollectable(uint256 usedAccountId, uint128 expected) internal view {
        uint128 actual = splits.collectable(usedAccountId, erc20);
        assertEq(actual, expected, "Invalid collectable amount");
    }

    function collect(uint256 usedAccountId, uint128 expectedAmt) internal {
        assertCollectable(usedAccountId, expectedAmt);
        uint128 actualAmt = splits.collect(usedAccountId, erc20);
        assertEq(actualAmt, expectedAmt, "Invalid collected amount");
    }

    function splitCollect(uint256 usedAccountId, uint128 expectedCollected, uint128 expectedSplit)
        internal
    {
        split(usedAccountId, expectedCollected, expectedSplit);
        collect(usedAccountId, expectedCollected);
    }

    function testGive() public {
        splits.give(accountId, receiver, erc20, 5);
        assertSplittable(receiver, 5);
    }

    function testSimpleSplit() public {
        // 60% split
        setSplits(accountId, splitsReceivers(receiver, (splits.TOTAL_SPLITS_WEIGHT() / 10) * 6));
        addSplittable(accountId, 10);
        split(accountId, 4, 6);
    }

    function testLimitsTheTotalSplitsReceiversCount() public {
        SplitsReceiver[] memory receiversGood = new SplitsReceiver[](MAX_SPLITS_RECEIVERS);
        SplitsReceiver[] memory receiversBad = new SplitsReceiver[](MAX_SPLITS_RECEIVERS + 1);
        for (uint256 i = 0; i < MAX_SPLITS_RECEIVERS; i++) {
            receiversGood[i] = SplitsReceiver(i, 1);
            receiversBad[i] = receiversGood[i];
        }
        receiversBad[MAX_SPLITS_RECEIVERS] = SplitsReceiver(MAX_SPLITS_RECEIVERS, 1);

        setSplits(accountId, receiversGood);
        vm.expectRevert("Too many splits receivers");
        splits.setSplits(accountId, receiversBad);
    }

    function testBenchSplitMaxReceivers() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](MAX_SPLITS_RECEIVERS);
        for (uint256 i = 0; i < receivers.length; i++) {
            receivers[i] = SplitsReceiver(i, 1);
        }
        setSplits(accountId, receivers);
        addSplittable(accountId, totalSplitsWeight);
        uint256 gas = gasleft();

        splits.split(accountId, erc20, receivers);

        gas -= gasleft();
        console.log("Gas used ", gas);
    }

    function testRejectsTooHighTotalWeightSplitsReceivers() public {
        setSplits(accountId, splitsReceivers(receiver, totalSplitsWeight));
        vm.expectRevert("Splits weights sum too high");
        splits.setSplits(accountId, splitsReceivers(receiver, totalSplitsWeight + 1));
    }

    function testRejectsZeroWeightSplitsReceivers() public {
        vm.expectRevert("Splits receiver weight is zero");
        splits.setSplits(accountId, splitsReceivers(receiver, 0));
    }

    function testRejectsUnsortedSplitsReceivers() public {
        vm.expectRevert(ERROR_NOT_SORTED);
        splits.setSplits(accountId, splitsReceivers(receiver2, 1, receiver1, 1));
    }

    function testRejectsDuplicateSplitsReceivers() public {
        vm.expectRevert(ERROR_NOT_SORTED);
        splits.setSplits(accountId, splitsReceivers(receiver, 1, receiver, 2));
    }

    function testCanSplitAllWhenCollectedDoesNotSplitEvenly() public {
        // 3 waiting for accountId
        addSplittable(accountId, 3);

        setSplits(
            accountId,
            splitsReceivers(receiver1, totalSplitsWeight / 2, receiver2, totalSplitsWeight / 2)
        );

        // Account received 3 which 100% is split
        split(accountId, 0, 3);
        // Receiver1 got 1 split from accountId
        split(receiver1, 1, 0);
        // Receiver2 got 2 split from accountId
        split(receiver2, 2, 0);
    }

    function testSplitRevertsIfInvalidCurrSplitsReceivers() public {
        setSplits(accountId, splitsReceivers(receiver, 1));
        vm.expectRevert("Invalid current splits receivers");
        splits.split(accountId, erc20, splitsReceivers(receiver, 2));
    }

    function testSplittingSplitsAllFundsEvenWhenTheyDoNotDivideEvenly() public {
        setSplits(
            accountId,
            splitsReceivers(
                receiver1, (totalSplitsWeight / 5) * 2, receiver2, totalSplitsWeight / 5
            )
        );
        addSplittable(accountId, 9);
        // accountId gets 40% of 9, receiver1 40 % and receiver2 20%
        split(accountId, 4, 5);
        split(receiver1, 3, 0);
        split(receiver2, 2, 0);
    }

    function testAccountCanSplitToItself() public {
        // receiver1 receives 30%, gets 50% split to themselves and receiver2 gets split 20%
        setSplits(
            receiver1,
            splitsReceivers(receiver1, totalSplitsWeight / 2, receiver2, totalSplitsWeight / 5)
        );
        addSplittable(receiver1, 20);

        (uint128 collectableAmt, uint128 splitAmt) =
            splits.split(receiver1, erc20, getCurrSplitsReceivers(receiver1));

        assertEq(collectableAmt, 6, "Invalid collectable amount");
        assertEq(splitAmt, 14, "Invalid split amount");

        assertSplittable(receiver1, 10);
        collect(receiver1, 6);
        splitCollect(receiver2, 4, 0);

        // Splitting 10 which has been split to receiver1 themselves in the previous step
        (collectableAmt, splitAmt) =
            splits.split(receiver1, erc20, getCurrSplitsReceivers(receiver1));

        assertEq(collectableAmt, 3, "Invalid collectable amount");
        assertEq(splitAmt, 7, "Invalid split amount");
        assertSplittable(receiver1, 5);
        collect(receiver1, 3);
        split(receiver2, 2, 0);
    }

    function testSplitsConfigurationIsCommonBetweenTokens() public {
        setSplits(accountId, splitsReceivers(receiver1, totalSplitsWeight / 10));
        erc20 = defaultErc20;
        addSplittable(accountId, 30);
        erc20 = otherErc20;
        addSplittable(accountId, 100);

        erc20 = defaultErc20;
        splitCollect(accountId, 27, 3);
        erc20 = otherErc20;
        splitCollect(accountId, 90, 10);
        erc20 = defaultErc20;
        splitCollect(receiver1, 3, 0);
        erc20 = otherErc20;
        splitCollect(receiver1, 10, 0);
    }

    function testForwardSplits() public {
        addSplittable(accountId, 10);
        setSplits(accountId, splitsReceivers(receiver1, totalSplitsWeight));
        setSplits(receiver1, splitsReceivers(receiver2, totalSplitsWeight));

        assertSplittable(receiver1, 0);
        assertSplittable(receiver2, 0);
        // Account has splittable 10 of which 10 is split
        splitCollect(accountId, 0, 10);
        // Receiver1 got 10 split from accountId of which 10 is split
        splitCollect(receiver1, 0, 10);
        // Receiver2 got 10 split from receiver1
        splitCollect(receiver2, 10, 0);
    }

    function testSplitMultipleReceivers() public {
        addSplittable(accountId, 10);

        setSplits(
            accountId,
            splitsReceivers(receiver1, totalSplitsWeight / 4, receiver2, totalSplitsWeight / 2)
        );
        assertSplittable(receiver1, 0);
        assertSplittable(receiver2, 0);
        // Account has splittable 10, of which 3/4 is split, which is 7
        splitCollect(accountId, 3, 7);
        // Receiver1 got 1/3 of 7 split from accountId, which is 2
        splitCollect(receiver1, 2, 0);
        // Receiver2 got 2/3 of 7 split from accountId, which is 5
        splitCollect(receiver2, 5, 0);
    }

    function sanitizeReceivers(
        SplitsReceiver[MAX_SPLITS_RECEIVERS] memory receiversRaw,
        uint256 receiversLengthRaw,
        uint256 totalWeightRaw
    ) internal view returns (SplitsReceiver[] memory receivers) {
        for (uint256 i = 0; i < receiversRaw.length; i++) {
            for (uint256 j = i + 1; j < receiversRaw.length; j++) {
                if (receiversRaw[i].accountId > receiversRaw[j].accountId) {
                    (receiversRaw[i], receiversRaw[j]) = (receiversRaw[j], receiversRaw[i]);
                }
            }
        }
        uint256 unique = 0;
        for (uint256 i = 1; i < receiversRaw.length; i++) {
            if (receiversRaw[i].accountId != receiversRaw[unique].accountId) unique++;
            receiversRaw[unique] = receiversRaw[i];
        }
        receivers = new SplitsReceiver[](bound(receiversLengthRaw, 0, unique));
        uint256 weightSum = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            receivers[i] = receiversRaw[i];
            weightSum += receivers[i].weight;
        }
        if (weightSum == 0) weightSum = 1;
        uint256 totalWeight = bound(totalWeightRaw, 0, (totalSplitsWeight - receivers.length));
        uint256 usedWeight = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            uint256 usedTotalWeight = totalWeight * usedWeight / weightSum;
            usedWeight += receivers[i].weight;
            receivers[i].weight =
                uint32((totalWeight * usedWeight / weightSum) - usedTotalWeight + 1);
        }
    }

    function testSplitFundsAddUp(
        uint256 usedAccountId,
        IERC20 usedErc20,
        uint128 amt,
        SplitsReceiver[MAX_SPLITS_RECEIVERS] memory receiversRaw,
        uint256 receiversLengthRaw,
        uint256 totalWeightRaw
    ) public {
        SplitsReceiver[] memory receivers =
            sanitizeReceivers(receiversRaw, receiversLengthRaw, totalWeightRaw);
        splits.addSplittable(usedAccountId, usedErc20, amt);
        splits.setSplits(usedAccountId, receivers);
        (uint128 collectableAmt, uint128 splitAmt) =
            splits.split(usedAccountId, usedErc20, receivers);
        assertEq(collectableAmt + splitAmt, amt, "Invalid split results");
        uint128 collectedAmt = splits.collect(usedAccountId, usedErc20);
        assertEq(collectedAmt, collectableAmt, "Invalid collected amount");
        uint256 splitSum = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            splitSum += splits.splittable(receivers[i].accountId, usedErc20);
        }
        assertEq(splitSum, splitAmt, "Invalid split amount");
    }
}
