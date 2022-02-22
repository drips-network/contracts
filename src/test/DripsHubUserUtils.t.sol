// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DSTest} from "ds-test/test.sol";
import {DripsHubUser} from "./DripsHubUser.t.sol";
import {SplitsReceiver, DripsHub, DripsReceiver} from "../DripsHub.sol";

abstract contract DripsHubUserUtils is DSTest {
    mapping(DripsHubUser => bytes) internal drips;
    mapping(DripsHubUser => mapping(uint256 => bytes)) internal accountDrips;
    mapping(DripsHubUser => bytes) internal currSplitsReceivers;

    function loadDrips(DripsHubUser user)
        internal
        returns (
            uint64 lastUpdate,
            uint128 lastBalance,
            DripsReceiver[] memory currReceivers
        )
    {
        (lastUpdate, lastBalance, currReceivers) = decodeDrips(drips[user]);
        assertDrips(user, lastUpdate, lastBalance, currReceivers);
    }

    function loadDrips(DripsHubUser user, uint256 account)
        internal
        returns (
            uint64 lastUpdate,
            uint128 lastBalance,
            DripsReceiver[] memory currReceivers
        )
    {
        (lastUpdate, lastBalance, currReceivers) = decodeDrips(accountDrips[user][account]);
        assertDrips(user, account, lastUpdate, lastBalance, currReceivers);
    }

    function storeDrips(
        DripsHubUser user,
        uint128 newBalance,
        DripsReceiver[] memory newReceivers
    ) internal {
        uint64 currTimestamp = uint64(block.timestamp);
        assertDrips(user, currTimestamp, newBalance, newReceivers);
        drips[user] = abi.encode(currTimestamp, newBalance, newReceivers);
    }

    function storeDrips(
        DripsHubUser user,
        uint256 account,
        uint128 newBalance,
        DripsReceiver[] memory newReceivers
    ) internal {
        uint64 currTimestamp = uint64(block.timestamp);
        assertDrips(user, account, currTimestamp, newBalance, newReceivers);
        accountDrips[user][account] = abi.encode(currTimestamp, newBalance, newReceivers);
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

    function getCurrSplitsReceivers(DripsHubUser user)
        internal
        view
        returns (SplitsReceiver[] memory)
    {
        bytes storage encoded = currSplitsReceivers[user];
        if (encoded.length == 0) {
            return new SplitsReceiver[](0);
        } else {
            return abi.decode(encoded, (SplitsReceiver[]));
        }
    }

    function setCurrSplitsReceivers(DripsHubUser user, SplitsReceiver[] memory newReceivers)
        internal
    {
        currSplitsReceivers[user] = abi.encode(newReceivers);
    }

    function dripsReceivers() internal pure returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](0);
    }

    function dripsReceivers(DripsHubUser user, uint128 amtPerSec)
        internal
        pure
        returns (DripsReceiver[] memory list)
    {
        list = new DripsReceiver[](1);
        list[0] = DripsReceiver(address(user), amtPerSec);
    }

    function dripsReceivers(
        DripsHubUser user1,
        uint128 amtPerSec1,
        DripsHubUser user2,
        uint128 amtPerSec2
    ) internal pure returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](2);
        list[0] = DripsReceiver(address(user1), amtPerSec1);
        list[1] = DripsReceiver(address(user2), amtPerSec2);
    }

    function setDrips(
        DripsHubUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        uint256 expectedBalance = uint256(int256(user.balance()) - balanceDelta);
        (uint64 lastUpdate, uint128 lastBalance, DripsReceiver[] memory currReceivers) = loadDrips(
            user
        );

        (uint128 newBalance, int128 realBalanceDelta) = user.setDrips(
            lastUpdate,
            lastBalance,
            currReceivers,
            balanceDelta,
            newReceivers
        );

        storeDrips(user, newBalance, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid drips balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        assertBalance(user, expectedBalance);
    }

    function assertDrips(
        DripsHubUser user,
        uint64 lastUpdate,
        uint128 balance,
        DripsReceiver[] memory currReceivers
    ) internal {
        bytes32 actual = user.dripsHash();
        bytes32 expected = user.hashDrips(lastUpdate, balance, currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function assertDripsBalance(DripsHubUser user, uint128 expected) internal {
        changeBalance(user, expected, expected);
    }

    function changeBalance(
        DripsHubUser user,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        (, , DripsReceiver[] memory currReceivers) = loadDrips(user);
        setDrips(user, balanceFrom, balanceTo, currReceivers);
    }

    function assertSetReceiversReverts(
        DripsHubUser user,
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
        DripsHubUser user,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        try user.setDrips(lastUpdate, lastBalance, currReceivers, balanceDelta, newReceivers) {
            assertTrue(false, "Set drips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid set drips revert reason");
        }
    }

    function setDrips(
        DripsHubUser user,
        uint256 account,
        uint128 balanceFrom,
        uint128 balanceTo,
        DripsReceiver[] memory newReceivers
    ) internal {
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        uint256 expectedBalance = uint256(int256(user.balance()) - balanceDelta);
        (uint64 lastUpdate, uint128 lastBalance, DripsReceiver[] memory currReceivers) = loadDrips(
            user,
            account
        );

        (uint128 newBalance, int128 realBalanceDelta) = user.setDrips(
            account,
            lastUpdate,
            lastBalance,
            currReceivers,
            balanceDelta,
            newReceivers
        );

        storeDrips(user, account, newBalance, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid drips balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        assertBalance(user, expectedBalance);
    }

    function assertDrips(
        DripsHubUser user,
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers
    ) internal {
        bytes32 actual = user.dripsHash(account);
        bytes32 expected = user.hashDrips(lastUpdate, lastBalance, currReceivers);
        assertEq(actual, expected, "Invalid drips configuration");
    }

    function changeBalance(
        DripsHubUser user,
        uint256 account,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        (, , DripsReceiver[] memory curr) = loadDrips(user, account);
        setDrips(user, account, balanceFrom, balanceTo, curr);
    }

    function give(
        DripsHubUser user,
        DripsHubUser receiver,
        uint128 amt
    ) internal {
        uint256 expectedBalance = uint256(user.balance() - amt);
        uint128 expectedCollectable = totalCollectable(receiver) + amt;

        user.give(address(receiver), amt);

        assertBalance(user, expectedBalance);
        assertTotalCollectable(receiver, expectedCollectable);
    }

    function give(
        DripsHubUser user,
        uint256 account,
        DripsHubUser receiver,
        uint128 amt
    ) internal {
        uint256 expectedBalance = uint256(user.balance() - amt);
        uint128 expectedCollectable = totalCollectable(receiver) + amt;

        user.give(account, address(receiver), amt);

        assertBalance(user, expectedBalance);
        assertTotalCollectable(receiver, expectedCollectable);
    }

    function splitsReceivers() internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](0);
    }

    function splitsReceivers(DripsHubUser user, uint32 weight)
        internal
        pure
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](1);
        list[0] = SplitsReceiver(address(user), weight);
    }

    function splitsReceivers(
        DripsHubUser user1,
        uint32 weight1,
        DripsHubUser user2,
        uint32 weight2
    ) internal pure returns (SplitsReceiver[] memory list) {
        list = new SplitsReceiver[](2);
        list[0] = SplitsReceiver(address(user1), weight1);
        list[1] = SplitsReceiver(address(user2), weight2);
    }

    function setSplits(DripsHubUser user, SplitsReceiver[] memory newReceivers) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(user);
        assertSplits(user, curr);

        user.setSplits(newReceivers);

        setCurrSplitsReceivers(user, newReceivers);
        assertSplits(user, newReceivers);
    }

    function assertSetSplitsReverts(
        DripsHubUser user,
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

    function assertSplits(DripsHubUser user, SplitsReceiver[] memory expectedReceivers) internal {
        bytes32 actual = user.splitsHash();
        bytes32 expected = user.hashSplits(expectedReceivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function collect(DripsHubUser user, uint128 expectedAmt) internal {
        collect(user, user, expectedAmt, 0);
    }

    function collect(
        DripsHubUser user,
        uint128 expectedCollected,
        uint128 expectedSplit
    ) internal {
        collect(user, user, expectedCollected, expectedSplit);
    }

    function collect(
        DripsHubUser user,
        DripsHubUser collected,
        uint128 expectedAmt
    ) internal {
        collect(user, collected, expectedAmt, 0);
    }

    function collect(
        DripsHubUser user,
        DripsHubUser collected,
        uint128 expectedCollected,
        uint128 expectedSplit
    ) internal {
        assertCollectable(collected, expectedCollected, expectedSplit);
        uint256 expectedBalance = collected.balance() + expectedCollected;

        (uint128 collectedAmt, uint128 splitAmt) = user.collect(
            address(collected),
            getCurrSplitsReceivers(user)
        );

        assertEq(collectedAmt, expectedCollected, "Invalid collected amount");
        assertEq(splitAmt, expectedSplit, "Invalid split amount");
        assertCollectable(collected, 0);
        assertBalance(collected, expectedBalance);
    }

    function assertCollectable(DripsHubUser user, uint128 expected) internal {
        assertCollectable(user, expected, 0);
    }

    function assertCollectable(
        DripsHubUser user,
        uint128 expectedCollected,
        uint128 expectedSplit
    ) internal {
        (uint128 actualCollected, uint128 actualSplit) = user.collectable(
            getCurrSplitsReceivers(user)
        );
        assertEq(actualCollected, expectedCollected, "Invalid collected");
        assertEq(actualSplit, expectedSplit, "Invalid split");
    }

    function totalCollectable(DripsHubUser user) internal view returns (uint128) {
        SplitsReceiver[] memory splits = getCurrSplitsReceivers(user);
        (uint128 collectable, uint128 splittable) = user.collectable(splits);
        return collectable + splittable;
    }

    function assertTotalCollectable(DripsHubUser user, uint128 expectedCollectable) internal {
        uint128 actualCollectable = totalCollectable(user);
        assertEq(actualCollectable, expectedCollectable, "Invalid total collectable");
    }

    function flushCycles(
        DripsHubUser user,
        uint64 expectedFlushableBefore,
        uint64 maxCycles,
        uint64 expectedFlushableAfter
    ) internal {
        assertFlushableCycles(user, expectedFlushableBefore);
        uint64 flushableLeft = user.flushCycles(maxCycles);
        assertEq(flushableLeft, expectedFlushableAfter, "Invalid flushable cycles left");
        assertFlushableCycles(user, expectedFlushableAfter);
    }

    function assertFlushableCycles(DripsHubUser user, uint64 expectedFlushable) internal {
        uint64 actualFlushable = user.flushableCycles();
        assertEq(actualFlushable, expectedFlushable, "Invalid flushable cycles");
    }

    function assertBalance(DripsHubUser user, uint256 expected) internal {
        assertEq(user.balance(), expected, "Invalid balance");
    }
}
