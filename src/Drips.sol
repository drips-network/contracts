// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

struct DripsReceiver {
    uint256 userId;
    uint128 amtPerSec;
}

library Drips {
    /// @notice Timestamp at which all drips must be finished
    uint64 internal constant MAX_TIMESTAMP = type(uint64).max - 2;
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits cost of changes in drips configuration.
    uint32 internal constant MAX_DRIPS_RECEIVERS = 100;

    /// @notice Emitted when drips from a user to a receiver are updated.
    /// Funds are being dripped on every second between the event block's timestamp (inclusively)
    /// and`endTime` (exclusively) or until the timestamp of the next drips update (exclusively).
    /// @param userId The dripping user ID.
    /// @param receiver The receiver user ID
    /// @param assetId The used asset ID
    /// @param amtPerSec The new amount per second dripped from the user
    /// to the receiver or 0 if the drips are stopped
    /// @param endTime The timestamp when dripping will stop,
    /// always larger than the block timestamp or equal to it if the drips are stopped
    event Dripping(
        uint256 indexed userId,
        uint256 indexed receiver,
        uint256 indexed assetId,
        uint128 amtPerSec,
        uint64 endTime
    );

    /// @notice Emitted when the drips configuration of a user is updated.
    /// @param userId The user ID.
    /// @param assetId The used asset ID
    /// @param balance The new drips balance. These funds will be dripped to the receivers.
    /// @param receivers The new list of the drips receivers.
    event DripsUpdated(
        uint256 indexed userId,
        uint256 indexed assetId,
        uint128 balance,
        DripsReceiver[] receivers
    );

    /// @notice Emitted when drips are received and are ready to be split.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param amt The received amount.
    /// @param receivableCycles The number of cycles which still can be received.
    event ReceivedDrips(
        uint256 indexed userId,
        uint256 indexed assetId,
        uint128 amt,
        uint64 receivableCycles
    );

    struct Storage {
        /// @notice User drips states.
        /// The keys are the user ID and the asset ID.
        mapping(uint256 => mapping(uint256 => DripsState)) dripsStates;
    }

    struct DripsState {
        /// @notice User drips configuration hashes, see `hashDrips`.
        bytes32 dripsHash;
        // The next cycle to be collected
        uint64 nextCollectedCycle;
        /// @notice The changes of collected amounts on specific cycle.
        /// The keys are cycles, each cycle `C` becomes collectable on timestamp `C * cycleSecs`.
        /// Values for cycles before `nextCollectedCycle` are guaranteed to be zeroed.
        /// This means that the value of `amtDeltas[nextCollectedCycle].thisCycle` is always
        /// relative to 0 or in other words it's an absolute value independent from other cycles.
        mapping(uint64 => AmtDelta) amtDeltas;
    }

    struct AmtDelta {
        /// @notice Amount delta applied on this cycle
        int128 thisCycle;
        /// @notice Amount delta applied on the next cycle
        int128 nextCycle;
    }

    /// @notice Counts cycles from which drips can be collected.
    /// This function can be used to detect that there are
    /// too many cycles to analyze in a single transaction.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return cycles The number of cycles which can be flushed
    function receivableDripsCycles(
        Storage storage s,
        uint64 cycleSecs,
        uint256 userId,
        uint256 assetId
    ) internal view returns (uint64 cycles) {
        uint64 collectedCycle = s.dripsStates[userId][assetId].nextCollectedCycle;
        if (collectedCycle == 0) return 0;
        uint64 currFinishedCycle = _currTimestamp() / cycleSecs;
        return currFinishedCycle + 1 - collectedCycle;
    }

    /// @notice Calculate effects of calling `receiveDrips` with the given parameters.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivableAmt The amount which would be received
    /// @return receivableCycles The number of cycles which would still be receivable after the call
    function receivableDrips(
        Storage storage s,
        uint64 cycleSecs,
        uint256 userId,
        uint256 assetId,
        uint64 maxCycles
    ) internal view returns (uint128 receivableAmt, uint64 receivableCycles) {
        uint64 allReceivableCycles = receivableDripsCycles(s, cycleSecs, userId, assetId);
        uint64 receivedCycles = maxCycles < allReceivableCycles ? maxCycles : allReceivableCycles;
        receivableCycles = allReceivableCycles - receivedCycles;
        DripsState storage dripsState = s.dripsStates[userId][assetId];
        uint64 collectedCycle = dripsState.nextCollectedCycle;
        int128 cycleAmt = 0;
        for (uint256 i = 0; i < receivedCycles; i++) {
            cycleAmt += dripsState.amtDeltas[collectedCycle].thisCycle;
            receivableAmt += uint128(cycleAmt);
            cycleAmt += dripsState.amtDeltas[collectedCycle].nextCycle;
            collectedCycle++;
        }
    }

    /// @notice Receive drips from uncollected cycles of the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// Calling this function does not collect but makes the funds ready to be split and collected.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The received amount
    /// @return receivableCycles The number of cycles which still can be received
    function receiveDrips(
        Storage storage s,
        uint64 cycleSecs,
        uint256 userId,
        uint256 assetId,
        uint64 maxCycles
    ) internal returns (uint128 receivedAmt, uint64 receivableCycles) {
        receivableCycles = receivableDripsCycles(s, cycleSecs, userId, assetId);
        uint64 cycles = maxCycles < receivableCycles ? maxCycles : receivableCycles;
        receivableCycles -= cycles;
        if (cycles > 0) {
            DripsState storage dripsState = s.dripsStates[userId][assetId];
            uint64 cycle = dripsState.nextCollectedCycle;
            int128 cycleAmt = 0;
            for (uint256 i = 0; i < cycles; i++) {
                cycleAmt += dripsState.amtDeltas[cycle].thisCycle;
                receivedAmt += uint128(cycleAmt);
                cycleAmt += dripsState.amtDeltas[cycle].nextCycle;
                delete dripsState.amtDeltas[cycle];
                cycle++;
            }
            // The next cycle delta must be relative to the last collected cycle, which got zeroed.
            // In other words the next cycle delta must be an absolute value.
            if (cycleAmt != 0) dripsState.amtDeltas[cycle].thisCycle += cycleAmt;
            dripsState.nextCollectedCycle = cycle;
        }
        emit ReceivedDrips(userId, assetId, receivedAmt, receivableCycles);
    }

    /// @notice Current user drips hash, see `hashDrips`.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return currDripsHash The current user account's drips hash
    function dripsHash(
        Storage storage s,
        uint256 userId,
        uint256 assetId
    ) internal view returns (bytes32 currDripsHash) {
        return s.dripsStates[userId][assetId].dripsHash;
    }

    /// @notice Sets the user's or the account's drips configuration.
    /// Transfers funds between the user's wallet and the drips hub contract
    /// to fulfill the change of the drips balance.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param lastUpdate The timestamp of the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user or the account.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the user or the account to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the user or the account.
    /// Pass it as `lastBalance` when updating that user or the account for the next time.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        Storage storage s,
        uint64 cycleSecs_,
        uint256 userId,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) internal returns (uint128 newBalance, int128 realBalanceDelta) {
        _assertCurrDrips(s, userId, assetId, lastUpdate, lastBalance, currReceivers);
        uint64 currEndTime;
        uint64 newEndTime;
        {
            uint128 newAmtPerSec = _assertDripsReceiversValid(newReceivers);
            uint128 currAmtPerSec = _totalDripsAmtPerSec(currReceivers);
            currEndTime = _dripsEndTime(lastUpdate, lastBalance, currAmtPerSec);
            (newBalance, realBalanceDelta) = _updateDripsBalance(
                lastUpdate,
                lastBalance,
                currEndTime,
                currAmtPerSec,
                balanceDelta
            );
            newEndTime = _dripsEndTime(_currTimestamp(), newBalance, newAmtPerSec);
        }
        _updateDripsReceiversStates(
            s,
            cycleSecs_,
            userId,
            assetId,
            currReceivers,
            currEndTime,
            newReceivers,
            newEndTime
        );
        s.dripsStates[userId][assetId].dripsHash = hashDrips(
            _currTimestamp(),
            newBalance,
            newReceivers
        );
        emit DripsUpdated(userId, assetId, newBalance, newReceivers);
    }

    /// @notice Validates a list of drips receivers.
    /// @param receivers The list of drips receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return totalAmtPerSec The total amount per second of all drips receivers.
    function _assertDripsReceiversValid(DripsReceiver[] memory receivers)
        private
        pure
        returns (uint128 totalAmtPerSec)
    {
        require(receivers.length <= MAX_DRIPS_RECEIVERS, "Too many drips receivers");
        uint256 amtPerSec = 0;
        uint256 prevReceiver;
        for (uint256 i = 0; i < receivers.length; i++) {
            uint128 amt = receivers[i].amtPerSec;
            require(amt != 0, "Drips receiver amtPerSec is zero");
            amtPerSec += amt;
            uint256 receiver = receivers[i].userId;
            if (i > 0) {
                require(prevReceiver != receiver, "Duplicate drips receivers");
                require(prevReceiver < receiver, "Drips receivers not sorted by user ID");
            }
            prevReceiver = receiver;
        }
        require(amtPerSec <= type(uint128).max, "Total drips receivers amtPerSec too high");
        return uint128(amtPerSec);
    }

    /// @notice Calculates the total amount per second of all the drips receivers.
    /// @param receivers The list of the receivers.
    /// It must have passed `_assertDripsReceiversValid` in the past.
    /// @return totalAmtPerSec The total amount per second of all the drips receivers
    function _totalDripsAmtPerSec(DripsReceiver[] memory receivers)
        private
        pure
        returns (uint128 totalAmtPerSec)
    {
        uint256 length = receivers.length;
        uint256 i = 0;
        while (i < length) {
            // Safe, because `receivers` passed `_assertDripsReceiversValid` in the past
            unchecked {
                totalAmtPerSec += receivers[i++].amtPerSec;
            }
        }
    }

    /// @notice Updates drips balance.
    /// @param lastUpdate The timestamp of the last drips update.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update.
    /// If this is the first update, pass zero.
    /// @param currEndTime Time when drips were supposed to end according to the last drips update.
    /// @param currAmtPerSec The total amount per second of all drips receivers
    /// according to the last drips update.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @return newBalance The new drips balance.
    /// Pass it as `lastBalance` when updating for the next time.
    /// @return realBalanceDelta The actually applied drips balance change.
    /// If positive, this is the amount which should be transferred from the user to the drips hub,
    /// or if negative, from the drips hub to the user.
    function _updateDripsBalance(
        uint64 lastUpdate,
        uint128 lastBalance,
        uint64 currEndTime,
        uint128 currAmtPerSec,
        int128 balanceDelta
    ) private view returns (uint128 newBalance, int128 realBalanceDelta) {
        if (currEndTime > _currTimestamp()) currEndTime = _currTimestamp();
        uint128 dripped = (currEndTime - lastUpdate) * currAmtPerSec;
        int128 currBalance = int128(lastBalance - dripped);
        int136 balance = currBalance + int136(balanceDelta);
        if (balance < 0) balance = 0;
        return (uint128(uint136(balance)), int128(balance - currBalance));
    }

    /// @notice Calculates the timestamp when dripping will end.
    /// @param startTime Time when dripping is started.
    /// @param startBalance The drips balance when dripping is started.
    /// @param totalAmtPerSec The total amount per second of all the drips receivers
    /// @return endTime The dripping end time.
    function _dripsEndTime(
        uint64 startTime,
        uint128 startBalance,
        uint128 totalAmtPerSec
    ) private pure returns (uint64 endTime) {
        if (totalAmtPerSec == 0) return startTime;
        uint256 endTimeBig = startTime + uint256(startBalance / totalAmtPerSec);
        return endTimeBig > MAX_TIMESTAMP ? MAX_TIMESTAMP : uint64(endTimeBig);
    }

    /// @notice Asserts that the drips configuration is the currently used one.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param lastUpdate The timestamp of the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user or the account.
    /// If this is the first update, pass an empty array.
    function _assertCurrDrips(
        Storage storage s,
        uint256 userId,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers
    ) private view {
        require(
            hashDrips(lastUpdate, lastBalance, currReceivers) == dripsHash(s, userId, assetId),
            "Invalid current drips configuration"
        );
    }

    /// @notice Calculates the hash of the drips configuration.
    /// It's used to verify if drips configuration is the previously set one.
    /// @param update The timestamp of the drips update.
    /// If the drips have never been updated, pass zero.
    /// @param balance The drips balance.
    /// If the drips have never been updated, pass zero.
    /// @param receivers The list of the drips receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// If the drips have never been updated, pass an empty array.
    /// @return dripsConfigurationHash The hash of the drips configuration
    function hashDrips(
        uint64 update,
        uint128 balance,
        DripsReceiver[] memory receivers
    ) internal pure returns (bytes32 dripsConfigurationHash) {
        if (update == 0 && balance == 0 && receivers.length == 0) return bytes32(0);
        return keccak256(abi.encode(receivers, update, balance));
    }

    /// @notice Updates the user's or the account's drips receivers' states.
    /// It applies the effects of the change of the drips configuration.
    /// @param userId The user ID.
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user or the account.
    /// If this is the first update, pass an empty array.
    /// @param currEndTime Time when drips were supposed to end according to the last drips update.
    /// @param newReceivers  The list of the drips receivers of the user or the account to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @param newEndTime Time when drips will end according to the new drips configuration.
    function _updateDripsReceiversStates(
        Storage storage s,
        uint64 cycleSecs,
        uint256 userId,
        uint256 assetId,
        DripsReceiver[] memory currReceivers,
        uint64 currEndTime,
        DripsReceiver[] memory newReceivers,
        uint64 newEndTime
    ) private {
        // Skip iterating over `currReceivers` if dripping has run out
        uint256 currIdx = currEndTime > _currTimestamp() ? 0 : currReceivers.length;
        // Skip iterating over `newReceivers` if no new dripping is started
        uint256 newIdx = newEndTime > _currTimestamp() ? 0 : newReceivers.length;
        while (true) {
            // Each iteration gets the next drips update and applies it on the receiver state.
            // A drips update is composed of two drips receiver configurations,
            // one current and one new, or from a single drips receiver configuration
            // if the drips receiver is being added or removed.
            bool pickCurr = currIdx < currReceivers.length;
            bool pickNew = newIdx < newReceivers.length;
            if (!pickCurr && !pickNew) break;
            if (pickCurr && pickNew) {
                // There are two candidate drips receiver configurations to create a drips update.
                // Pick both if they describe the same receiver or the one with a lower address.
                // The one with a higher address won't be used in this iteration.
                // Because drips receivers lists are sorted by addresses and deduplicated,
                // all matching pairs of drips receiver configurations will be found.
                uint256 currReceiver = currReceivers[currIdx].userId;
                uint256 newReceiver = newReceivers[newIdx].userId;
                pickCurr = currReceiver <= newReceiver;
                pickNew = newReceiver <= currReceiver;
            }
            // The drips update parameters
            uint256 receiver;
            int128 currAmtPerSec = 0;
            int128 newAmtPerSec = 0;
            if (pickCurr) {
                receiver = currReceivers[currIdx].userId;
                currAmtPerSec = int128(currReceivers[currIdx].amtPerSec);
                // Clear the obsolete drips end
                _setDelta(
                    s.dripsStates[receiver][assetId].amtDeltas,
                    cycleSecs,
                    currEndTime,
                    currAmtPerSec
                );
                currIdx++;
            }
            if (pickNew) {
                receiver = newReceivers[newIdx].userId;
                newAmtPerSec = int128(newReceivers[newIdx].amtPerSec);
                // Apply the new drips end
                _setDelta(
                    s.dripsStates[receiver][assetId].amtDeltas,
                    cycleSecs,
                    newEndTime,
                    -newAmtPerSec
                );
                newIdx++;
            }
            // The receiver may have never been used
            if (!pickCurr) {
                DripsState storage dripsState = s.dripsStates[receiver][assetId];
                // The receiver has never been used, initialize it
                if (dripsState.nextCollectedCycle == 0) {
                    dripsState.nextCollectedCycle = _currTimestamp() / cycleSecs + 1;
                }
            }
            // Apply the drips update since now
            _setDelta(
                s.dripsStates[receiver][assetId].amtDeltas,
                cycleSecs,
                _currTimestamp(),
                newAmtPerSec - currAmtPerSec
            );
            uint64 eventEndTime = newAmtPerSec == 0 ? _currTimestamp() : newEndTime;
            emit Dripping(userId, receiver, assetId, uint128(newAmtPerSec), eventEndTime);
        }
    }

    // /// @notice Sets amt delta of a user on a given timestamp
    // /// @param userId The user ID
    // /// @param timestamp The timestamp from which the delta takes effect
    // /// @param assetId The used asset ID
    // /// @param amtPerSecDelta Change of the per-second receiving rate
    function _setDelta(
        mapping(uint64 => AmtDelta) storage amtDeltas,
        // Storage storage s,
        uint64 cycleSecs,
        // uint256 userId,
        uint64 timestamp,
        // uint256 assetId,
        int128 amtPerSecDelta
    ) private {
        if (amtPerSecDelta == 0) return;
        // In order to set a delta on a specific timestamp it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint64 thisCycle = timestamp / cycleSecs + 1;
        uint64 nextCycleSecs = timestamp % cycleSecs;
        uint64 thisCycleSecs = cycleSecs - nextCycleSecs;
        AmtDelta storage amtDelta = amtDeltas[thisCycle];
        amtDelta.thisCycle += int128(uint128(thisCycleSecs)) * amtPerSecDelta;
        amtDelta.nextCycle += int128(uint128(nextCycleSecs)) * amtPerSecDelta;
    }

    function _currTimestamp() private view returns (uint64) {
        return uint64(block.timestamp);
    }
}
