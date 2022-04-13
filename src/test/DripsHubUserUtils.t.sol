// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DSTest} from "ds-test/test.sol";
import {AddressIdUser} from "./AddressIdUser.t.sol";
import {Hevm} from "./Hevm.t.sol";
import {SplitsReceiver, DripsHub, DripsReceiver} from "../DripsHub.sol";

abstract contract DripsHubUserUtils is DSTest {
    DripsHub private dripsHub;
    uint256 internal defaultAsset;

    // Keys are user ID and asset ID
    mapping(uint256 => mapping(uint256 => bytes)) internal drips;
    // Keys is user ID
    mapping(uint256 => bytes) internal currSplitsReceivers;

    function setUp(DripsHub dripsHub_) internal {
        dripsHub = dripsHub_;
    }

    function warpToCycleEnd() internal {
        warpBy(dripsHub.cycleSecs() - (block.timestamp % dripsHub.cycleSecs()));
    }

    function warpBy(uint256 secs) internal {
        Hevm(HEVM_ADDRESS).warp(block.timestamp + secs);
    }

    function calcUserId(uint32 account, uint224 subAccount) internal view returns (uint256) {
        return (uint256(account) << dripsHub.BITS_SUB_ACCOUNT()) | subAccount;
    }

    function loadDrips(AddressIdUser user)
        internal
        returns (
            uint64 lastUpdate,
            uint128 lastBalance,
            DripsReceiver[] memory currReceivers
        )
    {
        return loadDrips(defaultAsset, user);
    }

    function loadDrips(uint256 asset, AddressIdUser user)
        internal
        returns (
            uint64 lastUpdate,
            uint128 lastBalance,
            DripsReceiver[] memory currReceivers
        )
    {
        (lastUpdate, lastBalance, currReceivers) = decodeDrips(drips[user.userId()][asset]);
        assertDrips(asset, user, lastUpdate, lastBalance, currReceivers);
    }

    function storeDrips(
        AddressIdUser user,
        uint128 newBalance,
        DripsReceiver[] memory newReceivers
    ) internal {
        storeDrips(defaultAsset, user, newBalance, newReceivers);
    }

    function storeDrips(
        uint256 asset,
        AddressIdUser user,
        uint128 newBalance,
        DripsReceiver[] memory newReceivers
    ) internal {
        uint64 currTimestamp = uint64(block.timestamp);
        assertDrips(asset, user, currTimestamp, newBalance, newReceivers);
        drips[user.userId()][asset] = abi.encode(currTimestamp, newBalance, newReceivers);
    }

    function decodeDrips(bytes storage encoded)
        internal
        view
        returns (
            uint64 lastUpdate,
            uint128 lastBalance,
            DripsReceiver[] memory
        )
    {
        if (encoded.length == 0) {
            return (0, 0, new DripsReceiver[](0));
        } else {
            return abi.decode(encoded, (uint64, uint128, DripsReceiver[]));
        }
    }

    function getCurrSplitsReceivers(AddressIdUser user)
        internal
        view
        returns (SplitsReceiver[] memory)
    {
        bytes storage encoded = currSplitsReceivers[user.userId()];
        if (encoded.length == 0) {
            return new SplitsReceiver[](0);
        } else {
            return abi.decode(encoded, (SplitsReceiver[]));
        }
    }

    function setCurrSplitsReceivers(AddressIdUser user, SplitsReceiver[] memory newReceivers)
        internal
    {
        currSplitsReceivers[user.userId()] = abi.encode(newReceivers);
    }

    function dripsReceivers() internal pure returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](0);
    }

    function dripsReceivers(AddressIdUser user, uint128 amtPerSec)
        internal
        view
        returns (DripsReceiver[] memory list)
    {
        list = new DripsReceiver[](1);
        list[0] = DripsReceiver(user.userId(), amtPerSec);
    }

    function dripsReceivers(
        AddressIdUser user1,
        uint128 amtPerSec1,
        AddressIdUser user2,
        uint128 amtPerSec2
    ) internal view returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](2);
        list[0] = DripsReceiver(user1.userId(), amtPerSec1);
        list[1] = DripsReceiver(user2.userId(), amtPerSec2);
    }

    function setDrips(
        AddressIdUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        setDrips(defaultAsset, user, balanceFrom, balanceTo, newReceivers);
    }

    function setDrips(
        uint256 asset,
        AddressIdUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        uint256 expectedBalance = uint256(int256(user.balance(asset)) - balanceDelta);
        (uint64 lastUpdate, uint128 lastBalance, DripsReceiver[] memory currReceivers) = loadDrips(
            asset,
            user
        );

        (uint128 newBalance, int128 realBalanceDelta) = user.setDrips(
            asset,
            lastUpdate,
            lastBalance,
            currReceivers,
            balanceDelta,
            newReceivers
        );

        storeDrips(asset, user, newBalance, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid drips balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        assertBalance(asset, user, expectedBalance);
    }

    function assertDrips(
        uint256 asset,
        AddressIdUser user,
        uint64 lastUpdate,
        uint128 balance,
        DripsReceiver[] memory currReceivers
    ) internal {
        bytes32 actual = dripsHub.dripsHash(user.userId(), asset);
        bytes32 expected = dripsHub.hashDrips(lastUpdate, balance, currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function assertDripsBalance(AddressIdUser user, uint128 expected) internal {
        changeBalance(user, expected, expected);
    }

    function changeBalance(
        AddressIdUser user,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        (, , DripsReceiver[] memory currReceivers) = loadDrips(user);
        setDrips(user, balanceFrom, balanceTo, currReceivers);
    }

    function assertSetReceiversReverts(
        AddressIdUser user,
        DripsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        (uint64 lastUpdate, uint128 lastBalance, DripsReceiver[] memory currReceivers) = loadDrips(
            user
        );
        assertSetDripsReverts(
            user,
            lastUpdate,
            lastBalance,
            currReceivers,
            0,
            newReceivers,
            expectedReason
        );
    }

    function assertSetDripsReverts(
        AddressIdUser user,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        try
            user.setDrips(
                defaultAsset,
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            )
        {
            assertTrue(false, "Set drips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid set drips revert reason");
        }
    }

    function assertDrips(
        uint256 asset,
        uint256 user,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers
    ) internal {
        bytes32 actual = dripsHub.dripsHash(user, asset);
        bytes32 expected = dripsHub.hashDrips(lastUpdate, lastBalance, currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function give(
        AddressIdUser user,
        AddressIdUser receiver,
        uint128 amt
    ) internal {
        give(defaultAsset, user, receiver, amt);
    }

    function give(
        uint256 asset,
        AddressIdUser user,
        AddressIdUser receiver,
        uint128 amt
    ) internal {
        uint256 expectedBalance = uint256(user.balance(asset) - amt);
        uint128 expectedCollectable = totalCollectableAll(asset, receiver) + amt;

        user.give(receiver.userId(), asset, amt);

        assertBalance(asset, user, expectedBalance);
        assertTotalCollectableAll(asset, receiver, expectedCollectable);
    }

    function splitsReceivers() internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](0);
    }

    function splitsReceivers(AddressIdUser user, uint32 weight)
        internal
        view
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](1);
        list[0] = SplitsReceiver(user.userId(), weight);
    }

    function splitsReceivers(
        AddressIdUser user1,
        uint32 weight1,
        AddressIdUser user2,
        uint32 weight2
    ) internal view returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](2);
        list[0] = SplitsReceiver(user1.userId(), weight1);
        list[1] = SplitsReceiver(user2.userId(), weight2);
    }

    function setSplits(AddressIdUser user, SplitsReceiver[] memory newReceivers) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(user);
        assertSplits(user, curr);

        user.setSplits(newReceivers);

        setCurrSplitsReceivers(user, newReceivers);
        assertSplits(user, newReceivers);
    }

    function assertSetSplitsReverts(
        AddressIdUser user,
        SplitsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(user);
        assertSplits(user, curr);
        try user.setSplits(newReceivers) {
            assertTrue(false, "setSplits hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid setSplits revert reason");
        }
    }

    function assertSplits(AddressIdUser user, SplitsReceiver[] memory expectedReceivers) internal {
        bytes32 actual = dripsHub.splitsHash(user.userId());
        bytes32 expected = dripsHub.hashSplits(expectedReceivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function collectAll(AddressIdUser user, uint128 expectedAmt) internal {
        collectAll(defaultAsset, user, expectedAmt, 0);
    }

    function collectAll(
        uint256 asset,
        AddressIdUser user,
        uint128 expectedAmt
    ) internal {
        collectAll(asset, user, expectedAmt, 0);
    }

    function collectAll(
        AddressIdUser user,
        uint128 expectedCollected,
        uint128 expectedSplit
    ) internal {
        collectAll(defaultAsset, user, expectedCollected, expectedSplit);
    }

    function collectAll(
        uint256 asset,
        AddressIdUser user,
        uint128 expectedCollected,
        uint128 expectedSplit
    ) internal {
        assertCollectableAll(asset, user, expectedCollected, expectedSplit);
        uint256 expectedBalance = user.balance(asset) + expectedCollected;

        (uint128 collectedAmt, uint128 splitAmt) = user.collectAll(
            address(user),
            asset,
            getCurrSplitsReceivers(user)
        );

        assertEq(collectedAmt, expectedCollected, "Invalid collected amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertCollectableAll(asset, user, 0);
        assertBalance(asset, user, expectedBalance);
    }

    function assertCollectableAll(AddressIdUser user, uint128 expected) internal {
        assertCollectableAll(defaultAsset, user, expected, 0);
    }

    function assertCollectableAll(
        uint256 asset,
        AddressIdUser user,
        uint128 expected
    ) internal {
        assertCollectableAll(asset, user, expected, 0);
    }

    function assertCollectableAll(
        AddressIdUser user,
        uint128 expectedCollected,
        uint128 expectedSplit
    ) internal {
        assertCollectableAll(defaultAsset, user, expectedCollected, expectedSplit);
    }

    function assertCollectableAll(
        uint256 asset,
        AddressIdUser user,
        uint128 expectedCollected,
        uint128 expectedSplit
    ) internal {
        (uint128 actualCollected, uint128 actualSplit) = dripsHub.collectableAll(
            user.userId(),
            asset,
            getCurrSplitsReceivers(user)
        );
        assertEq(actualCollected, expectedCollected, "Invalid collected");
        assertEq(actualSplit, expectedSplit, "Invalid split");
    }

    function totalCollectableAll(uint256 asset, AddressIdUser user)
        internal
        view
        returns (uint128)
    {
        SplitsReceiver[] memory splits = getCurrSplitsReceivers(user);
        (uint128 collectableAmt, uint128 splittableAmt) = dripsHub.collectableAll(
            user.userId(),
            asset,
            splits
        );
        return collectableAmt + splittableAmt;
    }

    function assertTotalCollectableAll(
        uint256 asset,
        AddressIdUser user,
        uint128 expectedCollectable
    ) internal {
        uint128 actualCollectable = totalCollectableAll(asset, user);
        assertEq(actualCollectable, expectedCollectable, "Invalid total collectable");
    }

    function receiveDrips(
        AddressIdUser user,
        uint128 expectedReceivedAmt,
        uint64 expectedReceivedCycles
    ) internal {
        receiveDrips(user, type(uint64).max, expectedReceivedAmt, expectedReceivedCycles, 0, 0);
    }

    function receiveDrips(
        AddressIdUser user,
        uint64 maxCycles,
        uint128 expectedReceivedAmt,
        uint64 expectedReceivedCycles,
        uint128 expectedAmtAfter,
        uint64 expectedCyclesAfter
    ) internal {
        uint128 expectedTotalAmt = expectedReceivedAmt + expectedAmtAfter;
        uint64 expectedTotalCycles = expectedReceivedCycles + expectedCyclesAfter;
        assertReceivableDripsCycles(user, expectedTotalCycles);
        assertReceivableDrips(user, type(uint64).max, expectedTotalAmt, 0);
        assertReceivableDrips(user, maxCycles, expectedReceivedAmt, expectedCyclesAfter);

        (uint128 receivedAmt, uint64 receivableCycles) = dripsHub.receiveDrips(
            user.userId(),
            defaultAsset,
            maxCycles
        );

        assertEq(receivedAmt, expectedReceivedAmt, "Invalid amount received from drips");
        assertEq(receivableCycles, expectedCyclesAfter, "Invalid receivable drips cycles left");
        assertReceivableDripsCycles(user, expectedCyclesAfter);
        assertReceivableDrips(user, type(uint64).max, expectedAmtAfter, 0);
    }

    function assertReceivableDripsCycles(AddressIdUser user, uint64 expectedCycles) internal {
        uint64 actualCycles = dripsHub.receivableDripsCycles(user.userId(), defaultAsset);
        assertEq(actualCycles, expectedCycles, "Invalid total receivable drips cycles");
    }

    function assertReceivableDrips(
        AddressIdUser user,
        uint64 maxCycles,
        uint128 expectedAmt,
        uint64 expectedCycles
    ) internal {
        (uint128 actualAmt, uint64 actualCycles) = dripsHub.receivableDrips(
            user.userId(),
            defaultAsset,
            maxCycles
        );
        assertEq(actualAmt, expectedAmt, "Invalid receivable amount");
        assertEq(actualCycles, expectedCycles, "Invalid receivable drips cycles");
    }

    function split(
        AddressIdUser user,
        uint128 expectedCollectable,
        uint128 expectedSplit
    ) internal {
        assertSplittable(user, expectedCollectable + expectedSplit);
        uint128 collectableBefore = collectable(user);

        (uint128 collectableAmt, uint128 splitAmt) = dripsHub.split(
            user.userId(),
            defaultAsset,
            getCurrSplitsReceivers(user)
        );

        assertEq(collectableAmt, expectedCollectable, "Invalid collectable amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertSplittable(user, 0);
        assertCollectable(user, collectableBefore + expectedCollectable);
    }

    function assertSplittable(AddressIdUser user, uint256 expected) internal {
        uint256 actual = dripsHub.splittable(user.userId(), defaultAsset);
        assertEq(actual, expected, "Invalid splittable");
    }

    function collect(AddressIdUser user, uint128 expectedAmt) internal {
        assertCollectable(user, expectedAmt);
        uint256 balanceBefore = user.balance(defaultAsset);

        uint128 actualAmt = user.collect(address(user), defaultAsset);

        assertEq(actualAmt, expectedAmt, "Invalid collected amount");
        assertCollectable(user, 0);
        assertBalance(user, balanceBefore + expectedAmt);
    }

    function collectable(AddressIdUser user) internal view returns (uint128 amt) {
        return dripsHub.collectable(user.userId(), defaultAsset);
    }

    function assertCollectable(AddressIdUser user, uint256 expected) internal {
        assertEq(collectable(user), expected, "Invalid collectable");
    }

    function assertBalance(AddressIdUser user, uint256 expected) internal {
        assertBalance(defaultAsset, user, expected);
    }

    function assertBalance(
        uint256 asset,
        AddressIdUser user,
        uint256 expected
    ) internal {
        assertEq(user.balance(asset), expected, "Invalid balance");
    }
}
