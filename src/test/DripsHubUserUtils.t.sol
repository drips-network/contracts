// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DSTest} from "ds-test/test.sol";
import {DripsHubUser} from "./DripsHubUser.t.sol";
import {SplitsReceiver, DripsHub, Receiver} from "../DripsHub.sol";

abstract contract DripsHubUserUtils is DSTest {
    mapping(DripsHubUser => bytes) internal senderStates;
    mapping(DripsHubUser => mapping(uint256 => bytes)) internal senderAccountStates;
    mapping(DripsHubUser => bytes) internal currSplitsReceivers;

    function getSenderState(DripsHubUser user)
        internal
        returns (
            uint64 lastUpdate,
            uint128 lastBalance,
            Receiver[] memory currReceivers
        )
    {
        (lastUpdate, lastBalance, currReceivers) = decodeSenderState(senderStates[user]);
        assertSenderState(user, lastUpdate, lastBalance, currReceivers);
    }

    function getSenderState(DripsHubUser user, uint256 account)
        internal
        returns (
            uint64 lastUpdate,
            uint128 lastBalance,
            Receiver[] memory currReceivers
        )
    {
        (lastUpdate, lastBalance, currReceivers) = decodeSenderState(
            senderAccountStates[user][account]
        );
        assertSenderState(user, account, lastUpdate, lastBalance, currReceivers);
    }

    function setSenderState(
        DripsHubUser user,
        uint128 newBalance,
        Receiver[] memory newReceivers
    ) internal {
        uint64 currTimestamp = uint64(block.timestamp);
        assertSenderState(user, currTimestamp, newBalance, newReceivers);
        senderStates[user] = abi.encode(currTimestamp, newBalance, newReceivers);
    }

    function setSenderState(
        DripsHubUser user,
        uint256 account,
        uint128 newBalance,
        Receiver[] memory newReceivers
    ) internal {
        uint64 currTimestamp = uint64(block.timestamp);
        assertSenderState(user, account, currTimestamp, newBalance, newReceivers);
        senderAccountStates[user][account] = abi.encode(currTimestamp, newBalance, newReceivers);
    }

    function decodeSenderState(bytes storage encoded)
        internal
        view
        returns (
            uint64 lastUpdate,
            uint128 lastBalance,
            Receiver[] memory
        )
    {
        if (encoded.length == 0) {
            return (0, 0, new Receiver[](0));
        } else {
            return abi.decode(encoded, (uint64, uint128, Receiver[]));
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

    function receivers() internal pure returns (Receiver[] memory list) {
        list = new Receiver[](0);
    }

    function receivers(DripsHubUser user, uint128 amtPerSec)
        internal
        pure
        returns (Receiver[] memory list)
    {
        list = new Receiver[](1);
        list[0] = Receiver(address(user), amtPerSec);
    }

    function receivers(
        DripsHubUser user1,
        uint128 amtPerSec1,
        DripsHubUser user2,
        uint128 amtPerSec2
    ) internal pure returns (Receiver[] memory list) {
        list = new Receiver[](2);
        list[0] = Receiver(address(user1), amtPerSec1);
        list[1] = Receiver(address(user2), amtPerSec2);
    }

    function updateSender(
        DripsHubUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        Receiver[] memory newReceivers
    ) internal {
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        uint256 expectedBalance = uint256(int256(user.balance()) - balanceDelta);
        (uint64 lastUpdate, uint128 lastBalance, Receiver[] memory currReceivers) = getSenderState(
            user
        );

        (uint128 newBalance, int128 realBalanceDelta) = user.updateSender(
            lastUpdate,
            lastBalance,
            currReceivers,
            balanceDelta,
            newReceivers
        );

        setSenderState(user, newBalance, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid sender balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        assertBalance(user, expectedBalance);
    }

    function assertSenderState(
        DripsHubUser user,
        uint64 lastUpdate,
        uint128 balance,
        Receiver[] memory currReceivers
    ) internal {
        bytes32 actual = user.senderStateHash();
        bytes32 expected = user.hashSenderState(lastUpdate, balance, currReceivers);
        assertEq(actual, expected, "Invalid sender state");
    }

    function assertSenderBalance(DripsHubUser user, uint128 expected) internal {
        changeBalance(user, expected, expected);
    }

    function changeBalance(
        DripsHubUser user,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        (, , Receiver[] memory currReceivers) = getSenderState(user);
        updateSender(user, balanceFrom, balanceTo, currReceivers);
    }

    function assertSetReceiversReverts(
        DripsHubUser user,
        Receiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        (uint64 lastUpdate, uint128 lastBalance, Receiver[] memory currReceivers) = getSenderState(
            user
        );
        assertUpdateSenderReverts(
            user,
            lastUpdate,
            lastBalance,
            currReceivers,
            0,
            newReceivers,
            expectedReason
        );
    }

    function assertUpdateSenderReverts(
        DripsHubUser user,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] memory currReceivers,
        int128 balanceDelta,
        Receiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        try user.updateSender(lastUpdate, lastBalance, currReceivers, balanceDelta, newReceivers) {
            assertTrue(false, "Sender update hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid sender update revert reason");
        }
    }

    function updateSender(
        DripsHubUser user,
        uint256 account,
        uint128 balanceFrom,
        uint128 balanceTo,
        Receiver[] memory newReceivers
    ) internal {
        int128 balanceDelta = int128(balanceTo) - int128(balanceFrom);
        uint256 expectedBalance = uint256(int256(user.balance()) - balanceDelta);
        (uint64 lastUpdate, uint128 lastBalance, Receiver[] memory currReceivers) = getSenderState(
            user,
            account
        );

        (uint128 newBalance, int128 realBalanceDelta) = user.updateSender(
            account,
            lastUpdate,
            lastBalance,
            currReceivers,
            balanceDelta,
            newReceivers
        );

        setSenderState(user, account, newBalance, newReceivers);
        assertEq(newBalance, balanceTo, "Invalid sender balance");
        assertEq(realBalanceDelta, balanceDelta, "Invalid real balance delta");
        assertBalance(user, expectedBalance);
    }

    function assertSenderState(
        DripsHubUser user,
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] memory currReceivers
    ) internal {
        bytes32 actual = user.senderStateHash(account);
        bytes32 expected = user.hashSenderState(lastUpdate, lastBalance, currReceivers);
        assertEq(actual, expected, "Invalid account state");
    }

    function changeBalance(
        DripsHubUser user,
        uint256 account,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        (, , Receiver[] memory curr) = getSenderState(user, account);
        updateSender(user, account, balanceFrom, balanceTo, curr);
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
        setSplits(user, newReceivers, 0, 0);
    }

    function setSplits(
        DripsHubUser user,
        SplitsReceiver[] memory newReceivers,
        uint128 expectedCollected,
        uint128 expectedsplit
    ) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(user);
        assertSplits(user, curr);
        assertCollectable(user, expectedCollected, expectedsplit);
        uint256 expectedBalance = user.balance() + expectedCollected;

        (uint128 collected, uint128 split) = user.setSplits(curr, newReceivers);

        setCurrSplitsReceivers(user, newReceivers);
        assertSplits(user, newReceivers);
        assertEq(collected, expectedCollected, "Invalid collected amount");
        assertEq(split, expectedsplit, "Invalid split amount");
        assertCollectable(user, 0, 0);
        assertBalance(user, expectedBalance);
    }

    function assertSetSplitsReverts(
        DripsHubUser user,
        SplitsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        SplitsReceiver[] memory curr = getCurrSplitsReceivers(user);
        assertSplits(user, curr);
        try user.setSplits(curr, newReceivers) {
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
        uint128 expectedsplit
    ) internal {
        collect(user, user, expectedCollected, expectedsplit);
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
        uint128 expectedsplit
    ) internal {
        assertCollectable(collected, expectedCollected, expectedsplit);
        uint256 expectedBalance = collected.balance() + expectedCollected;

        (uint128 collectedAmt, uint128 splitAmt) = user.collect(
            address(collected),
            getCurrSplitsReceivers(user)
        );

        assertEq(collectedAmt, expectedCollected, "Invalid collected amount");
        assertEq(splitAmt, expectedsplit, "Invalid split amount");
        assertCollectable(collected, 0);
        assertBalance(collected, expectedBalance);
    }

    function assertCollectable(DripsHubUser user, uint128 expected) internal {
        assertCollectable(user, expected, 0);
    }

    function assertCollectable(
        DripsHubUser user,
        uint128 expectedCollected,
        uint128 expectedsplit
    ) internal {
        (uint128 actualCollected, uint128 actualsplit) = user.collectable(
            getCurrSplitsReceivers(user)
        );
        assertEq(actualCollected, expectedCollected, "Invalid collected");
        assertEq(actualsplit, expectedsplit, "Invalid split");
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
