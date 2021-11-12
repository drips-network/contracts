// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

struct Receiver {
    address receiver;
    uint128 amtPerSec;
}

struct DripsReceiver {
    address receiver;
    uint32 weight;
}

/// @notice Funding pool contract. Automatically sends funds to a configurable set of receivers.
///
/// The contract has 2 types of users: the senders and the receivers.
///
/// A sender has some funds and a set of addresses of receivers, to whom he wants to send funds.
/// In order to send there are 2 conditions, which must be fulfilled:
///
/// 1. There must be funds on his account in this contract.
///    They can be added with `topUp` and removed with `withdraw`.
/// 2. A set of receivers must be non-empty.
///    Receivers can be added, removed and updated with `setReceiver`.
///
/// Each of these functions can be called in any order and at any time, they have immediate effects.
/// When both conditions are fulfilled, every second the configured amount is being sent.
/// It's extracted from the `withdraw`able balance and transferred to the receivers.
/// The process continues automatically until the sender's balance is empty.
///
/// A single address can act as any number of independent senders by using sub-senders.
/// A sub-sender is identified by a user address and an ID.
/// The sender and all sub-senders' configurations are independent and they have separate balances.
///
/// A receiver has an account, from which they can `collect` funds sent by the senders.
/// The available amount is updated every `cycleSecs` seconds,
/// so recently sent funds may not be `collect`able immediately.
/// `cycleSecs` is a constant configured when the pool is deployed.
///
/// A single address can be used as a receiver, a sender or any number of sub-senders,
/// even at the same time.
/// It will have multiple balances in the contract, one with received funds, one with funds
/// being sent and one with funds being sent for each used sub-sender.
/// These balances have no connection between them and no shared configuration.
/// In order to send received funds, they must be first collected and then used to tup up
/// if they are to be sent through the contract.
///
/// The concept of something happening periodically, e.g. every second or every `cycleSecs` are
/// only high-level abstractions for the user, Ethereum isn't really capable of scheduling work.
/// The actual implementation emulates that behavior by calculating the results of the scheduled
/// events based on how many seconds have passed and only when a user needs their outcomes.
///
/// The contract assumes that all amounts in the system can be stored in signed 128-bit integers.
/// It's guaranteed to be safe only when working with assets with supply lower than `2 ^ 127`.
abstract contract Pool {
    /// @notice On every timestamp `T`, which is a multiple of `cycleSecs`, the receivers
    /// gain access to funds collected during `T - cycleSecs` to `T - 1`.
    uint64 public immutable cycleSecs;
    /// @dev Timestamp at which all funding periods must be finished
    uint64 internal constant MAX_TIMESTAMP = type(uint64).max - 2;
    /// @notice Maximum number of receivers of a single sender.
    /// Limits costs of changes in sender's configuration.
    uint32 public constant MAX_RECEIVERS = 100;
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits costs of dripping.
    uint32 public constant MAX_DRIPS_RECEIVERS = 200;
    /// @notice The total drips weights of a user
    uint32 public constant TOTAL_DRIPS_WEIGHTS = 1_000_000;
    /// @notice The amount passed as the withdraw amount to withdraw all the funds
    uint128 public constant WITHDRAW_ALL = type(uint128).max;

    /// @notice Emitted when a direct stream of funds between a sender and a receiver is updated.
    /// This is caused by a sender updating their parameters.
    /// Funds are being sent on every second between the event block's timestamp (inclusively) and
    /// `endTime` (exclusively) or until the timestamp of the next stream update (exclusively).
    /// @param sender The sender of the updated stream
    /// @param receiver The receiver of the updated stream
    /// @param amtPerSec The new amount per second sent from the sender to the receiver
    /// or 0 if sending is stopped
    /// @param endTime The timestamp when the funds stop being sent,
    /// always larger than the block timestamp or equal to it if sending is stopped
    event SenderToReceiverUpdated(
        address indexed sender,
        address indexed receiver,
        uint128 amtPerSec,
        uint64 endTime
    );

    /// @notice Emitted when a direct stream of funds between
    /// a sender's sub-sender and a receiver is updated.
    /// This is caused by a sender updating their sub-sender's parameters.
    /// Funds are being sent on every second between the event block's timestamp (inclusively) and
    /// `endTime` (exclusively) or until the timestamp of the next stream update (exclusively).
    /// @param senderAddr The address of the sender of the updated stream
    /// @param subSenderId The id of the sender's sub-sender
    /// @param receiver The receiver of the updated stream
    /// @param amtPerSec The new amount per second sent from the sender to the receiver
    /// or 0 if sending is stopped
    /// @param endTime The timestamp when the funds stop being sent,
    /// always larger than the block timestamp or equal to it if sending is stopped
    event SubSenderToReceiverUpdated(
        address indexed senderAddr,
        uint256 indexed subSenderId,
        address indexed receiver,
        uint128 amtPerSec,
        uint64 endTime
    );

    /// @notice Emitted when a sender is updated
    /// @param sender The updated sender
    /// @param balance The new sender's balance
    /// @param receivers The new list of the sender's receivers.
    event SenderUpdated(address indexed sender, uint128 balance, Receiver[] receivers);

    /// @notice Emitted when a sub-sender is updated
    /// @param senderAddr The address of the sender
    /// @param subSenderId The id of the sender's updated sub-sender
    /// @param balance The sub-sender's balance
    /// @param receivers The new list of the sub-sender's receivers.
    event SubSenderUpdated(
        address indexed senderAddr,
        uint256 indexed subSenderId,
        uint128 balance,
        Receiver[] receivers
    );

    /// @notice Emitted when the user's drips receivers list is updated.
    /// @param userAddr The user address
    /// @param receivers The list of the user's drips receivers.
    event DripsReceiversUpdated(address indexed userAddr, DripsReceiver[] receivers);

    /// @notice Emitted when a receiver collects funds
    /// @param receiver The collecting receiver
    /// @param collectedAmt The collected amount
    /// @param drippedAmt The amount dripped to the collecting receiver's receivers
    event Collected(address indexed receiver, uint128 collectedAmt, uint128 drippedAmt);

    /// @notice Emitted when funds are dripped from the sender to the receiver.
    /// This is caused by the sender collecting received funds.
    /// @param sender The user which is dripping
    /// @param receiver The user which is receiving the drips
    /// @param amt The dripped amount
    event Dripped(address indexed sender, address indexed receiver, uint128 amt);

    /// @notice Emitted when funds are given to the receiver.
    /// @param giver The address of the giver
    /// @param receiver The receiver
    /// @param amt The given amount
    event Given(address indexed giver, address indexed receiver, uint128 amt);

    /// @notice Emitted when funds are given from the sub-sender to the receiver.
    /// @param giver The address of the giver
    /// @param subSenderId The ID of the giver's sub-sender
    /// @param receiver The receiver
    /// @param amt The given amount
    event GivenFromSubSender(
        address indexed giver,
        uint256 indexed subSenderId,
        address indexed receiver,
        uint128 amt
    );

    struct ReceiverState {
        // The amount collectable independently from cycles
        uint128 collectable;
        // The next cycle to be collected
        uint64 nextCollectedCycle;
        // --- SLOT BOUNDARY
        // The changes of collected amounts on specific cycle.
        // The keys are cycles, each cycle `C` becomes collectable on timestamp `C * cycleSecs`.
        // Values for cycles before `nextCollectedCycle` are guaranteed to be zeroed.
        // This means that the value of `amtDeltas[nextCollectedCycle].thisCycle` is always
        // relative to 0 or in other words it's an absolute value independent from other cycles.
        mapping(uint64 => AmtDelta) amtDeltas;
    }

    struct AmtDelta {
        // Amount delta applied on this cycle
        int128 thisCycle;
        // Amount delta applied on the next cycle
        int128 nextCycle;
    }

    struct SenderId {
        bool isSubSender;
        address senderAddr;
        uint256 subSenderId;
    }

    /// @notice Current drips configuration hash, see `hashDripsReceivers`.
    /// The key is the user address.
    mapping(address => bytes32) public dripsReceiversHash;
    /// @notice Current sender state hashe, see `hashSenderState`.
    /// The key is the sender address.
    mapping(address => bytes32) public senderStateHash;
    /// @notice Current sub-sender state hashe, see `hashSenderState`.
    /// The key are the sender address and the sub-sender ID.
    mapping(address => mapping(uint256 => bytes32)) public subSenderStateHash;

    /// @dev Details about all the receivers, the key is the owner's address
    mapping(address => ReceiverState) internal receiverStates;

    /// @param _cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of funds being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 _cycleSecs) {
        cycleSecs = _cycleSecs;
    }

    /// @notice Returns amount of received funds available for collection
    /// @param receiverAddr The address of the receiver
    /// @param currReceivers The list of the user's current drips receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the sender's receivers
    function collectable(address receiverAddr, DripsReceiver[] calldata currReceivers)
        public
        view
        returns (uint128 collected, uint128 dripped)
    {
        ReceiverState storage receiver = receiverStates[receiverAddr];
        _assertCurrDripsReceivers(receiverAddr, currReceivers);

        // Collectable independently from cycles
        collected = receiver.collectable;

        // Collectable from cycles
        uint64 collectedCycle = receiver.nextCollectedCycle;
        uint64 currFinishedCycle = _currTimestamp() / cycleSecs;
        if (collectedCycle != 0 && collectedCycle <= currFinishedCycle) {
            int128 cycleAmt = 0;
            for (; collectedCycle <= currFinishedCycle; collectedCycle++) {
                cycleAmt += receiver.amtDeltas[collectedCycle].thisCycle;
                collected += uint128(cycleAmt);
                cycleAmt += receiver.amtDeltas[collectedCycle].nextCycle;
            }
        }

        // Dripped when collected
        if (collected > 0 && currReceivers.length > 0) {
            uint32 drippedWeight = 0;
            for (uint256 i = 0; i < currReceivers.length; i++) {
                drippedWeight += currReceivers[i].weight;
            }
            dripped = uint128((uint160(collected) * drippedWeight) / TOTAL_DRIPS_WEIGHTS);
            collected -= dripped;
        }
    }

    /// @notice Collects all received funds available for the user and sends them to that user
    /// @param receiverAddr The address of the receiver
    /// @param currReceivers The list of the user's current drips receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the sender's receivers
    function collect(address receiverAddr, DripsReceiver[] calldata currReceivers)
        public
        returns (uint128 collected, uint128 dripped)
    {
        (collected, dripped) = _collectInternal(receiverAddr, currReceivers);
        _transfer(receiverAddr, int128(collected));
    }

    /// @notice Counts cycles which will need to be analyzed when collecting or flushing.
    /// This function can be used to detect that there are too many cycles
    /// to analyze in a single transaction and flushing is needed.
    /// @param receiverAddr The address of the receiver
    /// @return flushable The number of cycles which can be flushed
    function flushableCycles(address receiverAddr) public view returns (uint64 flushable) {
        uint64 nextCollectedCycle = receiverStates[receiverAddr].nextCollectedCycle;
        if (nextCollectedCycle == 0) return 0;
        uint64 currFinishedCycle = _currTimestamp() / cycleSecs;
        return currFinishedCycle + 1 - nextCollectedCycle;
    }

    /// @notice Flushes uncollected cycles of the user.
    /// Flushed cycles won't need to be analyzed when the user collects from them.
    /// Calling this function does not collect and does not affect the collectable amount.
    ///
    /// This function is needed when collecting funds received over a period so long, that the gas
    /// needed for analyzing all the uncollected cycles can't fit in a single transaction.
    /// Calling this function allows spreading the analysis cost over multiple transactions.
    /// A cycle is never flushed more than once, even if this function is called many times.
    /// @param receiverAddr The address of the receiver
    /// @param maxCycles The maximum number of flushed cycles.
    /// If too low, flushing will be cheap, but will cut little gas from the next collection.
    /// If too high, flushing may become too expensive to fit in a single transaction.
    /// @return flushable The number of cycles which can be flushed
    function flushCycles(address receiverAddr, uint64 maxCycles) public returns (uint64 flushable) {
        ReceiverState storage receiver = receiverStates[receiverAddr];
        flushable = flushableCycles(receiverAddr);
        uint64 cycles = maxCycles < flushable ? maxCycles : flushable;
        flushable -= cycles;
        uint128 collected = _flushCyclesInternal(receiverAddr, cycles);
        if (collected > 0) receiver.collectable += collected;
    }

    /// @notice Removes from the history and returns the amount of received
    /// funds available for collection by the user
    /// @param receiverAddr The address of the receiver
    /// @param currReceivers The list of the user's current drips receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the sender's receivers
    function _collectInternal(address receiverAddr, DripsReceiver[] calldata currReceivers)
        internal
        returns (uint128 collected, uint128 dripped)
    {
        ReceiverState storage receiver = receiverStates[receiverAddr];
        _assertCurrDripsReceivers(receiverAddr, currReceivers);

        // Collectable independently from cycles
        collected = receiver.collectable;
        if (collected > 0) receiver.collectable = 0;

        // Collectable from cycles
        uint64 cycles = flushableCycles(receiverAddr);
        collected += _flushCyclesInternal(receiverAddr, cycles);

        // Dripped when collected
        if (collected > 0 && currReceivers.length > 0) {
            uint32 drippedWeight = 0;
            for (uint256 i = 0; i < currReceivers.length; i++) {
                drippedWeight += currReceivers[i].weight;
                uint128 dripAmt = uint128(
                    (uint160(collected) * drippedWeight) / TOTAL_DRIPS_WEIGHTS - dripped
                );
                dripped += dripAmt;
                address dripsAddr = currReceivers[i].receiver;
                receiverStates[dripsAddr].collectable += dripAmt;
                emit Dripped(receiverAddr, dripsAddr, dripAmt);
            }
            collected -= dripped;
        }
        emit Collected(receiverAddr, collected, dripped);
    }

    /// @notice Collects and clears receiver's cycles
    /// @param receiverAddr The address of the receiver
    /// @param count The number of flushed cycles.
    /// @return collectedAmt The collected amount
    function _flushCyclesInternal(address receiverAddr, uint64 count)
        internal
        returns (uint128 collectedAmt)
    {
        if (count == 0) return 0;
        ReceiverState storage receiver = receiverStates[receiverAddr];
        uint64 cycle = receiver.nextCollectedCycle;
        int128 cycleAmt = 0;
        for (uint256 i = 0; i < count; i++) {
            cycleAmt += receiver.amtDeltas[cycle].thisCycle;
            collectedAmt += uint128(cycleAmt);
            cycleAmt += receiver.amtDeltas[cycle].nextCycle;
            delete receiver.amtDeltas[cycle];
            cycle++;
        }
        // The next cycle delta must be relative to the last collected cycle, which got zeroed.
        // In other words the next cycle delta must be an absolute value.
        if (cycleAmt != 0) receiver.amtDeltas[cycle].thisCycle += cycleAmt;
        receiver.nextCollectedCycle = cycle;
    }

    /// @notice Gives funds to the receiver.
    /// The receiver can collect them immediately.
    /// @param senderId The sender id of the giver
    /// @param receiverAddr The receiver
    /// @param amt The given amount
    function _give(
        SenderId memory senderId,
        address receiverAddr,
        uint128 amt
    ) internal {
        receiverStates[receiverAddr].collectable += amt;
        if (senderId.isSubSender) {
            emit GivenFromSubSender(senderId.senderAddr, senderId.subSenderId, receiverAddr, amt);
        } else {
            emit Given(senderId.senderAddr, receiverAddr, amt);
        }
        _transfer(senderId.senderAddr, -int128(amt));
    }

    /// @notice Updates all the sender's parameters.
    /// Tops up and withdraws unsent funds from the balance of the sender.
    /// @param senderId The sender id
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// If this is the first update of the sender, pass an empty array.
    /// @param topUpAmt The topped up amount.
    /// @param withdrawAmt The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param newReceivers The new list of the sender's receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new sender balance.
    /// Pass it as `lastBalance` when updating the user for the next time.
    /// @return withdrawn The actually withdrawn amount.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` has been used.
    function _updateSender(
        SenderId memory senderId,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        uint128 topUpAmt,
        uint128 withdrawAmt,
        Receiver[] calldata newReceivers
    ) internal returns (uint128 newBalance, uint128 withdrawn) {
        _assertSenderState(senderId, lastUpdate, lastBalance, currReceivers);
        uint128 newAmtPerSec = _assertReceiversValid(newReceivers);
        uint128 currAmtPerSec = _totalAmtPerSec(currReceivers);
        uint64 currEndTime = _sendingEndTime(lastUpdate, lastBalance, currAmtPerSec);
        (newBalance, withdrawn) = _updateSenderBalance(
            lastUpdate,
            lastBalance,
            currEndTime,
            topUpAmt,
            withdrawAmt,
            currAmtPerSec
        );
        uint64 newEndTime = _sendingEndTime(_currTimestamp(), newBalance, newAmtPerSec);
        _updateStreams(senderId, currReceivers, currEndTime, newReceivers, newEndTime);
        _storeSenderState(senderId, newBalance, newReceivers);
        _emitSenderUpdated(senderId, newBalance, newReceivers);
        _transfer(senderId.senderAddr, int128(withdrawn) - int128(topUpAmt));
    }

    /// @notice Validates a list of receivers.
    /// @param receivers The list of sender receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return totalAmtPerSec The total amount per second of all receivers
    function _assertReceiversValid(Receiver[] calldata receivers)
        internal
        pure
        returns (uint128 totalAmtPerSec)
    {
        require(receivers.length <= MAX_RECEIVERS, "Too many receivers");
        uint256 amtPerSec = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            require(receivers[i].amtPerSec != 0, "Receiver amtPerSec is zero");
            amtPerSec += receivers[i].amtPerSec;
            if (i > 0) {
                address prevReceiver = receivers[i - 1].receiver;
                address currReceiver = receivers[i].receiver;
                require(prevReceiver <= currReceiver, "Receivers not sorted by address");
                require(prevReceiver != currReceiver, "Duplicate receivers");
            }
        }
        require(amtPerSec <= type(uint128).max, "Total amtPerSec too high");
        return uint128(amtPerSec);
    }

    /// @notice Updates sender's balance.
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currEndTime Time when sending was supposed to end according to the last update.
    /// @param topUpAmt The topped up amount.
    /// @param withdrawAmt The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param amtPerSec The sender's total amount per second
    /// @return newBalance The new sender balance.
    /// Pass it as `lastBalance` when updating the user for the next time.
    /// @return withdrawn The actually withdrawn amount.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` has been used.
    function _updateSenderBalance(
        uint64 lastUpdate,
        uint128 lastBalance,
        uint64 currEndTime,
        uint128 topUpAmt,
        uint128 withdrawAmt,
        uint128 amtPerSec
    ) internal view returns (uint128 newBalance, uint128 withdrawn) {
        if (currEndTime > _currTimestamp()) currEndTime = _currTimestamp();
        lastBalance -= (currEndTime - lastUpdate) * amtPerSec;
        lastBalance += topUpAmt;
        if (withdrawAmt == WITHDRAW_ALL) withdrawAmt = lastBalance;
        require(withdrawAmt <= lastBalance, "Not enough funds in the sender account");
        lastBalance -= withdrawAmt;
        return (lastBalance, withdrawAmt);
    }

    /// @notice Emit a relevant event when a sender is updated.
    /// @param senderId The id of the sender.
    /// @param balance The new sender balance.
    /// @param receivers The new list of the sender's receivers.
    function _emitSenderUpdated(
        SenderId memory senderId,
        uint128 balance,
        Receiver[] calldata receivers
    ) internal {
        if (senderId.isSubSender) {
            emit SubSenderUpdated(senderId.senderAddr, senderId.subSenderId, balance, receivers);
        } else {
            emit SenderUpdated(senderId.senderAddr, balance, receivers);
        }
    }

    /// @notice Updates streams in the receivers' `amtDeltas`.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// If this is the first update of the sender, pass an empty array.
    /// @param currEndTime Time when sending was supposed to end according to the last update.
    /// @param newReceivers The new list of the sender's receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @param newEndTime Time new when sending is supposed to end.
    function _updateStreams(
        SenderId memory senderId,
        Receiver[] calldata currReceivers,
        uint64 currEndTime,
        Receiver[] calldata newReceivers,
        uint64 newEndTime
    ) internal {
        // Skip iterating over `currReceivers` if funding has run out
        uint256 currIdx = currEndTime > _currTimestamp() ? 0 : currReceivers.length;
        // Skip iterating over `newReceivers` if no new funding is started
        uint256 newIdx = newEndTime > _currTimestamp() ? 0 : newReceivers.length;
        while (true) {
            // Each iteration gets the next stream update and applies it on the receiver.
            // A stream update is composed of two receiver configurations, one current and one new,
            // or from a single receiver configuration if the receiver is being added or removed.
            bool pickCurr = currIdx < currReceivers.length;
            bool pickNew = newIdx < newReceivers.length;
            if (!pickCurr && !pickNew) break;
            if (pickCurr && pickNew) {
                // There are two candidate receiver configurations to create a stream update.
                // Pick both if they describe the same receiver or the one with a lower address.
                // The one with a higher address won't be used in this iteration.
                // Because receiver lists are sorted by addresses and deduplicated,
                // this guarantees that all matching pairs of receiver configurations will be found.
                address currReceiver = currReceivers[currIdx].receiver;
                address newReceiver = newReceivers[newIdx].receiver;
                pickCurr = currReceiver <= newReceiver;
                pickNew = newReceiver <= currReceiver;
            }
            // The stream update parameters
            address receiver;
            int128 currAmt = 0;
            int128 newAmt = 0;
            if (pickCurr) {
                receiver = currReceivers[currIdx].receiver;
                currAmt = int128(currReceivers[currIdx].amtPerSec);
                // Clear the obsolete stream end
                _setDelta(receiver, currEndTime, currAmt);
                currIdx++;
            }
            if (pickNew) {
                receiver = newReceivers[newIdx].receiver;
                newAmt = int128(newReceivers[newIdx].amtPerSec);
                // Apply the new stream end
                _setDelta(receiver, newEndTime, -newAmt);
                newIdx++;
            }
            // Apply the stream update since now
            _setDelta(receiver, _currTimestamp(), newAmt - currAmt);
            _emitStreamUpdated(senderId, receiver, uint128(newAmt), newEndTime);
            // The receiver was never used, initialize it.
            if (!pickCurr && receiverStates[receiver].nextCollectedCycle == 0) {
                receiverStates[receiver].nextCollectedCycle = _currTimestamp() / cycleSecs + 1;
            }
        }
    }

    /// @notice Emit a relevant event when a stream is updated.
    /// @param senderId The id of the sender of the updated stream.
    /// @param receiver The receiver of the updated stream.
    /// @param amtPerSec The new amount per second sent from the sender to the receiver
    /// or 0 if sending is stopped.
    /// @param endTime The timestamp when sending is supposed to end.
    function _emitStreamUpdated(
        SenderId memory senderId,
        address receiver,
        uint128 amtPerSec,
        uint64 endTime
    ) internal {
        if (amtPerSec == 0) endTime = _currTimestamp();
        if (senderId.isSubSender) {
            emit SubSenderToReceiverUpdated(
                senderId.senderAddr,
                senderId.subSenderId,
                receiver,
                amtPerSec,
                endTime
            );
        } else {
            emit SenderToReceiverUpdated(senderId.senderAddr, receiver, amtPerSec, endTime);
        }
    }

    /// @notice Calculates the timestamp when sending is supposed to end.
    /// @param startTime Time when sending is started.
    /// @param startBalance The sender balance when sending is started.
    /// @param totalAmtPerSec The sender's total amount per second.
    /// @return sendingEndTime The sending end time.
    function _sendingEndTime(
        uint64 startTime,
        uint128 startBalance,
        uint128 totalAmtPerSec
    ) internal pure returns (uint64 sendingEndTime) {
        if (totalAmtPerSec == 0) return startTime;
        uint256 endTime = startTime + uint256(startBalance / totalAmtPerSec);
        return endTime > MAX_TIMESTAMP ? MAX_TIMESTAMP : uint64(endTime);
    }

    /// @notice Returns amount of unsent funds available for withdrawal for the sender
    /// @param senderAddr The address of the sender
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// @return withdrawableAmt The withdrawable amount
    function withdrawable(
        address senderAddr,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers
    ) public view returns (uint128 withdrawableAmt) {
        SenderId memory senderId = _senderId(senderAddr);
        return _withdrawable(senderId, lastUpdate, lastBalance, currReceivers);
    }

    /// @notice Returns amount of unsent funds available for withdrawal for the sub-sender
    /// @param senderAddr The address of the sender
    /// @param subSenderId The id of the sender's sub-sender
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// @return withdrawableAmt The withdrawable amount
    function withdrawableSubSender(
        address senderAddr,
        uint256 subSenderId,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers
    ) public view returns (uint128 withdrawableAmt) {
        SenderId memory senderId = _senderId(senderAddr, subSenderId);
        return _withdrawable(senderId, lastUpdate, lastBalance, currReceivers);
    }

    /// @notice Returns amount of unsent funds available for withdrawal for the sender.
    /// @param senderId The id of the sender
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// @return withdrawableAmt The withdrawable amount
    function _withdrawable(
        SenderId memory senderId,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers
    ) internal view returns (uint128 withdrawableAmt) {
        _assertSenderState(senderId, lastUpdate, lastBalance, currReceivers);
        uint128 amtPerSec = _totalAmtPerSec(currReceivers);
        uint192 alreadySent = uint192(_currTimestamp() - lastUpdate) * amtPerSec;
        if (alreadySent > lastBalance) {
            return lastBalance % amtPerSec;
        }
        return lastBalance - uint128(alreadySent);
    }

    /// @notice Asserts that the sender state is the currently used one.
    /// @param senderId The id of the sender
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// If this is the first update of the sender, pass an empty array.
    function _assertSenderState(
        SenderId memory senderId,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers
    ) internal view {
        bytes32 expectedHash;
        if (senderId.isSubSender) {
            expectedHash = subSenderStateHash[senderId.senderAddr][senderId.subSenderId];
        } else {
            expectedHash = senderStateHash[senderId.senderAddr];
        }
        bytes32 actualHash = hashSenderState(lastUpdate, lastBalance, currReceivers);
        require(actualHash == expectedHash, "Invalid provided sender state");
    }

    /// @notice Stores the hash of the updated sender state to be used in `_assertSenderState`.
    /// @param senderId The id of the sender
    /// @param newBalance The new sender balance.
    /// @param newReceivers The new list of the sender's receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    function _storeSenderState(
        SenderId memory senderId,
        uint128 newBalance,
        Receiver[] calldata newReceivers
    ) internal {
        bytes32 stateHash = hashSenderState(_currTimestamp(), newBalance, newReceivers);
        if (senderId.isSubSender) {
            subSenderStateHash[senderId.senderAddr][senderId.subSenderId] = stateHash;
        } else {
            senderStateHash[senderId.senderAddr] = stateHash;
        }
    }

    /// @notice Calculates the hash of the sender state.
    /// It's used to verify if a sender state is the previously configured one.
    /// @param update The timestamp of the update of the sender.
    /// If the sender has never been updated, pass zero.
    /// @param balance The sender balance.
    /// If the sender has never been updated, pass zero.
    /// @param receivers The list of the sender's receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// If the sender has never been updated, pass an empty array.
    /// @return receiversHash The hash of the sender state.
    function hashSenderState(
        uint64 update,
        uint128 balance,
        Receiver[] calldata receivers
    ) public pure returns (bytes32 receiversHash) {
        if (update == 0 && balance == 0 && receivers.length == 0) return bytes32(0);
        return keccak256(abi.encode(receivers, update, balance));
    }

    /// @notice Collects received funds and sets a new list of drips receivers of the user.
    /// @param userAddr The user address
    /// @param currReceivers The list of the user's drips receivers which is currently in use.
    /// If this function is called for the first time for the user, should be an empty array.
    /// @param newReceivers The new list of the user's drips receivers.
    /// Must be sorted by the drips receivers' addresses, deduplicated and without 0 weights.
    /// Each drips receiver will be getting `weight / TOTAL_DRIPS_WEIGHTS`
    /// share of the funds collected by the user.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the sender's receivers
    function _setDripsReceivers(
        address userAddr,
        DripsReceiver[] calldata currReceivers,
        DripsReceiver[] calldata newReceivers
    ) internal returns (uint128 collected, uint128 dripped) {
        (collected, dripped) = _collectInternal(userAddr, currReceivers);
        _assertDripsReceiversValid(newReceivers);
        dripsReceiversHash[userAddr] = hashDripsReceivers(newReceivers);
        emit DripsReceiversUpdated(userAddr, newReceivers);
        _transfer(userAddr, int128(collected));
    }

    /// @notice Validates a list of drips receivers
    /// @param receivers The list of drips receivers
    /// Must be sorted by the drips receivers' addresses, deduplicated and without 0 weights.
    function _assertDripsReceiversValid(DripsReceiver[] calldata receivers) internal pure {
        require(receivers.length <= MAX_DRIPS_RECEIVERS, "Too many drips receivers");
        uint64 totalWeight = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            require(receivers[i].weight != 0, "Drips receiver weight is zero");
            totalWeight += receivers[i].weight;
            if (i > 0) {
                address prevReceiver = receivers[i - 1].receiver;
                address currReceiver = receivers[i].receiver;
                require(prevReceiver <= currReceiver, "Drips receivers not sorted by address");
                require(prevReceiver != currReceiver, "Duplicate drips receivers");
            }
        }
        require(totalWeight <= TOTAL_DRIPS_WEIGHTS, "Drips weights sum too high");
    }

    /// @notice Asserts that the list of drips receivers is the user's currently used one.
    /// @param userAddr The user address
    /// @param currReceivers The list of the user's current drips receivers.
    function _assertCurrDripsReceivers(address userAddr, DripsReceiver[] calldata currReceivers)
        internal
        view
    {
        require(
            hashDripsReceivers(currReceivers) == dripsReceiversHash[userAddr],
            "Invalid current drips receivers"
        );
    }

    /// @notice Calculates the hash of the list of drips receivers.
    /// @param receivers The list of the drips receivers.
    /// Must be sorted by the drips receivers' addresses, deduplicated and without 0 weights.
    /// @return receiversHash The hash of the list of drips receivers.
    function hashDripsReceivers(DripsReceiver[] calldata receivers)
        public
        pure
        returns (bytes32 receiversHash)
    {
        if (receivers.length == 0) return bytes32(0);
        return keccak256(abi.encode(receivers));
    }

    /// @notice Calculates the total amount per second of all the passed receivers.
    /// @param receivers The list of the receivers.
    /// @return totalAmtPerSec The total amount per second of all receivers
    function _totalAmtPerSec(Receiver[] calldata receivers)
        internal
        pure
        returns (uint128 totalAmtPerSec)
    {
        for (uint256 i = 0; i < receivers.length; i++) {
            totalAmtPerSec += receivers[i].amtPerSec;
        }
    }

    /// @notice Called when funds need to be transferred between the user and the pool.
    /// The function must be called no more than once per transaction.
    /// @param userAddr The address of the user.
    /// @param amt The transferred amount.
    /// Positive to send funds to the user, negative to send from them.
    function _transfer(address userAddr, int128 amt) internal virtual;

    /// @notice Sets delta of a single receiver on a given timestamp
    /// @param receiverAddr The address of the receiver
    /// @param timestamp The timestamp from which the delta takes effect
    /// @param amtPerSecDelta Change of the per-second receiving rate
    function _setDelta(
        address receiverAddr,
        uint64 timestamp,
        int128 amtPerSecDelta
    ) internal {
        if (amtPerSecDelta == 0) return;
        mapping(uint64 => AmtDelta) storage amtDeltas = receiverStates[receiverAddr].amtDeltas;
        // In order to set a delta on a specific timestamp it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint64 thisCycle = timestamp / cycleSecs + 1;
        uint64 nextCycleSecs = timestamp % cycleSecs;
        uint64 thisCycleSecs = cycleSecs - nextCycleSecs;
        amtDeltas[thisCycle].thisCycle += int128(uint128(thisCycleSecs)) * amtPerSecDelta;
        amtDeltas[thisCycle].nextCycle += int128(uint128(nextCycleSecs)) * amtPerSecDelta;
    }

    function _senderId(address senderAddr) internal pure returns (SenderId memory) {
        return SenderId({isSubSender: false, senderAddr: senderAddr, subSenderId: 0});
    }

    function _senderId(address senderAddr, uint256 subSenderId)
        internal
        pure
        returns (SenderId memory)
    {
        return SenderId({isSubSender: true, senderAddr: senderAddr, subSenderId: subSenderId});
    }

    function _currTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp);
    }
}
