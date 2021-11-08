// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

struct Receiver {
    address receiver;
    uint128 amtPerSec;
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
    /// @notice Maximum value of drips fraction
    uint32 public constant MAX_DRIPS_FRACTION = 1_000_000;
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
    /// @param balance The sender's balance since the event block's timestamp
    /// @param dripsFraction The fraction of received funds to be dripped.
    /// A value from 0 to `MAX_DRIPS_FRACTION` inclusively,
    /// where 0 means no dripping and `MAX_DRIPS_FRACTION` dripping everything.
    /// @param receivers The list of the user's receivers.
    event SenderUpdated(
        address indexed sender,
        uint128 balance,
        uint32 dripsFraction,
        Receiver[] receivers
    );

    /// @notice Emitted when a sender is updated
    /// @param senderAddr The address of the sender
    /// @param subSenderId The id of the sender's updated sub-sender
    /// @param balance The sender's balance since the event block's timestamp
    /// @param receivers The list of the user's receivers.
    event SubSenderUpdated(
        address indexed senderAddr,
        uint256 indexed subSenderId,
        uint128 balance,
        Receiver[] receivers
    );

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
    /// @param amt The sent amount
    event Given(address indexed giver, address indexed receiver, uint128 amt);

    /// @notice Emitted when funds are given from the sub-sender to the receiver.
    /// @param giver The address of the giver
    /// @param subSenderId The ID of the giver's sub-sender
    /// @param receiver The receiver
    /// @param amt The sent amount
    event GivenFromSubSender(
        address indexed giver,
        uint256 indexed subSenderId,
        address indexed receiver,
        uint128 amt
    );

    struct Sender {
        // Timestamp at which the funding period has started
        uint64 startTime;
        // The amount available when the funding period has started
        uint128 startBalance;
        // The fraction of received funds to be dripped.
        // Always has value from 0 to `MAX_DRIPS_FRACTION` inclusively,
        // where 0 means no dripping and `MAX_DRIPS_FRACTION` dripping everything.
        uint32 dripsFraction;
        // --- SLOT BOUNDARY
        // Keccak256 of the ABI-encoded list of `Receiver`s describing receivers of the sender
        bytes32 receiversHash;
    }

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

    /// @dev Details about all the senders, the key is the owner's address
    mapping(address => Sender) internal senders;
    /// @dev Details about all the sub-senders, the keys is the owner address and the sub-sender ID
    mapping(address => mapping(uint256 => Sender)) internal subSenders;
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
    /// @param currReceivers The list of the user's current receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the user's receivers
    function collectable(address receiverAddr, Receiver[] calldata currReceivers)
        public
        view
        returns (uint128 collected, uint128 dripped)
    {
        ReceiverState storage receiver = receiverStates[receiverAddr];
        _assertCurrReceivers(senders[receiverAddr], currReceivers);

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
            Sender storage sender = senders[receiverAddr];
            dripped = uint128((uint160(collected) * sender.dripsFraction) / MAX_DRIPS_FRACTION);
            collected -= dripped;
        }
    }

    /// @notice Collects all received funds available for the user and sends them to that user
    /// @param receiverAddr The address of the receiver
    /// @param currReceivers The list of the user's current receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the user's receivers
    function collect(address receiverAddr, Receiver[] calldata currReceivers)
        public
        returns (uint128 collected, uint128 dripped)
    {
        (collected, dripped) = _collectInternal(receiverAddr, currReceivers);
        emit Collected(receiverAddr, collected, dripped);
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
    /// @param currReceivers The list of the user's current receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the user's receivers
    function _collectInternal(address receiverAddr, Receiver[] calldata currReceivers)
        internal
        returns (uint128 collected, uint128 dripped)
    {
        ReceiverState storage receiver = receiverStates[receiverAddr];
        Sender storage sender = senders[receiverAddr];
        _assertCurrReceivers(sender, currReceivers);

        // Collectable independently from cycles
        collected = receiver.collectable;
        if (collected > 0) receiver.collectable = 0;

        // Collectable from cycles
        uint64 cycles = flushableCycles(receiverAddr);
        collected += _flushCyclesInternal(receiverAddr, cycles);

        // Dripped when collected
        if (collected > 0 && currReceivers.length > 0 && sender.dripsFraction > 0) {
            uint256 drippable = (uint256(collected) * sender.dripsFraction) / MAX_DRIPS_FRACTION;
            uint128 totalAmtPerSec = _totalAmtPerSec(currReceivers);
            uint128 drippedAmtPerSec = 0;
            for (uint256 i = 0; i < currReceivers.length; i++) {
                drippedAmtPerSec += currReceivers[i].amtPerSec;
                uint128 dripAmt = uint128((drippable * drippedAmtPerSec) / totalAmtPerSec) -
                    dripped;
                dripped += dripAmt;
                address dripsAddr = currReceivers[i].receiver;
                receiverStates[dripsAddr].collectable += dripAmt;
                emit Dripped(receiverAddr, dripsAddr, dripAmt);
            }
            collected -= dripped;
        }
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
    /// @param giverAddr The address of the giver
    /// @param receiverAddr The receiver
    /// @param amt The given amount
    function _giveInternal(
        address giverAddr,
        address receiverAddr,
        uint128 amt
    ) internal {
        emit Given(giverAddr, receiverAddr, amt);
        _giveFromAnyGiver(giverAddr, receiverAddr, amt);
    }

    /// @notice Gives funds from the sub-sender to the receiver.
    /// The receiver can collect them immediately.
    /// @param giverAddr The address of the giver
    /// @param subSenderId The ID of the giver sub-sender
    /// @param receiverAddr The receiver
    /// @param amt The given amount
    function _giveFromSubSenderInternal(
        address giverAddr,
        uint256 subSenderId,
        address receiverAddr,
        uint128 amt
    ) internal {
        emit GivenFromSubSender(giverAddr, subSenderId, receiverAddr, amt);
        _giveFromAnyGiver(giverAddr, receiverAddr, amt);
    }

    /// @notice Gives funds to the receiver.
    /// The receiver can collect them immediately.
    /// @param giverAddr The address of the giver
    /// @param receiverAddr The receiver
    /// @param amt The given amount
    function _giveFromAnyGiver(
        address giverAddr,
        address receiverAddr,
        uint128 amt
    ) internal {
        receiverStates[receiverAddr].collectable += amt;
        _transfer(giverAddr, -int128(amt));
    }

    /// @notice Collects received funds and updates all the sender parameters of the user.
    /// See `_updateAnySender` for more details.
    /// @param senderAddr The address of the sender
    /// @return withdrawn The withdrawn amount which should be sent to the user.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` is used.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the user's receivers
    function _updateSenderInternal(
        address senderAddr,
        uint128 topUpAmt,
        uint128 withdrawAmt,
        uint32 dripsFraction,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    )
        internal
        returns (
            uint128 withdrawn,
            uint128 collected,
            uint128 dripped
        )
    {
        (collected, dripped) = _collectInternal(senderAddr, currReceivers);
        Sender memory sender = senders[senderAddr];
        withdrawn = _updateAnySender(
            sender,
            _senderId(senderAddr),
            topUpAmt,
            withdrawAmt,
            dripsFraction,
            currReceivers,
            newReceivers
        );
        senders[senderAddr] = sender;
        emit SenderUpdated(senderAddr, sender.startBalance, sender.dripsFraction, newReceivers);
        _transfer(senderAddr, int128(withdrawn) + int128(collected) - int128(topUpAmt));
    }

    /// @notice Updates all the parameters of the sender's sub-sender.
    /// See `_updateAnySender` for more details.
    /// @param senderAddr The address of the sender
    /// @param subSenderId The id of the sender's sub-sender
    function _updateSubSenderInternal(
        address senderAddr,
        uint256 subSenderId,
        uint128 topUpAmt,
        uint128 withdrawAmt,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) internal returns (uint128 withdrawn) {
        Sender memory sender = subSenders[senderAddr][subSenderId];
        withdrawn = _updateAnySender(
            sender,
            _subSenderId(senderAddr, subSenderId),
            topUpAmt,
            withdrawAmt,
            0,
            currReceivers,
            newReceivers
        );
        subSenders[senderAddr][subSenderId] = sender;
        emit SubSenderUpdated(senderAddr, subSenderId, sender.startBalance, newReceivers);
        _transfer(senderAddr, int128(withdrawn) - int128(topUpAmt));
    }

    /// @notice Updates all the sender's parameters.
    /// Tops up and withdraws unsent funds from the balance of the sender.
    /// @param sender The updated sender
    /// @param senderId The sender id
    /// @param topUpAmt The topped up amount.
    /// @param withdrawAmt The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param dripsFraction The fraction of received funds to be dripped.
    /// Must be a value from 0 to `MAX_DRIPS_FRACTION` inclusively,
    /// where 0 means no dripping and `MAX_DRIPS_FRACTION` dripping everything.
    /// @param currReceivers The list of the user's receivers which is currently in use.
    /// If this function is called for the first time for the user, should be an empty array.
    /// @param newReceivers The new list of the user's receivers.
    /// @return withdrawn The withdrawn amount which should be sent to the user.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` is used.
    function _updateAnySender(
        Sender memory sender,
        SenderId memory senderId,
        uint128 topUpAmt,
        uint128 withdrawAmt,
        uint32 dripsFraction,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) internal returns (uint128 withdrawn) {
        _assertCurrReceiversHash(sender.receiversHash, currReceivers);
        uint128 newAmtPerSec = _setReceiversHash(sender, newReceivers);
        _setDripsFraction(sender, dripsFraction);
        uint128 currAmtPerSec = _totalAmtPerSec(currReceivers);
        uint64 currEndTime = _sendingEndTime(sender, currAmtPerSec);
        withdrawn = _updateSenderBalance(sender, topUpAmt, withdrawAmt, currAmtPerSec, currEndTime);
        sender.startTime = _currTimestamp();
        uint64 newEndTime = _sendingEndTime(sender, newAmtPerSec);
        _updateStreams(senderId, currReceivers, newReceivers, currEndTime, newEndTime);
    }

    /// @notice Updates sender's `startBalance`.
    /// @param sender The updated sender.
    /// @param topUpAmt The topped up amount.
    /// @param withdrawAmt The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param amtPerSec The sender's total amount per second
    /// @param endTime Time when sending was supposed to stop.
    /// @return withdrawn The withdrawn amount which should be sent to the user.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` is used.
    function _updateSenderBalance(
        Sender memory sender,
        uint128 topUpAmt,
        uint128 withdrawAmt,
        uint128 amtPerSec,
        uint64 endTime
    ) internal view returns (uint128 withdrawn) {
        if (endTime > _currTimestamp()) endTime = _currTimestamp();
        sender.startBalance -= (endTime - sender.startTime) * amtPerSec;
        sender.startBalance += topUpAmt;
        if (withdrawAmt == WITHDRAW_ALL) withdrawAmt = sender.startBalance;
        require(withdrawAmt <= sender.startBalance, "Not enough funds in the sender account");
        sender.startBalance -= withdrawAmt;
        return withdrawAmt;
    }

    /// @notice Updates streams in the receivers' `amtDeltas`.
    /// @param currReceivers The list of the user's receivers which is currently in use.
    /// If this function is called for the first time for the user, should be an empty array.
    /// @param newReceivers The new list of the user's receivers.
    /// @param currEndTime Time when sending using `currReceivers` was supposed to stop.
    /// @param newEndTime Time when sending using `newReceivers` will be supposed to stop.
    function _updateStreams(
        SenderId memory senderId,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers,
        uint64 currEndTime,
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
            emitStreamUpdated(senderId, receiver, uint128(newAmt), newEndTime);
            // The receiver was never used, initialize it.
            if (!pickCurr && receiverStates[receiver].nextCollectedCycle == 0) {
                receiverStates[receiver].nextCollectedCycle = _currTimestamp() / cycleSecs + 1;
            }
        }
    }

    /// @notice Emit a relevant event when a stream is updated.
    /// @param senderId The id of the sender of the updated stream
    /// @param receiver The receiver of the updated stream
    /// @param amtPerSec The new amount per second sent from the sender to the receiver
    /// or 0 if sending is stopped
    /// @param endTime The timestamp when the funds stop being sent.
    function emitStreamUpdated(
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

    /// @notice Calculates the sending end time for a sender.
    /// @param sender The analyzed sender
    /// @param totalAmtPerSec The sender's total amount per second
    /// @return sendingEndTime The sending end time
    function _sendingEndTime(Sender memory sender, uint128 totalAmtPerSec)
        internal
        view
        returns (uint64 sendingEndTime)
    {
        if (totalAmtPerSec == 0) return _currTimestamp();
        uint256 endTime = sender.startTime + uint256(sender.startBalance / totalAmtPerSec);
        return endTime > MAX_TIMESTAMP ? MAX_TIMESTAMP : uint64(endTime);
    }

    /// @notice Adds the given amount to the senders balance of the user.
    /// @param sender The updated sender
    /// @param amt The topped up amount
    function _topUp(Sender storage sender, uint128 amt) internal {
        if (amt != 0) sender.startBalance += amt;
    }

    /// @notice Returns amount of unsent funds available for withdrawal for the sender
    /// @param senderAddr The address of the sender
    /// @param currReceivers The list of the user's current receivers.
    /// @return balance The available balance
    function withdrawable(address senderAddr, Receiver[] calldata currReceivers)
        public
        view
        returns (uint128)
    {
        return _withdrawableAnySender(senders[senderAddr], currReceivers);
    }

    /// @notice Returns amount of unsent funds available for withdrawal for the sub-sender
    /// @param senderAddr The address of the sender
    /// @param subSenderId The id of the sender's sub-sender
    /// @param currReceivers The list of the sub-sender's current receivers.
    /// @return balance The available balance
    function withdrawableSubSender(
        address senderAddr,
        uint256 subSenderId,
        Receiver[] calldata currReceivers
    ) public view returns (uint128) {
        return _withdrawableAnySender(subSenders[senderAddr][subSenderId], currReceivers);
    }

    /// @notice Returns amount of unsent funds available for withdrawal for the sender.
    /// See `withdrawable` for more details
    /// @param sender The queried sender
    /// @param currReceivers The list of the user's current receivers.
    function _withdrawableAnySender(Sender storage sender, Receiver[] calldata currReceivers)
        internal
        view
        returns (uint128)
    {
        _assertCurrReceivers(sender, currReceivers);
        uint128 amtPerSec = _totalAmtPerSec(currReceivers);
        // Hasn't been sending anything
        if (amtPerSec == 0) {
            return sender.startBalance;
        }
        uint192 alreadySent = uint192(_currTimestamp() - sender.startTime) * amtPerSec;
        if (alreadySent > sender.startBalance) {
            return sender.startBalance % amtPerSec;
        }
        return sender.startBalance - uint128(alreadySent);
    }

    /// @notice Withdraws unsent funds of the user.
    /// @param sender The updated sender
    /// @param amt The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @return withdrawn The actually withdrawn amount.
    /// Equal to `amt` unless `WITHDRAW_ALL` is used.
    function _withdraw(Sender storage sender, uint128 amt) internal returns (uint128 withdrawn) {
        if (amt == 0) return 0;
        uint128 startBalance = sender.startBalance;
        if (amt == WITHDRAW_ALL) amt = startBalance;
        if (amt == 0) return 0;
        require(amt <= startBalance, "Not enough funds in the sender account");
        sender.startBalance = startBalance - amt;
        return amt;
    }

    /// @notice Sets the fraction of received funds to be dripped by the sender.
    /// @param sender The updated sender
    /// @param dripsFraction The fraction of received funds to be dripped.
    /// Must be a value from 0 to `MAX_DRIPS_FRACTION` inclusively,
    /// where 0 means no dripping and `MAX_DRIPS_FRACTION` dripping everything.
    function _setDripsFraction(Sender memory sender, uint32 dripsFraction) internal pure {
        require(dripsFraction <= MAX_DRIPS_FRACTION, "Drip fraction too high");
        sender.dripsFraction = dripsFraction;
    }

    /// @notice Gets the fraction of received funds to be dripped by the provided user.
    /// @param userAddr The address of the user
    /// @return dripsFraction The fraction of received funds to be dripped.
    /// A value from 0 to `MAX_DRIPS_FRACTION` inclusively,
    /// where 0 means no dripping and `MAX_DRIPS_FRACTION` dripping everything.
    function getDripsFraction(address userAddr) public view returns (uint32 dripsFraction) {
        return senders[userAddr].dripsFraction;
    }

    /// @notice Asserts that the list of receivers is the sender's currently used one.
    /// @param sender The sender
    /// @param currReceivers The list of the user's current receivers.
    function _assertCurrReceivers(Sender storage sender, Receiver[] calldata currReceivers)
        internal
        view
    {
        _assertCurrReceiversHash(sender.receiversHash, currReceivers);
    }

    /// @notice Asserts that the list of receivers is the sender's currently used one.
    /// @param receiversHash The receivers list hash
    /// @param currReceivers The list of the user's current receivers.
    function _assertCurrReceiversHash(bytes32 receiversHash, Receiver[] calldata currReceivers)
        internal
        pure
    {
        require(hashReceivers(currReceivers) == receiversHash, "Invalid current receivers");
    }

    /// @notice Calculates the hash of the list of receivers.
    /// @param receivers The list of the receivers.
    /// Must be sorted by the receivers' addresses and deduplicated.
    /// @return receiversHash The hash of the list of receivers.
    function hashReceivers(Receiver[] calldata receivers)
        public
        pure
        returns (bytes32 receiversHash)
    {
        if (receivers.length == 0) return bytes32(0);
        return keccak256(abi.encode(receivers));
    }

    /// @notice Returns the sender's receivers list hash.
    /// @param senderAddr The address of the sender
    /// @return receiversHash The receivers list hash.
    function getReceiversHash(address senderAddr) public view returns (bytes32 receiversHash) {
        return senders[senderAddr].receiversHash;
    }

    /// @notice Returns the sub-sender's receivers list hash.
    /// @param senderAddr The address of the sender
    /// @param subSenderId The id of the sender's sub-sender
    /// @return receiversHash The receivers list hash.
    function getSubSenderReceiversHash(address senderAddr, uint256 subSenderId)
        public
        view
        returns (bytes32 receiversHash)
    {
        return subSenders[senderAddr][subSenderId].receiversHash;
    }

    /// @notice Calculates the total amount per second of all the passed receivers.
    /// @param receivers The list of the receivers.
    /// @return totalAmtPerSec The total amount per second
    function _totalAmtPerSec(Receiver[] calldata receivers)
        internal
        pure
        returns (uint128 totalAmtPerSec)
    {
        for (uint256 i = 0; i < receivers.length; i++) {
            totalAmtPerSec += receivers[i].amtPerSec;
        }
    }

    /// @notice Sets the receivers of the sender.
    /// @param sender The updated sender
    /// @param receivers The new list of the user's receivers
    /// @return totalAmtPerSec The total amount per second
    function _setReceiversHash(Sender memory sender, Receiver[] calldata receivers)
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
        totalAmtPerSec = uint128(amtPerSec);
        sender.receiversHash = hashReceivers(receivers);
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

    function _subSenderId(address senderAddr, uint256 subSenderId)
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
