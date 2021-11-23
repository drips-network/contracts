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

/// @notice Drips hub contract. Automatically sends funds to a configurable set of receivers.
///
/// The contract has 2 types of users: the senders and the receivers.
///
/// A sender has some funds and a set of addresses of receivers, to whom they want to send funds.
/// As soon as the sender balance is enough to cover at least 1 second of funding
/// of the configured receivers, sending automatically begins.
/// Every second funds are deducted from the sender balance and sent to their receivers.
/// The process stops automatically when the sender's balance is not enough to cover another second.
///
/// A single address can act as any number of independent senders by using accounts.
/// An account is identified by a user address and an account identifier.
/// The sender and their accounts' configurations are independent and they have separate balances.
///
/// A receiver has a balance, from which they can `collect` funds sent by the senders.
/// The available amount is updated every `cycleSecs` seconds,
/// so recently sent funds may not be `collect`able immediately.
/// `cycleSecs` is a constant configured when the drips hub is deployed.
///
/// A single address can be used as a receiver, a sender
/// or any number of accounts, even at the same time.
/// It will have multiple balances in the contract, one with received funds, one with funds
/// being sent and one with funds being sent for each used account.
/// These balances have no connection between them and no shared configuration.
/// In order to send received funds, they must be first collected and then
/// added to the sender balance if they are to be sent through the contract.
///
/// The concept of something happening periodically, e.g. every second or every `cycleSecs` are
/// only high-level abstractions for the user, Ethereum isn't really capable of scheduling work.
/// The actual implementation emulates that behavior by calculating the results of the scheduled
/// events based on how many seconds have passed and only when a user needs their outcomes.
///
/// The contract assumes that all amounts in the system can be stored in signed 128-bit integers.
/// It's guaranteed to be safe only when working with assets with supply lower than `2 ^ 127`.
abstract contract DripsHub {
    /// @notice On every timestamp `T`, which is a multiple of `cycleSecs`, the receivers
    /// gain access to funds collected during `T - cycleSecs` to `T - 1`.
    uint64 public immutable cycleSecs;
    /// @notice Timestamp at which all funding periods must be finished
    uint64 internal constant MAX_TIMESTAMP = type(uint64).max - 2;
    /// @notice Maximum number of receivers of a single sender.
    /// Limits costs of changes in sender's configuration.
    uint32 public constant MAX_RECEIVERS = 100;
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits costs of dripping.
    uint32 public constant MAX_DRIPS_RECEIVERS = 200;
    /// @notice The total drips weights of a user
    uint32 public constant TOTAL_DRIPS_WEIGHTS = 1_000_000;

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
    /// a sender's account and a receiver is updated.
    /// This is caused by the sender updating their account's parameters.
    /// Funds are being sent on every second between the event block's timestamp (inclusively) and
    /// `endTime` (exclusively) or until the timestamp of the next stream update (exclusively).
    /// @param senderAddr The address of the sender of the updated stream
    /// @param account The sender's account
    /// @param receiver The receiver of the updated stream
    /// @param amtPerSec The new amount per second sent from the sender to the receiver
    /// or 0 if sending is stopped
    /// @param endTime The timestamp when the funds stop being sent,
    /// always larger than the block timestamp or equal to it if sending is stopped
    event SenderToReceiverUpdated(
        address indexed senderAddr,
        uint256 indexed account,
        address indexed receiver,
        uint128 amtPerSec,
        uint64 endTime
    );

    /// @notice Emitted when a sender is updated
    /// @param sender The updated sender
    /// @param balance The new sender's balance
    /// @param receivers The new list of the sender's receivers.
    event SenderUpdated(address indexed sender, uint128 balance, Receiver[] receivers);

    /// @notice Emitted when a sender account is updated
    /// @param senderAddr The address of the sender
    /// @param account The sender's account
    /// @param balance The account's balance
    /// @param receivers The new list of the account's receivers.
    event SenderUpdated(
        address indexed senderAddr,
        uint256 indexed account,
        uint128 balance,
        Receiver[] receivers
    );

    /// @notice Emitted when the user's drips receivers list is updated.
    /// @param user The user
    /// @param receivers The list of the user's drips receivers.
    event DripsReceiversUpdated(address indexed user, DripsReceiver[] receivers);

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

    /// @notice Emitted when funds are given from the user to the receiver.
    /// @param user The address of the user
    /// @param receiver The receiver
    /// @param amt The given amount
    event Given(address indexed user, address indexed receiver, uint128 amt);

    /// @notice Emitted when funds are given from the user's account to the receiver.
    /// @param user The address of the user
    /// @param account The user's account
    /// @param receiver The receiver
    /// @param amt The given amount
    event Given(
        address indexed user,
        uint256 indexed account,
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

    struct UserOrAccount {
        bool isAccount;
        address user;
        uint256 account;
    }

    /// @notice Current drips configuration hash, see `hashDripsReceivers`.
    /// The key is the user address.
    mapping(address => bytes32) public dripsReceiversHash;
    /// @notice Current sender state hash, see `hashSenderState`.
    /// The key is the sender address.
    mapping(address => bytes32) internal senderStateHashes;
    /// @notice Current sender's account state hash, see `hashSenderState`.
    /// The key are the sender address and the account.
    mapping(address => mapping(uint256 => bytes32)) internal senderAccountStateHashes;

    /// @notice Details about all the receivers, the key is the owner's address
    mapping(address => ReceiverState) internal receiverStates;

    /// @param _cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of funds being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 _cycleSecs) {
        cycleSecs = _cycleSecs;
    }

    /// @notice Returns amount of received funds available for collection for a user
    /// @param user The user
    /// @param currReceivers The list of the user's current drips receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the sender's receivers
    function collectable(address user, DripsReceiver[] calldata currReceivers)
        public
        view
        returns (uint128 collected, uint128 dripped)
    {
        ReceiverState storage receiver = receiverStates[user];
        _assertCurrDripsReceivers(user, currReceivers);

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
    /// @param user The user
    /// @param currReceivers The list of the user's current drips receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the sender's receivers
    function collect(address user, DripsReceiver[] calldata currReceivers)
        public
        returns (uint128 collected, uint128 dripped)
    {
        (collected, dripped) = _collectInternal(user, currReceivers);
        _transfer(user, int128(collected));
    }

    /// @notice Counts cycles which will need to be analyzed when collecting or flushing.
    /// This function can be used to detect that there are too many cycles
    /// to analyze in a single transaction and flushing is needed.
    /// @param user The user
    /// @return flushable The number of cycles which can be flushed
    function flushableCycles(address user) public view returns (uint64 flushable) {
        uint64 nextCollectedCycle = receiverStates[user].nextCollectedCycle;
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
    /// @param user The user
    /// @param maxCycles The maximum number of flushed cycles.
    /// If too low, flushing will be cheap, but will cut little gas from the next collection.
    /// If too high, flushing may become too expensive to fit in a single transaction.
    /// @return flushable The number of cycles which can be flushed
    function flushCycles(address user, uint64 maxCycles) public returns (uint64 flushable) {
        flushable = flushableCycles(user);
        uint64 cycles = maxCycles < flushable ? maxCycles : flushable;
        flushable -= cycles;
        uint128 collected = _flushCyclesInternal(user, cycles);
        if (collected > 0) receiverStates[user].collectable += collected;
    }

    /// @notice Removes from the history and returns the amount of received
    /// funds available for collection by the user
    /// @param user The user
    /// @param currReceivers The list of the user's current drips receivers.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the sender's receivers
    function _collectInternal(address user, DripsReceiver[] calldata currReceivers)
        internal
        returns (uint128 collected, uint128 dripped)
    {
        ReceiverState storage receiver = receiverStates[user];
        _assertCurrDripsReceivers(user, currReceivers);

        // Collectable independently from cycles
        collected = receiver.collectable;
        if (collected > 0) receiver.collectable = 0;

        // Collectable from cycles
        uint64 cycles = flushableCycles(user);
        collected += _flushCyclesInternal(user, cycles);

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
                emit Dripped(user, dripsAddr, dripAmt);
            }
            collected -= dripped;
        }
        emit Collected(user, collected, dripped);
    }

    /// @notice Collects and clears user's cycles
    /// @param user The user
    /// @param count The number of flushed cycles.
    /// @return collectedAmt The collected amount
    function _flushCyclesInternal(address user, uint64 count)
        internal
        returns (uint128 collectedAmt)
    {
        if (count == 0) return 0;
        ReceiverState storage receiver = receiverStates[user];
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

    /// @notice Gives funds from the user or their account to the receiver.
    /// The receiver can collect them immediately.
    /// @param userOrAccount The user or their account
    /// @param receiver The receiver
    /// @param amt The given amount
    function _give(
        UserOrAccount memory userOrAccount,
        address receiver,
        uint128 amt
    ) internal {
        receiverStates[receiver].collectable += amt;
        if (userOrAccount.isAccount) {
            emit Given(userOrAccount.user, userOrAccount.account, receiver, amt);
        } else {
            emit Given(userOrAccount.user, receiver, amt);
        }
        _transfer(userOrAccount.user, -int128(amt));
    }

    /// @notice Current sender state hash, see `hashSenderState`.
    function senderStateHash(address sender) public view returns (bytes32) {
        return senderStateHashes[sender];
    }

    /// @notice Current sender's account state hash, see `hashSenderState`.
    function senderStateHash(address sender, uint256 account) public view returns (bytes32) {
        return senderAccountStateHashes[sender][account];
    }

    /// @notice Updates all the sender's parameters.
    /// Transfers funds to or from the sender to fulfill the update of the balance.
    /// @param userOrAccount The user or their account
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// If this is the first update of the sender, pass an empty array.
    /// @param balanceDelta The sender balance change to be applied.
    /// Positive to add funds to the sender balance, negative to remove them.
    /// @param newReceivers The new list of the sender's receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new sender balance.
    /// Pass it as `lastBalance` when updating the user for the next time.
    /// @return realBalanceDelta The actually applied balance change.
    function _updateSender(
        UserOrAccount memory userOrAccount,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) internal returns (uint128 newBalance, int128 realBalanceDelta) {
        _assertSenderState(userOrAccount, lastUpdate, lastBalance, currReceivers);
        uint128 newAmtPerSec = _assertReceiversValid(newReceivers);
        uint128 currAmtPerSec = _totalAmtPerSec(currReceivers);
        uint64 currEndTime = _sendingEndTime(lastUpdate, lastBalance, currAmtPerSec);
        (newBalance, realBalanceDelta) = _updateSenderBalance(
            lastUpdate,
            lastBalance,
            currEndTime,
            currAmtPerSec,
            balanceDelta
        );
        uint64 newEndTime = _sendingEndTime(_currTimestamp(), newBalance, newAmtPerSec);
        _updateStreams(userOrAccount, currReceivers, currEndTime, newReceivers, newEndTime);
        _storeSenderState(userOrAccount, newBalance, newReceivers);
        _emitSenderUpdated(userOrAccount, newBalance, newReceivers);
        _transfer(userOrAccount.user, -realBalanceDelta);
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
    /// @param currAmtPerSec The sender's total amount per second
    /// @param balanceDelta The sender balance change to be applied.
    /// Positive to add funds to the sender balance, negative to remove them.
    /// @return newBalance The new sender balance.
    /// Pass it as `lastBalance` when updating the user for the next time.
    /// @return realBalanceDelta The actually applied balance change.
    function _updateSenderBalance(
        uint64 lastUpdate,
        uint128 lastBalance,
        uint64 currEndTime,
        uint128 currAmtPerSec,
        int128 balanceDelta
    ) internal view returns (uint128 newBalance, int128 realBalanceDelta) {
        if (currEndTime > _currTimestamp()) currEndTime = _currTimestamp();
        uint128 sent = (currEndTime - lastUpdate) * currAmtPerSec;
        int128 currBalance = int128(lastBalance - sent);
        int136 balance = currBalance + int136(balanceDelta);
        if (balance < 0) balance = 0;
        return (uint128(uint136(balance)), int128(balance - currBalance));
    }

    /// @notice Emit a relevant event when a sender is updated.
    /// @param userOrAccount The user or their account
    /// @param balance The new sender balance.
    /// @param receivers The new list of the sender's receivers.
    function _emitSenderUpdated(
        UserOrAccount memory userOrAccount,
        uint128 balance,
        Receiver[] calldata receivers
    ) internal {
        if (userOrAccount.isAccount) {
            emit SenderUpdated(userOrAccount.user, userOrAccount.account, balance, receivers);
        } else {
            emit SenderUpdated(userOrAccount.user, balance, receivers);
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
        UserOrAccount memory userOrAccount,
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
            _emitStreamUpdated(userOrAccount, receiver, uint128(newAmt), newEndTime);
            // The receiver was never used, initialize it.
            if (!pickCurr && receiverStates[receiver].nextCollectedCycle == 0) {
                receiverStates[receiver].nextCollectedCycle = _currTimestamp() / cycleSecs + 1;
            }
        }
    }

    /// @notice Emit a relevant event when a stream is updated.
    /// @param userOrAccount The user or their account
    /// @param receiver The receiver of the updated stream.
    /// @param amtPerSec The new amount per second sent from the sender to the receiver
    /// or 0 if sending is stopped.
    /// @param endTime The timestamp when sending is supposed to end.
    function _emitStreamUpdated(
        UserOrAccount memory userOrAccount,
        address receiver,
        uint128 amtPerSec,
        uint64 endTime
    ) internal {
        if (amtPerSec == 0) endTime = _currTimestamp();
        if (userOrAccount.isAccount) {
            emit SenderToReceiverUpdated(
                userOrAccount.user,
                userOrAccount.account,
                receiver,
                amtPerSec,
                endTime
            );
        } else {
            emit SenderToReceiverUpdated(userOrAccount.user, receiver, amtPerSec, endTime);
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

    /// @notice Asserts that the sender state is the currently used one.
    /// @param userOrAccount The user or their account
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// If this is the first update of the sender, pass an empty array.
    function _assertSenderState(
        UserOrAccount memory userOrAccount,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers
    ) internal view {
        bytes32 expectedHash;
        if (userOrAccount.isAccount) {
            expectedHash = senderAccountStateHashes[userOrAccount.user][userOrAccount.account];
        } else {
            expectedHash = senderStateHashes[userOrAccount.user];
        }
        bytes32 actualHash = hashSenderState(lastUpdate, lastBalance, currReceivers);
        require(actualHash == expectedHash, "Invalid provided sender state");
    }

    /// @notice Stores the hash of the updated sender state to be used in `_assertSenderState`.
    /// @param userOrAccount The user or their account
    /// @param newBalance The new sender balance.
    /// @param newReceivers The new list of the sender's receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    function _storeSenderState(
        UserOrAccount memory userOrAccount,
        uint128 newBalance,
        Receiver[] calldata newReceivers
    ) internal {
        bytes32 stateHash = hashSenderState(_currTimestamp(), newBalance, newReceivers);
        if (userOrAccount.isAccount) {
            senderAccountStateHashes[userOrAccount.user][userOrAccount.account] = stateHash;
        } else {
            senderStateHashes[userOrAccount.user] = stateHash;
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
    /// @param user The user
    /// @param currReceivers The list of the user's drips receivers which is currently in use.
    /// If this function is called for the first time for the user, should be an empty array.
    /// @param newReceivers The new list of the user's drips receivers.
    /// Must be sorted by the drips receivers' addresses, deduplicated and without 0 weights.
    /// Each drips receiver will be getting `weight / TOTAL_DRIPS_WEIGHTS`
    /// share of the funds collected by the user.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the sender's receivers
    function _setDripsReceivers(
        address user,
        DripsReceiver[] calldata currReceivers,
        DripsReceiver[] calldata newReceivers
    ) internal returns (uint128 collected, uint128 dripped) {
        (collected, dripped) = _collectInternal(user, currReceivers);
        _assertDripsReceiversValid(newReceivers);
        dripsReceiversHash[user] = hashDripsReceivers(newReceivers);
        emit DripsReceiversUpdated(user, newReceivers);
        _transfer(user, int128(collected));
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
    /// @param user The user
    /// @param currReceivers The list of the user's current drips receivers.
    function _assertCurrDripsReceivers(address user, DripsReceiver[] calldata currReceivers)
        internal
        view
    {
        require(
            hashDripsReceivers(currReceivers) == dripsReceiversHash[user],
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

    /// @notice Called when funds need to be transferred between the user and the drips hub.
    /// The function must be called no more than once per transaction.
    /// @param user The user
    /// @param amt The transferred amount.
    /// Positive to send funds to the user, negative to send from them.
    function _transfer(address user, int128 amt) internal virtual;

    /// @notice Sets amt delta of a user on a given timestamp
    /// @param user The user
    /// @param timestamp The timestamp from which the delta takes effect
    /// @param amtPerSecDelta Change of the per-second receiving rate
    function _setDelta(
        address user,
        uint64 timestamp,
        int128 amtPerSecDelta
    ) internal {
        if (amtPerSecDelta == 0) return;
        mapping(uint64 => AmtDelta) storage amtDeltas = receiverStates[user].amtDeltas;
        // In order to set a delta on a specific timestamp it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint64 thisCycle = timestamp / cycleSecs + 1;
        uint64 nextCycleSecs = timestamp % cycleSecs;
        uint64 thisCycleSecs = cycleSecs - nextCycleSecs;
        amtDeltas[thisCycle].thisCycle += int128(uint128(thisCycleSecs)) * amtPerSecDelta;
        amtDeltas[thisCycle].nextCycle += int128(uint128(nextCycleSecs)) * amtPerSecDelta;
    }

    function _userOrAccount(address user) internal pure returns (UserOrAccount memory) {
        return UserOrAccount({isAccount: false, user: user, account: 0});
    }

    function _userOrAccount(address user, uint256 account)
        internal
        pure
        returns (UserOrAccount memory)
    {
        return UserOrAccount({isAccount: true, user: user, account: account});
    }

    function _currTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp);
    }
}
