// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

/// @notice A drips receiver
struct DripsReceiver {
    /// @notice The user ID.
    uint256 userId;
    /// @notice The drips configuration.
    DripsConfig config;
}

/// @notice Describes a drips configuration.
/// It's constructed from `amtPerSec`, `start` and `duration` as
/// `amtPerSec << 64 | start << 32 | duration`.
/// `amtPerSec` is the amount per second being dripped. Must never be zero.
/// `start` is the timestamp when dripping should start.
/// If zero, use the timestamp when drips are configured.
/// `duration` is the duration of dripping.
/// If zero, drip until balance runs out.
type DripsConfig is uint192;

using DripsConfigImpl for DripsConfig global;

library DripsConfigImpl {
    /// @notice Create a new DripsConfig.
    /// @param _amtPerSec The amount per second being dripped. Must never be zero.
    /// @param _start The timestamp when dripping should start.
    /// If zero, use the timestamp when drips are configured.
    /// @param _duration The duration of dripping.
    /// If zero, drip until balance runs out.
    function create(
        uint128 _amtPerSec,
        uint32 _start,
        uint32 _duration
    ) internal pure returns (DripsConfig) {
        uint192 config = _amtPerSec;
        config = (config << 32) | _start;
        config = (config << 32) | _duration;
        return DripsConfig.wrap(config);
    }

    /// @notice Extracts amtPerSec from a `DripsConfig`
    function amtPerSec(DripsConfig config) internal pure returns (uint128) {
        return uint128(DripsConfig.unwrap(config) >> 64);
    }

    /// @notice Extracts start from a `DripsConfig`
    function start(DripsConfig config) internal pure returns (uint32) {
        return uint32(DripsConfig.unwrap(config) >> 32);
    }

    /// @notice Extracts duration from a `DripsConfig`
    function duration(DripsConfig config) internal pure returns (uint32) {
        return uint32(DripsConfig.unwrap(config));
    }

    /// @notice Compares two `DripsConfig`s.
    /// First compares their `amtPerSec`s, then their `start`s and then their `duration`s.
    function lt(DripsConfig config, DripsConfig otherConfig) internal pure returns (bool) {
        return DripsConfig.unwrap(config) < DripsConfig.unwrap(otherConfig);
    }
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
    /// @param config The drips configuration.
    event DripsReceiverSeen(
        bytes32 indexed receiversHash,
        uint256 indexed userId,
        DripsConfig config
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
        /// @notice The next cycle to be received
        uint32 nextReceivableCycle;
        /// @notice The time when drips have been configured for the last time
        uint32 updateTime;
        /// @notice The end time of drips without duration
        uint32 defaultEnd;
        /// @notice The balance when drips have been configured for the last time
        uint128 balance;
        /// @notice The changes of received amounts on specific cycle.
        /// The keys are cycles, each cycle `C` becomes receivable on timestamp `C * cycleSecs`.
        /// Values for cycles before `nextReceivableCycle` are guaranteed to be zeroed.
        /// This means that the value of `amtDeltas[nextReceivableCycle].thisCycle` is always
        /// relative to 0 or in other words it's an absolute value independent from other cycles.
        mapping(uint32 => AmtDelta) amtDeltas;
    }

    struct AmtDelta {
        /// @notice Amount delta applied on this cycle
        int128 thisCycle;
        /// @notice Amount delta applied on the next cycle
        int128 nextCycle;
    }

    /// @notice Counts cycles from which drips can be received.
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
        uint32 nextReceivableCycle = s.dripsStates[assetId][userId].nextReceivableCycle;
        // The currently running cycle is not receivable yet
        uint32 currCycle = _cycleOf(_currTimestamp(), cycleSecs);
        if (nextReceivableCycle == 0 || nextReceivableCycle > currCycle) return 0;
        return currCycle - nextReceivableCycle;
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
        uint32 receivedCycle = state.nextReceivableCycle;
        int128 cycleAmt = 0;
        for (uint256 i = 0; i < receivedCycles; i++) {
            cycleAmt += state.amtDeltas[receivedCycle].thisCycle;
            receivableAmt += uint128(cycleAmt);
            cycleAmt += state.amtDeltas[receivedCycle].nextCycle;
            receivedCycle++;
        }
    }

    /// @notice Receive drips from unreceived cycles of the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// Calling this function does not receive but makes the funds ready to be split and received.
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
            uint32 cycle = state.nextReceivableCycle;
            int128 cycleAmt = 0;
            for (uint256 i = 0; i < cycles; i++) {
                cycleAmt += state.amtDeltas[cycle].thisCycle;
                receivedAmt += uint128(cycleAmt);
                cycleAmt += state.amtDeltas[cycle].nextCycle;
                delete state.amtDeltas[cycle];
                cycle++;
            }
            // The next cycle delta must be relative to the last received cycle, which got zeroed.
            // In other words the next cycle delta must be an absolute value.
            if (cycleAmt != 0) state.amtDeltas[cycle].thisCycle += cycleAmt;
            state.nextReceivableCycle = cycle;
        }
        emit ReceivedDrips(userId, assetId, receivedAmt, receivableCycles);
    }

    /// @notice Current user drips state.
    /// @param s The drips storage
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return dripsHash The current drips receivers list hash, see `hashDrips`
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
            uint128 balance,
            uint32 defaultEnd
        )
    {
        DripsState storage state = s.dripsStates[assetId][userId];
        return (state.dripsHash, state.updateTime, state.balance, state.defaultEnd);
    }

    /// @notice User drips balance at a given timestamp
    /// @param s The drips storage
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param receivers The current drips receivers list
    /// @param timestamp The timestamps for which balance should be calculated.
    /// It can't be lower than the timestamp of the last call to `setDrips`.
    /// If it's bigger than `block.timestamp`, then it's a prediction assuming
    /// that `setDrips` won't be called before `timestamp`.
    /// @return balance The user balance on `timestamp`
    function balanceAt(
        Storage storage s,
        uint256 userId,
        uint256 assetId,
        DripsReceiver[] memory receivers,
        uint32 timestamp
    ) internal view returns (uint128 balance) {
        DripsState storage state = s.dripsStates[assetId][userId];
        require(timestamp >= state.updateTime, "Timestamp before last drips update");
        require(hashDrips(receivers) == state.dripsHash, "Invalid current drips list");
        return _balanceAt(state.balance, state.updateTime, state.defaultEnd, receivers, timestamp);
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
            uint128 currBalance = _balanceAt(
                lastBalance,
                lastUpdate,
                currDefaultEnd,
                currReceivers,
                _currTimestamp()
            );
            int136 balance = int128(currBalance) + int136(balanceDelta);
            if (balance < 0) balance = 0;
            newBalance = uint128(uint136(balance));
            realBalanceDelta = int128(balance - int128(currBalance));
        }
        uint32 newDefaultEnd = calcDefaultEnd(newBalance, newReceivers);
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
                emit DripsReceiverSeen(newDripsHash, receiver.userId, receiver.config);
            }
        }
        emit DripsSet(userId, assetId, newDripsHash, newBalance);
    }

    function _addDefaultEnd(
        uint256[] memory defaultEnds,
        uint256 length,
        uint128 amtPerSec,
        uint32 start
    ) private pure {
        defaultEnds[length] = (uint256(amtPerSec) << 32) | start;
    }

    function _defaultEndAtIdx(uint256[] memory defaultEnds, uint256 idx)
        private
        pure
        returns (uint256 amtPerSec, uint256 start)
    {
        uint256 val;
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            val := mload(add(32, add(defaultEnds, shl(5, idx))))
        }
        return (val >> 32, uint32(val));
    }

    /// @notice Calculates the end time of drips without duration.
    /// @param balance The balance when drips have started
    /// @param receivers The list of drips receivers.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @return defaultEndTime The end time of drips without duration.
    function calcDefaultEnd(uint128 balance, DripsReceiver[] memory receivers)
        internal
        view
        returns (uint32 defaultEndTime)
    {
        require(receivers.length <= MAX_DRIPS_RECEIVERS, "Too many drips receivers");
        uint256[] memory defaultEnds = new uint256[](receivers.length);
        uint256 defaultEndsLen = 0;
        uint168 spent = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory receiver = receivers[i];
            uint128 amtPerSec = receiver.config.amtPerSec();
            require(amtPerSec != 0, "Drips receiver amtPerSec is zero");
            if (i > 0) require(_isOrdered(receivers[i - 1], receiver), "Receivers not sorted");
            // Default drips end doesn't matter here, the end time is ignored when
            // the duration is zero and if it's non-zero the default end is not used anyway
            (uint32 start, uint32 end) = _dripsRangeInFuture(receiver, _currTimestamp(), 0);
            if (receiver.config.duration() == 0) {
                _addDefaultEnd(defaultEnds, defaultEndsLen++, amtPerSec, start);
            } else {
                spent += uint160(end - start) * amtPerSec;
            }
        }
        require(balance >= spent, "Insufficient balance");
        balance -= uint128(spent);
        return _calcDefaultEnd(defaultEnds, defaultEndsLen, balance);
    }

    function _calcDefaultEnd(
        uint256[] memory defaultEnds,
        uint256 defaultEndsLen,
        uint128 balance
    ) private view returns (uint32 defaultEnd) {
        unchecked {
            uint32 minEnd = _currTimestamp();
            uint32 maxEnd = type(uint32).max;
            if (defaultEndsLen == 0 || balance == 0) return minEnd;
            if (_isBalanceEnough(defaultEnds, defaultEndsLen, balance, maxEnd)) return maxEnd;
            uint256 enoughEnd = minEnd;
            uint256 notEnoughEnd = maxEnd;
            while (true) {
                uint256 end = (enoughEnd + notEnoughEnd) / 2;
                if (end == enoughEnd) return uint32(end);
                if (_isBalanceEnough(defaultEnds, defaultEndsLen, balance, end)) {
                    enoughEnd = end;
                } else {
                    notEnoughEnd = end;
                }
            }
        }
    }

    function _isBalanceEnough(
        uint256[] memory defaultEnds,
        uint256 defaultEndsLen,
        uint256 balance,
        uint256 end
    ) private pure returns (bool) {
        unchecked {
            uint256 spent = 0;
            for (uint256 i = 0; i < defaultEndsLen; i++) {
                (uint256 amtPerSec, uint256 start) = _defaultEndAtIdx(defaultEnds, i);
                if (end <= start) continue;
                spent += amtPerSec * (end - start);
                if (spent > balance) return false;
            }
            return true;
        }
    }

    /// @notice Calculates the drips balance at a given timestamp.
    /// @param lastBalance The balance when drips have started
    /// @param lastUpdate The timestamp when drips have started.
    /// @param defaultEnd The end time of drips without duration
    /// @param receivers The list of drips receivers.
    /// @param timestamp The timestamps for which balance should be calculated.
    /// It can't be lower than `lastUpdate`.
    /// If it's bigger than `block.timestamp`, then it's a prediction assuming
    /// that `setDrips` won't be called before `timestamp`.
    /// @return balance The user balance on `timestamp`
    function _balanceAt(
        uint128 lastBalance,
        uint32 lastUpdate,
        uint32 defaultEnd,
        DripsReceiver[] memory receivers,
        uint32 timestamp
    ) private pure returns (uint128 balance) {
        balance = lastBalance;
        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory receiver = receivers[i];
            (uint32 start, uint32 end) = _dripsRange({
                receiver: receiver,
                updateTime: lastUpdate,
                defaultEnd: defaultEnd,
                startCap: lastUpdate,
                endCap: timestamp
            });
            balance -= (end - start) * receiver.config.amtPerSec();
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
    /// @param lastUpdate the last time the sender updated the drips.
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
                (currRecv.userId != newRecv.userId ||
                    currRecv.config.amtPerSec() != newRecv.config.amtPerSec())
            ) {
                pickCurr = _isOrdered(currRecv, newRecv);
                pickNew = !pickCurr;
            }

            if (pickCurr && pickNew) {
                // Shift the existing drip to fulfil the new configuration
                DripsState storage state = states[currRecv.userId];
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
                    state.amtDeltas,
                    cycleSecs,
                    currStart,
                    currEnd,
                    newStart,
                    newEnd,
                    currRecv.config.amtPerSec()
                );
                // Ensure that the user receives the updated cycles
                uint32 startCycle = _cycleOf(newStart, cycleSecs);
                if (state.nextReceivableCycle > startCycle) {
                    state.nextReceivableCycle = startCycle;
                }
            } else if (pickCurr) {
                // Remove an existing drip
                mapping(uint32 => AmtDelta) storage deltas = states[currRecv.userId].amtDeltas;
                (uint32 start, uint32 end) = _dripsRangeInFuture(
                    currRecv,
                    lastUpdate,
                    currDefaultEnd
                );
                _clearDeltaRange(deltas, cycleSecs, start, end, currRecv.config.amtPerSec());
            } else if (pickNew) {
                // Create a new drip
                DripsState storage state = states[newRecv.userId];
                (uint32 start, uint32 end) = _dripsRangeInFuture(
                    newRecv,
                    _currTimestamp(),
                    newDefaultEnd
                );
                _setDeltaRange(state.amtDeltas, cycleSecs, start, end, newRecv.config.amtPerSec());
                // Ensure that the user receives the updated cycles
                uint32 startCycle = _cycleOf(start, cycleSecs);
                if (state.nextReceivableCycle == 0 || state.nextReceivableCycle > startCycle) {
                    state.nextReceivableCycle = startCycle;
                }
            } else {
                break;
            }

            if (pickCurr) currIdx++;
            if (pickNew) newIdx++;
        }
    }

    /// @notice Calculates the time range in the future in which a receiver will be dripped to.
    /// @param receiver The drips receiver
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
        start = receiver.config.start();
        if (start == 0) start = updateTime;
        uint40 end = uint40(start) + receiver.config.duration();
        if (end == start) end = defaultEnd;
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
        return prev.config.lt(next.config);
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
