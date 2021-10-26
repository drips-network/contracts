// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DSTest} from "ds-test/test.sol";
import {PoolUser} from "./User.t.sol";
import {Pool, ReceiverWeight} from "../Pool.sol";

abstract contract PoolUserUtils is DSTest {
    mapping(PoolUser => bytes) internal currWeights;
    mapping(PoolUser => mapping(uint256 => bytes)) internal currSubSenderWeights;

    function getCurrWeights(PoolUser user) internal view returns (ReceiverWeight[] memory) {
        return decodeWeights(currWeights[user]);
    }

    function setCurrWeights(PoolUser user, ReceiverWeight[] memory newReceivers) internal {
        currWeights[user] = abi.encode(newReceivers);
    }

    function getCurrSubSenderWeights(PoolUser user, uint256 id)
        internal
        view
        returns (ReceiverWeight[] memory)
    {
        return decodeWeights(currSubSenderWeights[user][id]);
    }

    function setCurrSubSenderWeights(
        PoolUser user,
        uint256 id,
        ReceiverWeight[] memory newReceivers
    ) internal {
        currSubSenderWeights[user][id] = abi.encode(newReceivers);
    }

    function decodeWeights(bytes storage encoded) internal view returns (ReceiverWeight[] memory) {
        if (encoded.length == 0) {
            return new ReceiverWeight[](0);
        } else {
            return abi.decode(encoded, (ReceiverWeight[]));
        }
    }

    function weights() internal pure returns (ReceiverWeight[] memory list) {
        list = new ReceiverWeight[](0);
    }

    function weights(PoolUser user, uint32 weight)
        internal
        pure
        returns (ReceiverWeight[] memory list)
    {
        list = new ReceiverWeight[](1);
        list[0] = ReceiverWeight(address(user), weight);
    }

    function weights(
        PoolUser user1,
        uint32 weight1,
        PoolUser user2,
        uint32 weight2
    ) internal pure returns (ReceiverWeight[] memory list) {
        list = new ReceiverWeight[](2);
        list[0] = ReceiverWeight(address(user1), weight1);
        list[1] = ReceiverWeight(address(user2), weight2);
    }

    function updateSender(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        uint128 amtPerSec,
        uint32 dripsFraction,
        ReceiverWeight[] memory newReceivers
    ) internal {
        assertWithdrawable(user, balanceFrom);
        uint128 toppedUp = balanceTo > balanceFrom ? balanceTo - balanceFrom : 0;
        uint128 withdraw = balanceTo < balanceFrom ? balanceFrom - balanceTo : 0;
        uint256 expectedBalance = user.balance() + withdraw - toppedUp;
        uint128 expectedAmtPerSec = amtPerSec == user.getAmtPerSecUnchanged()
            ? user.getAmtPerSec()
            : amtPerSec;
        ReceiverWeight[] memory curr = getCurrWeights(user);
        assertReceivers(user, curr);

        (uint128 withdrawn, uint128 collected, uint128 dripped) = user.updateSender(
            toppedUp,
            withdraw,
            amtPerSec,
            dripsFraction,
            curr,
            newReceivers
        );

        setCurrWeights(user, newReceivers);
        assertEq(withdrawn, withdraw, "Expected amount not withdrawn");
        assertEq(collected, 0, "Expected non-withdrawing sender update");
        assertEq(dripped, 0, "Expected non-dripping sender update");
        assertWithdrawable(user, balanceTo);
        assertBalance(user, expectedBalance);
        assertEq(user.getAmtPerSec(), expectedAmtPerSec, "Invalid amtPerSec after updateSender");
        assertEq(
            user.getDripsFraction(),
            dripsFraction,
            "Invalid dripsFraction after updateSender"
        );
        assertReceivers(user, newReceivers);
    }

    function assertReceivers(PoolUser user, ReceiverWeight[] memory list) internal {
        bytes32 actual = user.getReceiverWeightsHash();
        bytes32 expected = user.hashReceiverWeights(list);
        assertEq(actual, expected, "Invalid receivers list hash");
    }

    function assertWithdrawable(PoolUser user, uint128 expected) internal {
        assertEq(user.withdrawable(), expected, "Invalid withdrawable");
    }

    function changeBalance(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        updateSender(
            user,
            balanceFrom,
            balanceTo,
            user.getAmtPerSecUnchanged(),
            user.getDripsFraction(),
            getCurrWeights(user)
        );
    }

    function setAmtPerSec(PoolUser user, uint128 amtPerSec) internal {
        uint128 withdrawable = user.withdrawable();
        updateSender(
            user,
            withdrawable,
            withdrawable,
            amtPerSec,
            user.getDripsFraction(),
            getCurrWeights(user)
        );
    }

    function setReceivers(PoolUser user, ReceiverWeight[] memory newReceivers) internal {
        uint128 withdrawable = user.withdrawable();
        updateSender(
            user,
            withdrawable,
            withdrawable,
            user.getAmtPerSecUnchanged(),
            user.getDripsFraction(),
            newReceivers
        );
    }

    function assertSetReceiversReverts(
        PoolUser user,
        ReceiverWeight[] memory newReceivers,
        string memory expectedReason
    ) internal {
        try
            user.updateSender(
                0,
                0,
                user.getAmtPerSecUnchanged(),
                user.getDripsFraction(),
                getCurrWeights(user),
                newReceivers
            )
        {
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
        uint128 amtPerSec,
        ReceiverWeight[] memory newReceivers
    ) internal {
        assertWithdrawableSubSender(user, subSenderId, balanceFrom);
        uint128 toppedUp = balanceTo > balanceFrom ? balanceTo - balanceFrom : 0;
        uint128 withdraw = balanceTo < balanceFrom ? balanceFrom - balanceTo : 0;
        uint256 expectedBalance = user.balance() + withdraw - toppedUp;
        uint128 expectedAmtPerSec = amtPerSec == user.getAmtPerSecUnchanged()
            ? user.getAmtPerSecSubSender(subSenderId)
            : amtPerSec;
        ReceiverWeight[] memory curr = getCurrSubSenderWeights(user, subSenderId);
        assertSubSenderReceivers(user, subSenderId, curr);

        uint256 withdrawn = user.updateSubSender(
            subSenderId,
            toppedUp,
            withdraw,
            amtPerSec,
            curr,
            newReceivers
        );

        setCurrSubSenderWeights(user, subSenderId, newReceivers);
        assertEq(withdrawn, withdraw, "expected amount not withdrawn");
        assertWithdrawableSubSender(user, subSenderId, balanceTo);
        assertBalance(user, expectedBalance);
        assertEq(
            user.getAmtPerSecSubSender(subSenderId),
            expectedAmtPerSec,
            "Invalid amtPerSec after updateSender"
        );
        assertSubSenderReceivers(user, subSenderId, newReceivers);
    }

    function assertWithdrawableSubSender(
        PoolUser user,
        uint256 subSenderId,
        uint128 expected
    ) internal {
        assertEq(user.withdrawableSubSender(subSenderId), expected, "Invalid withdrawable");
    }

    function assertSubSenderReceivers(
        PoolUser user,
        uint256 subSenderId,
        ReceiverWeight[] memory list
    ) internal {
        bytes32 actual = user.getSubSenderReceiverWeightsHash(subSenderId);
        bytes32 expected = user.hashReceiverWeights(list);
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
            user.getAmtPerSecUnchanged(),
            getCurrSubSenderWeights(user, subSenderId)
        );
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
            getCurrWeights(user)
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
        (uint128 actualCollected, uint128 actualDripped) = user.collectable();
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
