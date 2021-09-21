// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DSTest} from "ds-test/test.sol";
import {PoolUser, EthPoolUser} from "./User.t.sol";
import {Hevm} from "./BaseTest.t.sol";
import {EthPool, Pool, ReceiverWeight} from "../EthPool.sol";

// TODO split into an abstract PoolTest and EthPoolTest
// when https://github.com/dapphub/dapptools/issues/769 is fixed
contract EthPoolTest is DSTest {
    struct Weight {
        PoolUser user;
        uint32 weight;
    }

    uint64 public constant CYCLE_SECS = 10;

    Hevm internal immutable hevm;

    Pool private pool;

    PoolUser private sender;
    PoolUser private receiver;
    PoolUser private sender1;
    PoolUser private receiver1;
    PoolUser private sender2;
    PoolUser private receiver2;

    constructor() {
        hevm = Hevm(HEVM_ADDRESS);
    }

    function setUp() public virtual {
        pool = getPool();
        sender = createUser();
        receiver = createUser();
        sender1 = createUser();
        receiver1 = createUser();
        sender2 = createUser();
        receiver2 = createUser();
    }

    function getPool() internal virtual returns (Pool) {
        return Pool(new EthPool(CYCLE_SECS));
    }

    function createUser() internal virtual returns (PoolUser) {
        return PoolUser(new EthPoolUser{value: 100 ether}(EthPool(address(pool))));
    }

    function updateSender(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        uint128 amtPerSec
    ) internal {
        updateSender(user, balanceFrom, balanceTo, amtPerSec, new ReceiverWeight[](0));
    }

    function updateSender(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        uint128 amtPerSec,
        Weight memory weight
    ) internal {
        ReceiverWeight[] memory updatedReceivers = new ReceiverWeight[](1);
        updatedReceivers[0] = ReceiverWeight(address(weight.user), weight.weight);
        updateSender(user, balanceFrom, balanceTo, amtPerSec, updatedReceivers);
    }

    function updateSender(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        uint128 amtPerSec,
        Weight memory weight1,
        Weight memory weight2
    ) internal {
        ReceiverWeight[] memory updatedReceivers = new ReceiverWeight[](2);
        updatedReceivers[0] = ReceiverWeight(address(weight1.user), weight1.weight);
        updatedReceivers[1] = ReceiverWeight(address(weight2.user), weight2.weight);
        updateSender(user, balanceFrom, balanceTo, amtPerSec, updatedReceivers);
    }

    function updateSender(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        uint128 amtPerSec,
        Weight memory weight1,
        Weight memory weight2,
        Weight memory weight3
    ) internal {
        ReceiverWeight[] memory updatedReceivers = new ReceiverWeight[](3);
        updatedReceivers[0] = ReceiverWeight(address(weight1.user), weight1.weight);
        updatedReceivers[1] = ReceiverWeight(address(weight2.user), weight2.weight);
        updatedReceivers[2] = ReceiverWeight(address(weight3.user), weight3.weight);
        updateSender(user, balanceFrom, balanceTo, amtPerSec, updatedReceivers);
    }

    function updateSender(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo,
        uint128 amtPerSec,
        ReceiverWeight[] memory updatedReceivers
    ) internal {
        assertWithdrawable(user, balanceFrom);
        uint128 toppedUp = balanceTo > balanceFrom ? balanceTo - balanceFrom : 0;
        uint128 withdraw = balanceTo < balanceFrom ? balanceFrom - balanceTo : 0;
        uint256 expectedBalance = user.balance() + withdraw - toppedUp;
        uint128 expectedAmtPerSec = amtPerSec == pool.AMT_PER_SEC_UNCHANGED()
            ? user.getAmtPerSec()
            : amtPerSec;

        uint256 withdrawn = user.updateSender(toppedUp, withdraw, amtPerSec, updatedReceivers);

        assertEq(withdrawn, withdraw, "expected amount not withdrawn");
        assertWithdrawable(user, balanceTo);
        assertBalance(user, expectedBalance);
        assertEq(user.getAmtPerSec(), expectedAmtPerSec, "Invalid amtPerSec after updateSender");
        // TODO assert list of receivers
    }

    function assertWithdrawable(PoolUser user, uint128 expected) internal {
        assertEq(user.withdrawable(), expected, "Invalid withdrawable");
    }

    function changeBalance(
        PoolUser user,
        uint128 balanceFrom,
        uint128 balanceTo
    ) internal {
        updateSender(user, balanceFrom, balanceTo, pool.AMT_PER_SEC_UNCHANGED());
    }

    function setAmtPerSec(PoolUser user, uint128 amtPerSec) internal {
        uint128 withdrawable = user.withdrawable();
        updateSender(user, withdrawable, withdrawable, amtPerSec);
    }

    function setReceiver(PoolUser user, Weight memory weight) internal {
        uint128 withdrawable = user.withdrawable();
        updateSender(user, withdrawable, withdrawable, pool.AMT_PER_SEC_UNCHANGED(), weight);
    }

    function assertSetReceiverReverts(
        PoolUser user,
        Weight memory weight,
        string memory expectedReason
    ) internal {
        ReceiverWeight[] memory updatedReceivers = new ReceiverWeight[](1);
        updatedReceivers[0] = ReceiverWeight(address(weight.user), weight.weight);
        try user.updateSender(0, 0, pool.AMT_PER_SEC_UNCHANGED(), updatedReceivers) {
            assertTrue(false, "Sender receivers update hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid sender receivers update revert reason");
        }
    }

    function collect(PoolUser user, uint128 expectedAmt) internal {
        collect(user, user, expectedAmt);
    }

    function collect(
        PoolUser user,
        PoolUser collected,
        uint128 expectedAmt
    ) internal {
        assertCollectable(collected, expectedAmt);
        uint256 expectedBalance = collected.balance() + expectedAmt;

        user.collect(address(collected));

        assertCollectable(collected, 0);
        assertBalance(collected, expectedBalance);
    }

    function assertCollectable(PoolUser user, uint128 expected) internal {
        assertEq(user.collectable(), expected, "Invalid collectable");
    }

    function assertBalance(PoolUser user, uint256 expected) internal {
        assertEq(user.balance(), expected, "Invalid balance");
    }

    function warpToCycleEnd() internal {
        warpBy(CYCLE_SECS - (block.timestamp % CYCLE_SECS));
    }

    function warpBy(uint256 secs) internal {
        hevm.warp(block.timestamp + secs);
    }

    function testAllowsSendingToASingleReceiver() public {
        updateSender(sender, 0, 100, 1, Weight(receiver, 1));
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
        updateSender(sender, 0, balance, 1, Weight(receiver, 1));
        warpBy(time);
        // Sender had `time` seconds paying 1 per second
        changeBalance(sender, balance - time, 0);
        warpToCycleEnd();
        // Sender had `time` seconds paying 1 per second
        collect(receiver, time);
    }

    function testAllowsSendingToMultipleReceivers() public {
        updateSender(sender, 0, 6, 3, Weight(receiver1, 1), Weight(receiver2, 2));
        warpToCycleEnd();
        // Sender had 2 seconds paying 1 per second
        collect(receiver1, 2);
        // Sender had 2 seconds paying 2 per second
        collect(receiver2, 4);
    }

    function testSendsSomeFundsFromASingleSenderToTwoReceivers() public {
        updateSender(sender, 0, 100, 2, Weight(receiver1, 1), Weight(receiver2, 1));
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
        updateSender(sender1, 0, 100, 1, Weight(receiver, 1));
        warpBy(2);
        updateSender(sender2, 0, 100, 2, Weight(receiver, 1));
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
        updateSender(sender, 0, CYCLE_SECS + 10, 1, Weight(receiver, 1));
        warpToCycleEnd();
        // Receiver had CYCLE_SECS seconds paying 1 per second
        collect(receiver, CYCLE_SECS);
        warpBy(7);
        // Sender had CYCLE_SECS + 7 seconds paying 1 per second
        changeBalance(sender, 3, 0);
        warpToCycleEnd();
        // Receiver had 7 seconds paying 1 per second
        collect(receiver, 7);
    }

    function testSendsFundsUntilTheyRunOut() public {
        updateSender(sender, 0, 100, 9, Weight(receiver, 1));
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

    function testAllowsToppingUpWhileSending() public {
        updateSender(sender, 0, 100, 10, Weight(receiver, 1));
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
        updateSender(sender, 0, 100, 10, Weight(receiver, 1));
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
        updateSender(sender, 0, balance, 1, Weight(receiver, 1));
        warpBy(10);
        // Sender had 10 seconds paying 1 per second
        changeBalance(sender, balance - 10, 0);
        warpToCycleEnd();
        // Receiver had 10 seconds paying 1 per second
        collect(receiver, 10);
    }

    function testAllowsChangingAmountPerSecondWhileSending() public {
        updateSender(sender, 0, 100, 10, Weight(receiver, 1));
        warpBy(4);
        setAmtPerSec(sender, 9);
        warpBy(4);
        // Sender had 4 seconds paying 10 per second and 4 seconds paying 9 per second
        changeBalance(sender, 24, 0);
        warpToCycleEnd();
        // Receiver had 4 seconds paying 10 per second and 4 seconds paying 9 per second
        collect(receiver, 76);
    }

    function testAllowsSenderUpdateWithTopUpAndWithdrawal() public {
        sender.updateSender(10, 3, 0, new ReceiverWeight[](0));
        assertWithdrawable(sender, 7);
    }

    function testAllowsNoSenderUpdate() public {
        updateSender(sender, 0, 6, 3, Weight(receiver, 1));
        warpBy(1);
        // Sender had 1 second paying 3 per second
        updateSender(sender, 3, 3, pool.AMT_PER_SEC_UNCHANGED());
        warpToCycleEnd();
        collect(receiver, 6);
    }

    function testSendsAmountPerSecondRoundedDownToAMultipleOfWeightsSum() public {
        updateSender(sender, 0, 100, 9, Weight(receiver, 5));
        warpBy(5);
        // Sender had 5 seconds paying 5 per second
        changeBalance(sender, 75, 0);
        warpToCycleEnd();
        // Receiver had 5 seconds paying 5 per second
        collect(receiver, 25);
    }

    function testSendsNothingIfAmountPerSecondIsSmallerThanWeightsSum() public {
        updateSender(sender, 0, 100, 4, Weight(receiver, 5));
        warpBy(5);
        // Sender had 0 paying seconds
        changeBalance(sender, 100, 0);
        warpToCycleEnd();
        // Receiver had 0 paying seconds
        collect(receiver, 0);
    }

    function testAllowsRemovingTheLastReceiverWeightWhenAmountPerSecondIsZero() public {
        updateSender(
            sender,
            0,
            100,
            12,
            Weight(receiver1, 1),
            Weight(receiver2, 1),
            Weight(receiver2, 0)
        );
        warpBy(1);
        // Sender had 1 seconds paying 12 per second
        changeBalance(sender, 88, 0);
        warpToCycleEnd();
        // Receiver1 had 1 seconds paying 12 per second
        collect(receiver1, 12);
        // Receiver2 had 0 paying seconds
        assertCollectable(receiver2, 0);
    }

    function testAllowsChangingReceiverWeightsWhileSending() public {
        updateSender(sender, 0, 100, 12, Weight(receiver1, 1), Weight(receiver2, 1));
        warpBy(3);
        setReceiver(sender, Weight(receiver2, 2));
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
        updateSender(sender, 0, 100, 10, Weight(receiver1, 1), Weight(receiver2, 1));
        warpBy(3);
        setReceiver(sender, Weight(receiver1, 0));
        warpBy(4);
        setReceiver(sender, Weight(receiver2, 0));
        warpBy(10);
        // Sender had 7 seconds paying 10 per second
        changeBalance(sender, 30, 0);
        warpToCycleEnd();
        // Receiver1 had 3 seconds paying 5 per second
        collect(receiver1, 15);
        // Receiver2 had 3 seconds paying 5 per second and 4 seconds paying 10 per second
        collect(receiver2, 55);
    }

    function testLimitsTheTotalWeightsSum() public {
        setReceiver(sender, Weight(receiver1, pool.SENDER_WEIGHTS_SUM_MAX()));
        assertSetReceiverReverts(sender, Weight(receiver2, 1), "Too much total receivers weight");
    }

    function testLimitsTheOverflowingTotalWeightsSum() public {
        setReceiver(sender, Weight(receiver1, 1));
        assertSetReceiverReverts(
            sender,
            Weight(receiver2, type(uint32).max),
            "Too much total receivers weight"
        );
    }

    function testLimitsTheTotalReceiversCount() public {
        ReceiverWeight[] memory receivers = new ReceiverWeight[](pool.SENDER_WEIGHTS_COUNT_MAX());
        for (uint160 i = 0; i < receivers.length; i++) {
            receivers[i] = ReceiverWeight(address(i + 1), 1);
        }
        sender.updateSender(0, 0, pool.AMT_PER_SEC_UNCHANGED(), receivers);
        assertSetReceiverReverts(sender, Weight(receiver, 1), "Too many receivers");
    }

    function testAllowsAnAddressToBeASenderAndAReceiverIndependently() public {
        updateSender(sender, 0, 10, 10, Weight(sender, 10));
        warpBy(1);
        // Sender had 1 second paying 10 per second
        assertWithdrawable(sender, 0);
        warpToCycleEnd();
        // Sender had 1 second paying 10 per second
        collect(sender, 10);
    }

    function testAllowsWithdrawalOfAllFunds() public {
        updateSender(sender, 0, 10, 1, Weight(receiver, 1));
        warpBy(4);
        // Sender had 4 second paying 1 per second
        assertWithdrawable(sender, 6);
        uint256 expectedBalance = sender.balance() + 6;
        sender.updateSender(
            0,
            pool.WITHDRAW_ALL(),
            pool.AMT_PER_SEC_UNCHANGED(),
            new ReceiverWeight[](0)
        );
        assertWithdrawable(sender, 0);
        assertBalance(sender, expectedBalance);
        warpToCycleEnd();
        // Receiver had 4 seconds paying 1 per second
        collect(receiver, 4);
    }

    function testAnybodyCanCallCollect() public {
        updateSender(sender1, 0, 10, 10, Weight(receiver, 1));
        warpToCycleEnd();
        // Receiver had 1 second paying 10 per second
        collect(sender2, receiver, 10);
    }
}
