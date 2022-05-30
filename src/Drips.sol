// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

/// @notice A drips receiver
struct DripsReceiver {
    /// @notice The user ID.
    uint256 userId;
    /// @notice The amount per second being dripped. Must never be zero.
    uint128 amtPerSec;
    /// @notice The timestamp when dripping should start.
    /// If zero, use the timestamp when drips are configured.
    uint32 start;
    /// @notice The duration of dripping.
    /// If zero, drip until balance runs out.
    uint32 duration;
}

library Drips {
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits cost of changes in drips configuration.
    uint8 internal constant MAX_DRIPS_RECEIVERS = 100;

    /// @notice Emitted when the drips configuration of a user is updated.
    /// @param userId The user ID.
    /// @param assetId The used asset ID
    /// @param receiversHash The drips receivers list hash
    /// @param balance The new drips balance. These funds will be dripped to the receivers.
    event DripsSet(
        uint256 indexed userId,
        uint256 indexed assetId,
        bytes32 indexed receiversHash,
        uint128 balance
    );

    /// @notice Emitted when a user is seen in a drips receivers list.
    /// @param receiversHash The drips receivers list hash
    /// @param userId The user ID.
    /// @param amtPerSec The amount per second being dripped. Must never be zero.
    /// @param start The timestamp when dripping should start.
    /// If zero, use the timestamp when drips are configured.
    /// @param duration The duration of dripping.
    /// If zero, drip until balance runs out.
    event DripsReceiverSeen(
        bytes32 indexed receiversHash,
        uint256 indexed userId,
        uint128 amtPerSec,
        uint32 start,
        uint32 duration
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
        uint32 receivableCycles
    );

    struct Storage {
        /// @notice User drips states.
        /// The keys are the asset ID and the user ID.
        mapping(uint256 => mapping(uint256 => DripsState)) dripsStates;
    }

    struct DripsState {
        /// @notice Drips receivers list hash, see `hashDrips`.
        bytes32 dripsHash;
        /// @notice The next cycle to be collected
        uint32 nextCollectedCycle;
        /// @notice The time when drips have been configured for the last time
        uint32 updateTime;
        /// @notice The end time of drips without duration
        uint32 defaultEnd;
        /// @notice The balance when drips have been configured for the last time
        uint128 balance;
        /// @notice The changes of collected amounts on specific cycle.
        /// The keys are cycles, each cycle `C` becomes collectable on timestamp `C * cycleSecs`.
        /// Values for cycles before `nextCollectedCycle` are guaranteed to be zeroed.
        /// This means that the value of `amtDeltas[nextCollectedCycle].thisCycle` is always
        /// relative to 0 or in other words it's an absolute value independent from other cycles.
        mapping(uint32 => AmtDelta) amtDeltas;
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
    /// @param s The drips storage
    /// @param cycleSecs The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return cycles The number of cycles which can be flushed
    function receivableDripsCycles(
        Storage storage s,
        uint32 cycleSecs,
        uint256 userId,
        uint256 assetId
    ) internal view returns (uint32 cycles) {
        uint32 nextCollectedCycle = s.dripsStates[assetId][userId].nextCollectedCycle;
        // The currently running cycle is not receivable yet
        uint32 currCycle = _cycleOf(_currTimestamp(), cycleSecs);
        if (nextCollectedCycle == 0 || nextCollectedCycle > currCycle) return 0;
        return currCycle - nextCollectedCycle;
    }

    /// @notice Calculate effects of calling `receiveDrips` with the given parameters.
    /// @param s The drips storage
    /// @param cycleSecs The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivableAmt The amount which would be received
    /// @return receivableCycles The number of cycles which would still be receivable after the call
    function receivableDrips(
        Storage storage s,
        uint32 cycleSecs,
        uint256 userId,
        uint256 assetId,
        uint32 maxCycles
    ) internal view returns (uint128 receivableAmt, uint32 receivableCycles) {
        uint32 allReceivableCycles = receivableDripsCycles(s, cycleSecs, userId, assetId);
        uint32 receivedCycles = maxCycles < allReceivableCycles ? maxCycles : allReceivableCycles;
        receivableCycles = allReceivableCycles - receivedCycles;
        DripsState storage state = s.dripsStates[assetId][userId];
        uint32 collectedCycle = state.nextCollectedCycle;
        int128 cycleAmt = 0;
        for (uint256 i = 0; i < receivedCycles; i++) {
            cycleAmt += state.amtDeltas[collectedCycle].thisCycle;
            receivableAmt += uint128(cycleAmt);
            cycleAmt += state.amtDeltas[collectedCycle].nextCycle;
            collectedCycle++;
        }
    }

    /// @notice Receive drips from uncollected cycles of the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// Calling this function does not collect but makes the funds ready to be split and collected.
    /// @param s The drips storage
    /// @param cycleSecs The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The received amount
    /// @return receivableCycles The number of cycles which still can be received
    function receiveDrips(
        Storage storage s,
        uint32 cycleSecs,
        uint256 userId,
        uint256 assetId,
        uint32 maxCycles
    ) internal returns (uint128 receivedAmt, uint32 receivableCycles) {
        receivableCycles = receivableDripsCycles(s, cycleSecs, userId, assetId);
        uint32 cycles = maxCycles < receivableCycles ? maxCycles : receivableCycles;
        receivableCycles -= cycles;
        if (cycles > 0) {
            DripsState storage state = s.dripsStates[assetId][userId];
            uint32 cycle = state.nextCollectedCycle;
            int128 cycleAmt = 0;
            for (uint256 i = 0; i < cycles; i++) {
                cycleAmt += state.amtDeltas[cycle].thisCycle;
                receivedAmt += uint128(cycleAmt);
                cycleAmt += state.amtDeltas[cycle].nextCycle;
                delete state.amtDeltas[cycle];
                cycle++;
            }
            // The next cycle delta must be relative to the last collected cycle, which got zeroed.
            // In other words the next cycle delta must be an absolute value.
            if (cycleAmt != 0) state.amtDeltas[cycle].thisCycle += cycleAmt;
            state.nextCollectedCycle = cycle;
        }
        emit ReceivedDrips(userId, assetId, receivedAmt, receivableCycles);
    }

    /// @notice Current user drips hash, see `hashDrips`.
    /// @param s The drips storage
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return dripsHash The current drips receivers list hash
    /// @return updateTime The time when drips have been configured for the last time
    /// @return balance The balance when drips have been configured for the last time
    function dripsState(
        Storage storage s,
        uint256 userId,
        uint256 assetId
    )
        internal
        view
        returns (
            bytes32 dripsHash,
            uint32 updateTime,
            uint128 balance
        )
    {
        DripsState storage state = s.dripsStates[assetId][userId];
        return (state.dripsHash, state.updateTime, state.balance);
    }

    /// @notice Sets the user's drips configuration.
    /// @param s The drips storage
    /// @param cycleSecs The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change being applied.
    /// Positive when adding funds to the drips balance, negative to removing them.
    /// @param newReceivers The list of the drips receivers of the user to be set.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the user.
    /// Pass it as `lastBalance` when updating that user for the next time.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        Storage storage s,
        uint32 cycleSecs,
        uint256 userId,
        uint256 assetId,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) internal returns (uint128 newBalance, int128 realBalanceDelta) {
        DripsState storage state = s.dripsStates[assetId][userId];
        bytes32 currDripsHash = hashDrips(currReceivers);
        require(currDripsHash == state.dripsHash, "Invalid current drips list");
        uint32 lastUpdate = state.updateTime;
        uint32 currDefaultEnd = state.defaultEnd;
        uint128 lastBalance = state.balance;
        {
            uint128 currBalance = _currBalance(
                lastBalance,
                lastUpdate,
                currDefaultEnd,
                currReceivers
            );
            int136 balance = int128(currBalance) + int136(balanceDelta);
            if (balance < 0) balance = 0;
            newBalance = uint128(uint136(balance));
            realBalanceDelta = int128(balance - int128(currBalance));
        }
        uint32 newDefaultEnd = _defaultEnd(newBalance, newReceivers);
        _updateReceiverStates(
            s.dripsStates[assetId],
            cycleSecs,
            currReceivers,
            lastUpdate,
            currDefaultEnd,
            newReceivers,
            newDefaultEnd
        );
        state.updateTime = _currTimestamp();
        state.defaultEnd = newDefaultEnd;
        state.balance = newBalance;
        bytes32 newDripsHash = hashDrips(newReceivers);
        if (newDripsHash != currDripsHash) {
            state.dripsHash = newDripsHash;
            for (uint256 i = 0; i < newReceivers.length; i++) {
                DripsReceiver memory receiver = newReceivers[i];
                emit DripsReceiverSeen(
                    newDripsHash,
                    receiver.userId,
                    receiver.amtPerSec,
                    receiver.start,
                    receiver.duration
                );
            }
        }
        emit DripsSet(userId, assetId, newDripsHash, newBalance);
    }

    /// @notice Calculates the end time of drips without duration.
    /// @param balance The balance when drips have started
    /// @param receivers The list of drips receivers.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @return defaultEndTime The end time of drips without duration.
    function _defaultEnd(uint128 balance, DripsReceiver[] memory receivers)
        private
        view
        returns (uint32 defaultEndTime)
    {
        require(receivers.length <= MAX_DRIPS_RECEIVERS, "Too many drips receivers");
        DefaultEnd[] memory defaults = new DefaultEnd[](receivers.length);
        uint8 length = 0;

        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory receiver = receivers[i];
            require(receiver.amtPerSec != 0, "Drips receiver amtPerSec is zero");
            if (i > 0) require(_isOrdered(receivers[i - 1], receiver), "Receivers not sorted");
            // Default drips end doesn't matter here, the end time is ignored when
            // the duration is zero and if it's non-zero the default end is not used anyway
            (uint32 start, uint32 end) = _dripsRangeInFuture(receiver, _currTimestamp(), 0);
            if (receiver.duration == 0) {
                length = _addDefaultEnd(defaults, length, start, receiver.amtPerSec);
            } else {
                uint192 spent = (end - start) * receiver.amtPerSec;
                require(balance >= spent, "Insufficient balance");
                balance -= uint128(spent);
            }
        }
        return _receiversDefaultEnd(defaults, length, balance);
    }

    /// @notice The internal representation of a receiver without a duration
    struct DefaultEnd {
        uint32 start;
        uint136 amtPerSec;
    }

    /// @notice Adds a `DefaultEnd` to the list of receivers while keeping it sorted.
    /// @param defaults The list of default ends, must be sorted by start
    /// @param length The length of the list
    /// @param start The start time of the added receiver
    /// @param amtPerSec The amtPerSec of the added receiver
    /// @return newLength The new length of the list
    function _addDefaultEnd(
        DefaultEnd[] memory defaults,
        uint8 length,
        uint32 start,
        uint128 amtPerSec
    ) private pure returns (uint8 newLength) {
        for (uint8 i = 0; i < length; i++) {
            DefaultEnd memory defaultEnd = defaults[i];
            if (defaultEnd.start == start) {
                defaultEnd.amtPerSec += amtPerSec;
                return length;
            }
            if (defaultEnd.start > start) {
                // Shift existing entries to make space for inserting the new entry
                for (uint8 j = length; j > i; j--) {
                    defaults[j] = defaults[j - 1];
                }
                defaults[i] = DefaultEnd(start, amtPerSec);
                return length + 1;
            }
        }
        defaults[length] = DefaultEnd(start, amtPerSec);
        return length + 1;
    }

    /// @notice Calculates the end time of drips without duration.
    /// @param defaults The list of default ends, must be sorted by start
    /// @param length The length of the list
    /// @param balance The balance available for drips without duration
    /// @return end_ The end time of drips without duration
    function _receiversDefaultEnd(
        DefaultEnd[] memory defaults,
        uint8 length,
        uint128 balance
    ) private pure returns (uint32 end_) {
        uint32 lastStart = 0;
        uint136 amtPerSec = 0;
        uint136 end = type(uint136).max;
        for (uint8 i = 0; i < length; i++) {
            DefaultEnd memory defaultEnd = defaults[i];
            uint32 start = defaultEnd.start;
            if (start >= end) break;
            balance -= uint128(amtPerSec * (start - lastStart));
            lastStart = start;
            amtPerSec += defaultEnd.amtPerSec;
            end = start + (balance / amtPerSec);
        }
        if (end > type(uint32).max) end = type(uint32).max;
        return uint32(end);
    }

    /// @notice Calculates the current drips balance.
    /// @param lastBalance The balance when drips have started
    /// @param lastUpdate The timestamp when drips have started.
    /// @param defaultEnd The end time of drips without duration
    /// @param receivers The list of drips receivers.
    /// @return balance The current drips balance.
    function _currBalance(
        uint128 lastBalance,
        uint32 lastUpdate,
        uint32 defaultEnd,
        DripsReceiver[] memory receivers
    ) private view returns (uint128 balance) {
        balance = lastBalance;
        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory receiver = receivers[i];
            (uint32 start, uint32 end) = _dripsRangeInPast(receiver, lastUpdate, defaultEnd);
            balance -= (end - start) * receiver.amtPerSec;
        }
    }

    /// @notice Calculates the hash of the drips configuration.
    /// It's used to verify if drips configuration is the previously set one.
    /// @param receivers The list of the drips receivers.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// If the drips have never been updated, pass an empty array.
    /// @return dripsConfigurationHash The hash of the drips configuration
    function hashDrips(DripsReceiver[] memory receivers)
        internal
        pure
        returns (bytes32 dripsConfigurationHash)
    {
        if (receivers.length == 0) return bytes32(0);
        return keccak256(abi.encode(receivers));
    }

    /// @notice Applies the effects of the change of the drips on the receivers' drips states.
    /// @param states The drips states for a single asset, the key is the user ID
    /// @param cycleSecs_ The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user.
    /// If this is the first update, pass an empty array.
    /// @param lastUpdate The timestamp of the last drips update of the user.
    /// If this is the first update, pass zero.
    /// @param currDefaultEnd Time when drips without duration
    /// were supposed to end according to the last drips update.
    /// @param newReceivers  The list of the drips receivers of the user to be set.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @param newDefaultEnd Time when drips without duration
    /// will end according to the new drips configuration.
    function _updateReceiverStates(
        mapping(uint256 => DripsState) storage states,
        uint32 cycleSecs_,
        DripsReceiver[] memory currReceivers,
        uint32 lastUpdate,
        uint32 currDefaultEnd,
        DripsReceiver[] memory newReceivers,
        uint32 newDefaultEnd
    ) private {
        // A copy shallow in the stack, prevents "stack too deep" errors
        uint32 cycleSecs = cycleSecs_;
        uint256 currIdx = 0;
        uint256 newIdx = 0;
        while (true) {
            bool pickCurr = currIdx < currReceivers.length;
            DripsReceiver memory currRecv;
            if (pickCurr) currRecv = currReceivers[currIdx];

            bool pickNew = newIdx < newReceivers.length;
            DripsReceiver memory newRecv;
            if (pickNew) newRecv = newReceivers[newIdx];

            // Limit picking both curr and new to situations when they differ only by time
            if (
                pickCurr &&
                pickNew &&
                (currRecv.userId != newRecv.userId || currRecv.amtPerSec != newRecv.amtPerSec)
            ) {
                pickCurr = _isOrdered(currRecv, newRecv);
                pickNew = !pickCurr;
            }

            if (pickCurr && pickNew) {
                // Shift the existing drip to fulfil the new configuration
                mapping(uint32 => AmtDelta) storage deltas = states[currRecv.userId].amtDeltas;
                (uint32 currStart, uint32 currEnd) = _dripsRangeInFuture(
                    currRecv,
                    lastUpdate,
                    currDefaultEnd
                );
                (uint32 newStart, uint32 newEnd) = _dripsRangeInFuture(
                    newRecv,
                    _currTimestamp(),
                    newDefaultEnd
                );
                _moveDeltaRange(
                    deltas,
                    cycleSecs,
                    currStart,
                    currEnd,
                    newStart,
                    newEnd,
                    currRecv.amtPerSec
                );
            } else if (pickCurr) {
                // Remove an existing drip
                mapping(uint32 => AmtDelta) storage deltas = states[currRecv.userId].amtDeltas;
                (uint32 start, uint32 end) = _dripsRangeInFuture(
                    currRecv,
                    lastUpdate,
                    currDefaultEnd
                );
                _clearDeltaRange(deltas, cycleSecs, start, end, currRecv.amtPerSec);
            } else if (pickNew) {
                // Create a new drip
                DripsState storage state = states[newRecv.userId];
                (uint32 start, uint32 end) = _dripsRangeInFuture(
                    newRecv,
                    _currTimestamp(),
                    newDefaultEnd
                );
                _setDeltaRange(state.amtDeltas, cycleSecs, start, end, newRecv.amtPerSec);
                // Ensure that the receiver collects the updated cycles
                uint32 startCycle = _cycleOf(start, cycleSecs);
                if (state.nextCollectedCycle == 0 || state.nextCollectedCycle > startCycle) {
                    state.nextCollectedCycle = startCycle;
                }
            } else {
                break;
            }

            if (pickCurr) currIdx++;
            if (pickNew) newIdx++;
        }
    }

    /// @notice Calculates the time range in the past in which a receiver has been dripped to.
    /// @param receiver The drips receiver
    /// @param updateTime The time when drips are configured
    /// @param defaultEnd The end time of drips without duration
    function _dripsRangeInPast(
        DripsReceiver memory receiver,
        uint32 updateTime,
        uint32 defaultEnd
    ) private view returns (uint32 start, uint32 end) {
        return _dripsRange(receiver, updateTime, defaultEnd, 0, _currTimestamp());
    }

    /// @notice Calculates the time range in the future in which a receiver will be dripped to.
    /// @param receiver The drips receiver
    /// @param updateTime The time when drips are configured
    /// @param defaultEnd The end time of drips without duration
    function _dripsRangeInFuture(
        DripsReceiver memory receiver,
        uint32 updateTime,
        uint32 defaultEnd
    ) private view returns (uint32 start, uint32 end) {
        return _dripsRange(receiver, updateTime, defaultEnd, _currTimestamp(), type(uint32).max);
    }

    /// @notice Calculates the time range in which a receiver is to be dripped to.
    /// This range is capped to provide a view on drips through a specific time window.
    /// @param receiver The drips receiver
    /// @param updateTime The time when drips are configured
    /// @param defaultEnd The end time of drips without duration
    /// @param startCap The timestamp the drips range start should be capped to
    /// @param endCap The timestamp the drips range end should be capped to
    function _dripsRange(
        DripsReceiver memory receiver,
        uint32 updateTime,
        uint32 defaultEnd,
        uint32 startCap,
        uint32 endCap
    ) private pure returns (uint32 start, uint32 end_) {
        start = updateTime;
        if (receiver.start != 0) start = receiver.start;
        uint40 end = defaultEnd;
        if (receiver.duration != 0) end = uint40(start) + receiver.duration;
        if (start < updateTime) start = updateTime;
        if (start < startCap) start = startCap;
        if (end > endCap) end = endCap;
        if (end < start) end = start;
        return (start, uint32(end));
    }

    /// @notice Changes amt delta to move a time range of received funds by a user
    /// @param amtDeltas The user deltas
    /// @param cycleSecs The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param currStart The timestamp from which the delta currently takes effect
    /// @param currEnd The timestamp until which the delta currently takes effect
    /// @param newStart The timestamp from which the delta will start taking effect
    /// @param newEnd The timestamp until which the delta will start taking effect
    /// @param amtPerSec The receiving rate
    function _moveDeltaRange(
        mapping(uint32 => AmtDelta) storage amtDeltas,
        uint32 cycleSecs,
        uint32 currStart,
        uint32 currEnd,
        uint32 newStart,
        uint32 newEnd,
        uint128 amtPerSec
    ) private {
        _clearDeltaRange(amtDeltas, cycleSecs, currStart, newStart, amtPerSec);
        _setDeltaRange(amtDeltas, cycleSecs, currEnd, newEnd, amtPerSec);
    }

    /// @notice Clears amt delta of received funds by a user in a given time range
    /// @param amtDeltas The user deltas
    /// @param cycleSecs The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param start The timestamp from which the delta takes effect
    /// @param end The timestamp until which the delta takes effect
    /// @param amtPerSec The receiving rate
    function _clearDeltaRange(
        mapping(uint32 => AmtDelta) storage amtDeltas,
        uint32 cycleSecs,
        uint32 start,
        uint32 end,
        uint128 amtPerSec
    ) private {
        // start and end are swapped
        _setDeltaRange(amtDeltas, cycleSecs, end, start, amtPerSec);
    }

    /// @notice Sets amt delta of received funds by a user in a given time range
    /// @param amtDeltas The user deltas
    /// @param cycleSecs The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param start The timestamp from which the delta takes effect
    /// @param end The timestamp until which the delta takes effect
    /// @param amtPerSec The receiving rate
    function _setDeltaRange(
        mapping(uint32 => AmtDelta) storage amtDeltas,
        uint32 cycleSecs,
        uint32 start,
        uint32 end,
        uint128 amtPerSec
    ) private {
        if (start == end) return;
        _setDelta(amtDeltas, cycleSecs, start, int128(amtPerSec));
        _setDelta(amtDeltas, cycleSecs, end, -int128(amtPerSec));
    }

    /// @notice Sets amt delta of received funds by a user on a given timestamp
    /// @param amtDeltas The user deltas
    /// @param cycleSecs The cycle length in seconds.
    /// Must be the same in all calls working on a single storage instance. Must be higher than 1.
    /// @param timestamp The timestamp from which the delta takes effect
    /// @param amtPerSecDelta Change of the per-second receiving rate
    function _setDelta(
        mapping(uint32 => AmtDelta) storage amtDeltas,
        uint32 cycleSecs,
        uint32 timestamp,
        int128 amtPerSecDelta
    ) private {
        // In order to set a delta on a specific timestamp it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint32 thisCycle = _cycleOf(timestamp, cycleSecs);
        uint32 nextCycleSecs = timestamp % cycleSecs;
        uint32 thisCycleSecs = cycleSecs - nextCycleSecs;
        AmtDelta storage amtDelta = amtDeltas[thisCycle];
        amtDelta.thisCycle += int128(uint128(thisCycleSecs)) * amtPerSecDelta;
        amtDelta.nextCycle += int128(uint128(nextCycleSecs)) * amtPerSecDelta;
    }

    /// @notice Checks if two receivers fulfil the sortedness requirement of the receivers list.
    /// @param prev The previous receiver
    /// @param prev The next receiver
    function _isOrdered(DripsReceiver memory prev, DripsReceiver memory next)
        private
        pure
        returns (bool)
    {
        if (prev.userId != next.userId) return prev.userId < next.userId;
        if (prev.amtPerSec != next.amtPerSec) return prev.amtPerSec < next.amtPerSec;
        if (prev.start != next.start) return prev.start < next.start;
        return prev.duration < next.duration;
    }

    /// @notice Calculates the cycle containing the given timestamp.
    /// @param timestamp The timestamp.
    /// @param cycleSecs The cycle length in seconds.
    /// @return cycle The cycle containing the timestamp.
    function _cycleOf(uint32 timestamp, uint32 cycleSecs) internal pure returns (uint32 cycle) {
        return timestamp / cycleSecs + 1;
    }

    /// @notice The current timestamp, casted to the library's internal representation.
    /// @return timestamp The current timestamp
    function _currTimestamp() private view returns (uint32 timestamp) {
        return uint32(block.timestamp);
    }
}
