// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DSTest} from "ds-test/test.sol";
import {PoolUser} from "./User.t.sol";
import {DripsReceiver, Pool, Receiver} from "../Pool.sol";

abstract contract PoolUserUtils is DSTest {
    mapping(PoolUser => bytes) internal currReceivers;
    mapping(PoolUser => mapping(uint256 => bytes)) internal currSubSenderReceivers;
    mapping(PoolUser => bytes) internal currDripsReceivers;

    function getCurrReceivers(PoolUser user) internal view returns (Receiver[] memory) {
        return decodeReceivers(currReceivers[user]);
    }

    function setCurrReceivers(PoolUser user, Receiver[] memory newReceivers) internal {
        currReceivers[user] = abi.encode(newReceivers);
    }

    function getCurrSubSenderReceivers(PoolUser user, uint256 id)
        internal
        view
        returns (Receiver[] memory)
    {
        return decodeReceivers(currSubSenderReceivers[user][id]);
    }

    function setCurrSubSenderReceivers(
        PoolUser user,
        uint256 id,
        Receiver[] memory newReceivers
    ) internal {
        currSubSenderReceivers[user][id] = abi.encode(newReceivers);
    }

    function decodeReceivers(bytes storage encoded) internal view returns (Receiver[] memory) {
        if (encoded.length == 0) {
            return new Receiver[](0);
        } else {
            return abi.decode(encoded, (Receiver[]));
        }
    }

    function getCurrDripsReceivers(PoolUser user) internal view returns (DripsReceiver[] memory) {
        bytes storage encoded = currDripsReceivers[user];
        if (encoded.length == 0) {
            return new DripsReceiver[](0);
        } else {
            return abi.decode(encoded, (DripsReceiver[]));
        }
    }

    function setCurrDripsReceivers(PoolUser user, DripsReceiver[] memory newReceivers) internal {
        currDripsReceivers[user] = abi.encode(newReceivers);
    }

    function receivers() internal pure returns (Receiver[] memory list) {
        list = new Receiver[](0);
    }

    function receivers(PoolUser user, uint128 amtPerSec)
        internal
        pure
        returns (Receiver[] memory list)
    {
        list = new Receiver[](1);
        list[0] = Receiver(address(user), amtPerSec);
    }

    function receivers(
        PoolUser user1,
        uint128 amtPerSec1,
        PoolUser user2,
        uint128 amtPerSec2
    ) internal pure returns (Receiver[] memory list) {
        list = new Receiver[](2);
        list[0] = Receiver(address(user1), amtPerSec1);
        list[1] = Receiver(address(user2), amtPerSec2);
    }

    function updateSender(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        Receiver[] memory newReceivers
    ) internal {
        assertWithdrawable(user, balanceFrom);
        uint128 toppedUp = balanceTo > balanceFrom ? balanceTo - balanceFrom : 0;
        uint128 withdraw = balanceTo < balanceFrom ? balanceFrom - balanceTo : 0;
        uint256 expectedBalance = user.balance() + withdraw - toppedUp;
        Receiver[] memory curr = getCurrReceivers(user);
        assertReceivers(user, curr);

        uint128 withdrawn = user.updateSender(toppedUp, withdraw, curr, newReceivers);

        setCurrReceivers(user, newReceivers);
        assertEq(withdrawn, withdraw, "Expected amount not withdrawn");
        assertWithdrawable(user, balanceTo);
        assertBalance(user, expectedBalance);
        assertReceivers(user, newReceivers);
    }

    function assertReceivers(PoolUser user, Receiver[] memory expectedReceivers) internal {
        bytes32 actual = user.getReceiversHash();
        bytes32 expected = user.hashReceivers(expectedReceivers);
        assertEq(actual, expected, "Invalid receivers list hash");
    }

    function assertWithdrawable(PoolUser user, uint128 expected) internal {
        uint128 actual = user.withdrawable(getCurrReceivers(user));
        assertEq(actual, expected, "Invalid withdrawable");
    }

    function changeBalance(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        updateSender(user, balanceFrom, balanceTo, getCurrReceivers(user));
    }

    function setReceivers(PoolUser user, Receiver[] memory newReceivers) internal {
        uint128 withdrawable = user.withdrawable(getCurrReceivers(user));
        updateSender(user, withdrawable, withdrawable, newReceivers);
    }

    function assertSetReceiversReverts(
        PoolUser user,
        Receiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        try user.updateSender(0, 0, getCurrReceivers(user), newReceivers) {
            assertTrue(false, "Sender receivers update hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid sender receivers update revert reason");
        }
    }

    function updateSubSender(
        PoolUser user,
        uint256 subSenderId,
        uint128 balanceFrom,
        uint128 balanceTo,
        Receiver[] memory newReceivers
    ) internal {
        assertWithdrawableSubSender(user, subSenderId, balanceFrom);
        uint128 toppedUp = balanceTo > balanceFrom ? balanceTo - balanceFrom : 0;
        uint128 withdraw = balanceTo < balanceFrom ? balanceFrom - balanceTo : 0;
        uint256 expectedBalance = user.balance() + withdraw - toppedUp;
        Receiver[] memory curr = getCurrSubSenderReceivers(user, subSenderId);
        assertSubSenderReceivers(user, subSenderId, curr);

        uint256 withdrawn = user.updateSubSender(
            subSenderId,
            toppedUp,
            withdraw,
            curr,
            newReceivers
        );

        setCurrSubSenderReceivers(user, subSenderId, newReceivers);
        assertEq(withdrawn, withdraw, "expected amount not withdrawn");
        assertWithdrawableSubSender(user, subSenderId, balanceTo);
        assertBalance(user, expectedBalance);
        assertSubSenderReceivers(user, subSenderId, newReceivers);
    }

    function assertWithdrawableSubSender(
        PoolUser user,
        uint256 subSenderId,
        uint128 expected
    ) internal {
        uint128 actual = user.withdrawableSubSender(
            subSenderId,
            getCurrSubSenderReceivers(user, subSenderId)
        );
        assertEq(actual, expected, "Invalid withdrawable");
    }

    function assertSubSenderReceivers(
        PoolUser user,
        uint256 subSenderId,
        Receiver[] memory expectedReceivers
    ) internal {
        bytes32 actual = user.getSubSenderReceiversHash(subSenderId);
        bytes32 expected = user.hashReceivers(expectedReceivers);
        assertEq(actual, expected, "Invalid receivers list hash");
    }

    function changeBalanceSubSender(
        PoolUser user,
        uint256 subSenderId,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        updateSubSender(
            user,
            subSenderId,
            balanceFrom,
            balanceTo,
            getCurrSubSenderReceivers(user, subSenderId)
        );
    }

    function dripsReceivers() internal pure returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](0);
    }

    function dripsReceivers(PoolUser user, uint32 weight)
        internal
        pure
        returns (DripsReceiver[] memory list)
    {
        list = new DripsReceiver[](1);
        list[0] = DripsReceiver(address(user), weight);
    }

    function dripsReceivers(
        PoolUser user1,
        uint32 weight1,
        PoolUser user2,
        uint32 weight2
    ) internal pure returns (DripsReceiver[] memory list) {
        list = new DripsReceiver[](2);
        list[0] = DripsReceiver(address(user1), weight1);
        list[1] = DripsReceiver(address(user2), weight2);
    }

    function setDripsReceivers(PoolUser user, DripsReceiver[] memory newReceivers) internal {
        DripsReceiver[] memory curr = getCurrDripsReceivers(user);
        assertDripsReceivers(user, curr);

        user.setDripsReceivers(curr, newReceivers);

        setCurrDripsReceivers(user, newReceivers);
        assertDripsReceivers(user, newReceivers);
    }

    function assertSetDripsReceiversReverts(
        PoolUser user,
        DripsReceiver[] memory newReceivers,
        string memory expectedReason
    ) internal {
        DripsReceiver[] memory curr = getCurrDripsReceivers(user);
        assertDripsReceivers(user, curr);
        try user.setDripsReceivers(curr, newReceivers) {
            assertTrue(false, "Drips receivers update hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid drips receivers update revert reason");
        }
    }

    function assertDripsReceivers(PoolUser user, DripsReceiver[] memory expectedReceivers)
        internal
    {
        bytes32 actual = user.dripsReceiversHash();
        bytes32 expected = user.hashDripsReceivers(expectedReceivers);
        assertEq(actual, expected, "Invalid drips receivers list hash");
    }

    function collect(PoolUser user, uint128 expectedAmt) internal {
        collect(user, user, expectedAmt, 0);
    }

    function collect(
        PoolUser user,
        uint128 expectedCollected,
        uint128 expectedDripped
    ) internal {
        collect(user, user, expectedCollected, expectedDripped);
    }

    function collect(
        PoolUser user,
        PoolUser collected,
        uint128 expectedAmt
    ) internal {
        collect(user, collected, expectedAmt, 0);
    }

    function collect(
        PoolUser user,
        PoolUser collected,
        uint128 expectedCollected,
        uint128 expectedDripped
    ) internal {
        assertCollectable(collected, expectedCollected, expectedDripped);
        uint256 expectedBalance = collected.balance() + expectedCollected;

        (uint128 collectedAmt, uint128 drippedAmt) = user.collect(
            address(collected),
            getCurrDripsReceivers(user)
        );

        assertEq(collectedAmt, expectedCollected, "Invalid collected amount");
        assertEq(drippedAmt, expectedDripped, "Invalid dripped amount");
        assertCollectable(collected, 0);
        assertBalance(collected, expectedBalance);
    }

    function assertCollectable(PoolUser user, uint128 expected) internal {
        assertCollectable(user, expected, 0);
    }

    function assertCollectable(
        PoolUser user,
        uint128 expectedCollected,
        uint128 expectedDripped
    ) internal {
        (uint128 actualCollected, uint128 actualDripped) = user.collectable(
            getCurrDripsReceivers(user)
        );
        assertEq(actualCollected, expectedCollected, "Invalid collectable");
        assertEq(actualDripped, expectedDripped, "Invalid drippable");
    }

    function flushCycles(
        PoolUser user,
        uint64 expectedFlushableBefore,
        uint64 maxCycles,
        uint64 expectedFlushableAfter
    ) internal {
        assertFlushableCycles(user, expectedFlushableBefore);
        uint64 flushableLeft = user.flushCycles(maxCycles);
        assertEq(flushableLeft, expectedFlushableAfter, "Invalid flushable cycles left");
        assertFlushableCycles(user, expectedFlushableAfter);
    }

    function assertFlushableCycles(PoolUser user, uint64 expectedFlushable) internal {
        uint64 actualFlushable = user.flushableCycles();
        assertEq(actualFlushable, expectedFlushable, "Invalid flushable cycles");
    }

    function assertBalance(PoolUser user, uint256 expected) internal {
        assertEq(user.balance(), expected, "Invalid balance");
    }
}
