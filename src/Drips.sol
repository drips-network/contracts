// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

/// @notice A drips receiver
struct DripsReceiver {
    /// @notice The user ID.
    uint256 userId;
    /// @notice The drips configuration.
    DripsConfig config;
}

/// @notice The sender drips history entry, used when squeezing drips.
struct DripsHistory {
    /// @notice Drips receivers list hash, see `_hashDrips`.
    /// If it's non-zero, `receivers` must be empty.
    bytes32 dripsHash;
    /// @notice The drips receivers. If it's non-empty, `dripsHash` must be `0`.
    /// If it's empty, this history entry will be skipped when squeezing drips
    /// and `dripsHash` will be used when verifying the drips history validity.
    /// Skipping a history entry allows cutting gas usage on analysis
    /// of parts of the drips history which are not worth squeezing.
    /// The hash of an empty receivers list is `0`, so when the sender updates
    /// their receivers list to be empty, the new `DripsHistory` entry will have
    /// both the `dripsHash` equal to `0` and the `receivers` empty making it always skipped.
    /// This is fine, because there can't be any funds to squeeze from that entry anyway.
    DripsReceiver[] receivers;
    /// @notice The time when drips have been configured
    uint32 updateTime;
    /// @notice The maximum end time of drips
    uint32 maxEnd;
}

/// @notice Describes a drips configuration.
/// It's constructed from `dripId`, `amtPerSec`, `start` and `duration` as
/// `dripId << 224 | amtPerSec << 64 | start << 32 | duration`.
/// `dripId` is an arbitrary number used to identify a drip.
/// It's a part of the configuration but the protocol doesn't use it.
/// `amtPerSec` is the amount per second being dripped. Must never be zero.
/// It must have additional `Drips._AMT_PER_SEC_EXTRA_DECIMALS` decimals and can have fractions.
/// To achieve that its value must be multiplied by `Drips._AMT_PER_SEC_MULTIPLIER`.
/// `start` is the timestamp when dripping should start.
/// If zero, use the timestamp when drips are configured.
/// `duration` is the duration of dripping.
/// If zero, drip until balance runs out.
type DripsConfig is uint256;

using DripsConfigImpl for DripsConfig global;

library DripsConfigImpl {
    /// @notice Create a new DripsConfig.
    /// @param dripId_ An arbitrary number used to identify a drip.
    /// It's a part of the configuration but the protocol doesn't use it.
    /// @param amtPerSec_ The amount per second being dripped. Must never be zero.
    /// It must have additional `Drips._AMT_PER_SEC_EXTRA_DECIMALS` decimals and can have fractions.
    /// To achieve that the passed value must be multiplied by `Drips._AMT_PER_SEC_MULTIPLIER`.
    /// @param start_ The timestamp when dripping should start.
    /// If zero, use the timestamp when drips are configured.
    /// @param duration_ The duration of dripping.
    /// If zero, drip until balance runs out.
    function create(uint32 dripId_, uint160 amtPerSec_, uint32 start_, uint32 duration_)
        internal
        pure
        returns (DripsConfig)
    {
        uint256 config = dripId_;
        config = (config << 160) | amtPerSec_;
        config = (config << 32) | start_;
        config = (config << 32) | duration_;
        return DripsConfig.wrap(config);
    }

    /// @notice Extracts dripId from a `DripsConfig`
    function dripId(DripsConfig config) internal pure returns (uint32) {
        return uint32(DripsConfig.unwrap(config) >> 224);
    }

    /// @notice Extracts amtPerSec from a `DripsConfig`
    function amtPerSec(DripsConfig config) internal pure returns (uint160) {
        return uint160(DripsConfig.unwrap(config) >> 64);
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
    /// First compares `dripId`s, then `amtPerSec`s, then `start`s and finally `duration`s.
    /// @return isLower True if `config` is strictly lower than `otherConfig`.
    function lt(DripsConfig config, DripsConfig otherConfig) internal pure returns (bool isLower) {
        return DripsConfig.unwrap(config) < DripsConfig.unwrap(otherConfig);
    }
}

/// @notice Drips can keep track of at most `type(int128).max`
/// which is `2 ^ 127 - 1` units of each asset.
/// It's up to the caller to guarantee that this limit is never exceeded,
/// failing to do so may result in a total protocol collapse.
abstract contract Drips {
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits cost of changes in drips configuration.
    uint256 internal constant _MAX_DRIPS_RECEIVERS = 100;
    /// @notice The additional decimals for all amtPerSec values.
    uint8 internal constant _AMT_PER_SEC_EXTRA_DECIMALS = 9;
    /// @notice The multiplier for all amtPerSec values. It's `10 ** _AMT_PER_SEC_EXTRA_DECIMALS`.
    uint160 internal constant _AMT_PER_SEC_MULTIPLIER = 1_000_000_000;
    /// @notice The total amount the contract can keep track of each asset.
    uint256 internal constant _MAX_TOTAL_DRIPS_BALANCE = uint128(type(int128).max);
    /// @notice On every timestamp `T`, which is a multiple of `cycleSecs`, the receivers
    /// gain access to drips received during `T - cycleSecs` to `T - 1`.
    /// Always higher than 1.
    // slither-disable-next-line naming-convention
    uint32 internal immutable _cycleSecs;
    /// @notice The minimum amtPerSec of a drip. It's 1 token per cycle.
    // slither-disable-next-line naming-convention
    uint160 internal immutable _minAmtPerSec;
    /// @notice The storage slot holding a single `DripsStorage` structure.
    bytes32 private immutable _dripsStorageSlot;

    /// @notice Emitted when the drips configuration of a user is updated.
    /// @param userId The user ID.
    /// @param assetId The used asset ID
    /// @param receiversHash The drips receivers list hash
    /// @param dripsHistoryHash The drips history hash which was valid right before the update.
    /// @param balance The new drips balance. These funds will be dripped to the receivers.
    /// @param maxEnd The maximum end time of drips, when funds run out.
    /// If funds run out after the timestamp `type(uint32).max`, it's set to `type(uint32).max`.
    /// If the balance is 0 or there are no receivers, it's set to the current timestamp.
    event DripsSet(
        uint256 indexed userId,
        uint256 indexed assetId,
        bytes32 indexed receiversHash,
        bytes32 dripsHistoryHash,
        uint128 balance,
        uint32 maxEnd
    );

    /// @notice Emitted when a user is seen in a drips receivers list.
    /// @param receiversHash The drips receivers list hash
    /// @param userId The user ID.
    /// @param config The drips configuration.
    event DripsReceiverSeen(
        bytes32 indexed receiversHash, uint256 indexed userId, DripsConfig config
    );

    /// @notice Emitted when drips are received.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param amt The received amount.
    /// @param receivableCycles The number of cycles which still can be received.
    event ReceivedDrips(
        uint256 indexed userId, uint256 indexed assetId, uint128 amt, uint32 receivableCycles
    );

    /// @notice Emitted when drips are squeezed.
    /// @param userId The squeezing user ID.
    /// @param assetId The used asset ID.
    /// @param senderId The ID of the user sending drips which are squeezed.
    /// @param amt The squeezed amount.
    /// @param dripsHistoryHashes The history hashes of all squeezed drips history entries.
    /// Each history hash matches `dripsHistoryHash` emitted in its `DripsSet`
    /// when the squeezed drips configuration was set.
    /// Sorted in the oldest drips configuration to the newest.
    event SqueezedDrips(
        uint256 indexed userId,
        uint256 indexed assetId,
        uint256 indexed senderId,
        uint128 amt,
        bytes32[] dripsHistoryHashes
    );

    struct DripsStorage {
        /// @notice User drips states.
        /// The keys are the asset ID and the user ID.
        mapping(uint256 => mapping(uint256 => DripsState)) states;
    }

    struct DripsState {
        /// @notice The drips history hash, see `_hashDripsHistory`.
        bytes32 dripsHistoryHash;
        /// @notice The next squeezable timestamps. The key is the sender's user ID.
        /// Each `N`th element of the array is the next squeezable timestamp
        /// of the `N`th sender's drips configuration in effect in the current cycle.
        mapping(uint256 => uint32[2 ** 32]) nextSqueezed;
        /// @notice The drips receivers list hash, see `_hashDrips`.
        bytes32 dripsHash;
        /// @notice The next cycle to be received
        uint32 nextReceivableCycle;
        /// @notice The time when drips have been configured for the last time
        uint32 updateTime;
        /// @notice The maximum end time of drips
        uint32 maxEnd;
        /// @notice The balance when drips have been configured for the last time
        uint128 balance;
        /// @notice The number of drips configurations seen in the current cycle
        uint32 currCycleConfigs;
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

    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being receivable by their receivers.
    /// High value makes receiving cheaper by making it process less cycles for a given time range.
    /// Must be higher than 1.
    /// @param dripsStorageSlot The storage slot to holding a single `DripsStorage` structure.
    constructor(uint32 cycleSecs, bytes32 dripsStorageSlot) {
        require(cycleSecs > 1, "Cycle length too low");
        _cycleSecs = cycleSecs;
        _minAmtPerSec = (_AMT_PER_SEC_MULTIPLIER + cycleSecs - 1) / cycleSecs;
        _dripsStorageSlot = dripsStorageSlot;
    }

    /// @notice Receive drips from unreceived cycles of the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The received amount
    function _receiveDrips(uint256 userId, uint256 assetId, uint32 maxCycles)
        internal
        returns (uint128 receivedAmt)
    {
        uint32 receivableCycles;
        uint32 fromCycle;
        uint32 toCycle;
        int128 finalAmtPerCycle;
        (receivedAmt, receivableCycles, fromCycle, toCycle, finalAmtPerCycle) =
            _receiveDripsResult(userId, assetId, maxCycles);
        if (fromCycle != toCycle) {
            DripsState storage state = _dripsStorage().states[assetId][userId];
            state.nextReceivableCycle = toCycle;
            mapping(uint32 => AmtDelta) storage amtDeltas = state.amtDeltas;
            for (uint32 cycle = fromCycle; cycle < toCycle; cycle++) {
                delete amtDeltas[cycle];
            }
            // The next cycle delta must be relative to the last received cycle, which got zeroed.
            // In other words the next cycle delta must be an absolute value.
            if (finalAmtPerCycle != 0) {
                amtDeltas[toCycle].thisCycle += finalAmtPerCycle;
            }
        }
        emit ReceivedDrips(userId, assetId, receivedAmt, receivableCycles);
    }

    /// @notice Calculate effects of calling `_receiveDrips` with the given parameters.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The amount which would be received
    /// @return receivableCycles The number of cycles which would still be receivable after the call
    /// @return fromCycle The cycle from which funds would be received
    /// @return toCycle The cycle to which funds would be received
    /// @return amtPerCycle The amount per cycle when `toCycle` starts.
    function _receiveDripsResult(uint256 userId, uint256 assetId, uint32 maxCycles)
        internal
        view
        returns (
            uint128 receivedAmt,
            uint32 receivableCycles,
            uint32 fromCycle,
            uint32 toCycle,
            int128 amtPerCycle
        )
    {
        (fromCycle, toCycle) = _receivableDripsCyclesRange(userId, assetId);
        if (toCycle - fromCycle > maxCycles) {
            receivableCycles = toCycle - fromCycle - maxCycles;
            toCycle -= receivableCycles;
        }
        mapping(uint32 => AmtDelta) storage amtDeltas =
            _dripsStorage().states[assetId][userId].amtDeltas;
        for (uint32 cycle = fromCycle; cycle < toCycle; cycle++) {
            AmtDelta memory amtDelta = amtDeltas[cycle];
            amtPerCycle += amtDelta.thisCycle;
            receivedAmt += uint128(amtPerCycle);
            amtPerCycle += amtDelta.nextCycle;
        }
    }

    /// @notice Counts cycles from which drips can be received.
    /// This function can be used to detect that there are
    /// too many cycles to analyze in a single transaction.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return cycles The number of cycles which can be flushed
    function _receivableDripsCycles(uint256 userId, uint256 assetId)
        internal
        view
        returns (uint32 cycles)
    {
        (uint32 fromCycle, uint32 toCycle) = _receivableDripsCyclesRange(userId, assetId);
        return toCycle - fromCycle;
    }

    /// @notice Calculates the cycles range from which drips can be received.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return fromCycle The cycle from which funds can be received
    /// @return toCycle The cycle to which funds can be received
    function _receivableDripsCyclesRange(uint256 userId, uint256 assetId)
        private
        view
        returns (uint32 fromCycle, uint32 toCycle)
    {
        fromCycle = _dripsStorage().states[assetId][userId].nextReceivableCycle;
        toCycle = _cycleOf(_currTimestamp());
        // slither-disable-next-line timestamp
        if (fromCycle == 0 || toCycle < fromCycle) {
            toCycle = fromCycle;
        }
    }

    /// @notice Receive drips from the currently running cycle from a single sender.
    /// It doesn't receive drips from the previous, finished cycles, to do that use `_receiveDrips`.
    /// Squeezed funds won't be received in the next calls to `_squeezeDrips` or `_receiveDrips`.
    /// Only funds dripped before `block.timestamp` can be squeezed.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param assetId The used asset ID.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @param historyHash The sender's history hash which was valid right before
    /// they set up the sequence of configurations described by `dripsHistory`.
    /// @param dripsHistory The sequence of the sender's drips configurations.
    /// It can start at an arbitrary past configuration, but must describe all the configurations
    /// which have been used since then including the current one, in the chronological order.
    /// Only drips described by `dripsHistory` will be squeezed.
    /// If `dripsHistory` entries have no receivers, they won't be squeezed.
    /// @return amt The squeezed amount.
    function _squeezeDrips(
        uint256 userId,
        uint256 assetId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) internal returns (uint128 amt) {
        uint256 squeezedNum;
        uint256[] memory squeezedRevIdxs;
        bytes32[] memory historyHashes;
        uint256 currCycleConfigs;
        (amt, squeezedNum, squeezedRevIdxs, historyHashes, currCycleConfigs) =
            _squeezeDripsResult(userId, assetId, senderId, historyHash, dripsHistory);
        bytes32[] memory squeezedHistoryHashes = new bytes32[](squeezedNum);
        DripsState storage state = _dripsStorage().states[assetId][userId];
        uint32[2 ** 32] storage nextSqueezed = state.nextSqueezed[senderId];
        for (uint256 i = 0; i < squeezedNum; i++) {
            // `squeezedRevIdxs` are sorted from the newest configuration to the oldest,
            // but we need to consume them from the oldest to the newest.
            uint256 revIdx = squeezedRevIdxs[squeezedNum - i - 1];
            squeezedHistoryHashes[i] = historyHashes[historyHashes.length - revIdx];
            nextSqueezed[currCycleConfigs - revIdx] = _currTimestamp();
        }
        uint32 cycleStart = _currCycleStart();
        _addDeltaRange(state, cycleStart, cycleStart + 1, -int160(amt * _AMT_PER_SEC_MULTIPLIER));
        emit SqueezedDrips(userId, assetId, senderId, amt, squeezedHistoryHashes);
    }

    /// @notice Calculate effects of calling `_squeezeDrips` with the given parameters.
    /// See its documentation for more details.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param assetId The used asset ID.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @param historyHash The sender's history hash which was valid right before `dripsHistory`.
    /// @param dripsHistory The sequence of the sender's drips configurations.
    /// @return amt The squeezed amount.
    /// @return squeezedNum The number of squeezed history entries.
    /// @return squeezedRevIdxs The indexes of the squeezed history entries.
    /// The indexes are reversed, meaning that to get the actual index in an array,
    /// they must counted from the end of arrays, as in `arrayLength - squeezedRevIdxs[i]`.
    /// These indexes can be safely used to access `dripsHistory`, `historyHashes`
    /// and `nextSqueezed` regardless of their lengths.
    /// `squeezeRevIdxs` is sorted ascending, from pointing at the most recent entry to the oldest.
    /// @return historyHashes The history hashes valid for squeezing each of `dripsHistory` entries.
    /// In other words history hashes which had been valid right before each drips
    /// configuration was set, matching `dripsHistoryHash` emitted in its `DripsSet`.
    /// The first item is always equal to `historyHash`.
    /// @return currCycleConfigs The number of the sender's
    /// drips configurations which have been seen in the current cycle.
    /// This is also the number of used entries in each of the sender's `nextSqueezed` arrays.
    function _squeezeDripsResult(
        uint256 userId,
        uint256 assetId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    )
        internal
        view
        returns (
            uint128 amt,
            uint256 squeezedNum,
            uint256[] memory squeezedRevIdxs,
            bytes32[] memory historyHashes,
            uint256 currCycleConfigs
        )
    {
        {
            DripsState storage sender = _dripsStorage().states[assetId][senderId];
            historyHashes = _verifyDripsHistory(historyHash, dripsHistory, sender.dripsHistoryHash);
            // If the last update was not in the current cycle,
            // there's only the single latest history entry to squeeze in the current cycle.
            currCycleConfigs = 1;
            // slither-disable-next-line timestamp
            if (sender.updateTime >= _currCycleStart()) currCycleConfigs = sender.currCycleConfigs;
        }
        squeezedRevIdxs = new uint256[](dripsHistory.length);
        uint32[2 ** 32] storage nextSqueezed =
            _dripsStorage().states[assetId][userId].nextSqueezed[senderId];
        uint32 squeezeEndCap = _currTimestamp();
        for (uint256 i = 1; i <= dripsHistory.length && i <= currCycleConfigs; i++) {
            DripsHistory memory drips = dripsHistory[dripsHistory.length - i];
            if (drips.receivers.length != 0) {
                uint32 squeezeStartCap = nextSqueezed[currCycleConfigs - i];
                if (squeezeStartCap < _currCycleStart()) squeezeStartCap = _currCycleStart();
                if (squeezeStartCap < drips.updateTime) squeezeStartCap = drips.updateTime;
                if (squeezeStartCap < squeezeEndCap) {
                    squeezedRevIdxs[squeezedNum++] = i;
                    amt += _squeezedAmt(userId, drips, squeezeStartCap, squeezeEndCap);
                }
            }
            squeezeEndCap = drips.updateTime;
        }
    }

    /// @notice Verify a drips history and revert if it's invalid.
    /// @param historyHash The user's history hash which was valid right before `dripsHistory`.
    /// @param dripsHistory The sequence of the user's drips configurations.
    /// @param finalHistoryHash The history hash at the end of `dripsHistory`.
    /// @return historyHashes The history hashes valid for squeezing each of `dripsHistory` entries.
    /// In other words history hashes which had been valid right before each drips
    /// configuration was set, matching `dripsHistoryHash`es emitted in `DripsSet`.
    /// The first item is always equal to `historyHash` and `finalHistoryHash` is never included.
    function _verifyDripsHistory(
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory,
        bytes32 finalHistoryHash
    ) private pure returns (bytes32[] memory historyHashes) {
        historyHashes = new bytes32[](dripsHistory.length);
        for (uint256 i = 0; i < dripsHistory.length; i++) {
            DripsHistory memory drips = dripsHistory[i];
            bytes32 dripsHash = drips.dripsHash;
            if (drips.receivers.length != 0) {
                require(dripsHash == 0, "Entry with hash and receivers");
                dripsHash = _hashDrips(drips.receivers);
            }
            historyHashes[i] = historyHash;
            historyHash = _hashDripsHistory(historyHash, dripsHash, drips.updateTime, drips.maxEnd);
        }
        // slither-disable-next-line incorrect-equality,timestamp
        require(historyHash == finalHistoryHash, "Invalid drips history");
    }

    /// @notice Calculate the amount squeezable by a user from a single drips history entry.
    /// @param userId The ID of the user to squeeze drips for.
    /// @param dripsHistory The squeezed history entry.
    /// @param squeezeStartCap The squeezed time range start.
    /// @param squeezeEndCap The squeezed time range end.
    /// @return squeezedAmt The squeezed amount.
    function _squeezedAmt(
        uint256 userId,
        DripsHistory memory dripsHistory,
        uint32 squeezeStartCap,
        uint32 squeezeEndCap
    ) private view returns (uint128 squeezedAmt) {
        DripsReceiver[] memory receivers = dripsHistory.receivers;
        // Binary search for the `idx` of the first occurrence of `userId`
        uint256 idx = 0;
        for (uint256 idxCap = receivers.length; idx < idxCap;) {
            uint256 idxMid = (idx + idxCap) / 2;
            if (receivers[idxMid].userId < userId) {
                idx = idxMid + 1;
            } else {
                idxCap = idxMid;
            }
        }
        uint32 updateTime = dripsHistory.updateTime;
        uint32 maxEnd = dripsHistory.maxEnd;
        uint256 amt = 0;
        for (; idx < receivers.length; idx++) {
            DripsReceiver memory receiver = receivers[idx];
            if (receiver.userId != userId) break;
            (uint32 start, uint32 end) =
                _dripsRange(receiver, updateTime, maxEnd, squeezeStartCap, squeezeEndCap);
            amt += _drippedAmt(receiver.config.amtPerSec(), start, end);
        }
        return uint128(amt);
    }

    /// @notice Current user drips state.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return dripsHash The current drips receivers list hash, see `_hashDrips`
    /// @return dripsHistoryHash The current drips history hash, see `_hashDripsHistory`.
    /// @return updateTime The time when drips have been configured for the last time
    /// @return balance The balance when drips have been configured for the last time
    /// @return maxEnd The current maximum end time of drips
    function _dripsState(uint256 userId, uint256 assetId)
        internal
        view
        returns (
            bytes32 dripsHash,
            bytes32 dripsHistoryHash,
            uint32 updateTime,
            uint128 balance,
            uint32 maxEnd
        )
    {
        DripsState storage state = _dripsStorage().states[assetId][userId];
        return
            (state.dripsHash, state.dripsHistoryHash, state.updateTime, state.balance, state.maxEnd);
    }

    /// @notice User's drips balance at a given timestamp
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param currReceivers The current drips receivers list.
    /// It must be exactly the same as the last list set for the user with `_setDrips`.
    /// @param timestamp The timestamps for which balance should be calculated.
    /// It can't be lower than the timestamp of the last call to `setDrips`.
    /// If it's bigger than `block.timestamp`, then it's a prediction assuming
    /// that `setDrips` won't be called before `timestamp`.
    /// @return balance The user balance on `timestamp`
    function _balanceAt(
        uint256 userId,
        uint256 assetId,
        DripsReceiver[] memory currReceivers,
        uint32 timestamp
    ) internal view returns (uint128 balance) {
        DripsState storage state = _dripsStorage().states[assetId][userId];
        require(timestamp >= state.updateTime, "Timestamp before the last update");
        _verifyDripsReceivers(currReceivers, state);
        return _calcBalance(state.balance, state.updateTime, state.maxEnd, currReceivers, timestamp);
    }

    /// @notice Calculates the drips balance at a given timestamp.
    /// @param lastBalance The balance when drips have started
    /// @param lastUpdate The timestamp when drips have started.
    /// @param maxEnd The maximum end time of drips
    /// @param receivers The list of drips receivers.
    /// @param timestamp The timestamps for which balance should be calculated.
    /// It can't be lower than `lastUpdate`.
    /// If it's bigger than `block.timestamp`, then it's a prediction assuming
    /// that `setDrips` won't be called before `timestamp`.
    /// @return balance The user balance on `timestamp`
    function _calcBalance(
        uint128 lastBalance,
        uint32 lastUpdate,
        uint32 maxEnd,
        DripsReceiver[] memory receivers,
        uint32 timestamp
    ) private view returns (uint128 balance) {
        balance = lastBalance;
        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory receiver = receivers[i];
            (uint32 start, uint32 end) = _dripsRange({
                receiver: receiver,
                updateTime: lastUpdate,
                maxEnd: maxEnd,
                startCap: lastUpdate,
                endCap: timestamp
            });
            balance -= uint128(_drippedAmt(receiver.config.amtPerSec(), start, end));
        }
    }

    /// @notice Sets the user's drips configuration.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param currReceivers The current drips receivers list.
    /// It must be exactly the same as the last list set for the user with `_setDrips`.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change being applied.
    /// Positive when adding funds to the drips balance, negative to removing them.
    /// @param newReceivers The list of the drips receivers of the user to be set.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @param maxEndHint1 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The first hint for finding the maximum end time when all drips stop due to funds
    /// running out after the balance is updated and the new receivers list is applied.
    /// Hints have no effect on the results of calling this function, except potentially saving gas.
    /// Hints are Unix timestamps used as the starting points for binary search for the time
    /// when funds run out in the range of timestamps from the current block's to `2^32`.
    /// Hints lower than the current timestamp are ignored.
    /// You can provide zero, one or two hints. The order of hints doesn't matter.
    /// Hints are the most effective when one of them is lower than or equal to
    /// the last timestamp when funds are still dripping, and the other one is strictly larger
    /// than that timestamp,the smaller the difference between such hints, the higher gas savings.
    /// The savings are the highest possible when one of the hints is equal to
    /// the last timestamp when funds are still dripping, and the other one is larger by 1.
    /// It's worth noting that the exact timestamp of the block in which this function is executed
    /// may affect correctness of the hints, especially if they're precise.
    /// Hints don't provide any benefits when balance is not enough to cover
    /// a single second of dripping or is enough to cover all drips until timestamp `2^32`.
    /// Even inaccurate hints can be useful, and providing a single hint
    /// or two hints that don't enclose the time when funds run out can still save some gas.
    /// Providing poor hints that don't reduce the number of binary search steps
    /// may cause slightly higher gas usage than not providing any hints.
    /// @param maxEndHint2 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The second hint for finding the maximum end time, see `maxEndHint1` docs for more details.
    /// @return realBalanceDelta The actually applied drips balance change.
    function _setDrips(
        uint256 userId,
        uint256 assetId,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers,
        // slither-disable-next-line similar-names
        uint32 maxEndHint1,
        uint32 maxEndHint2
    ) internal returns (int128 realBalanceDelta) {
        DripsState storage state = _dripsStorage().states[assetId][userId];
        _verifyDripsReceivers(currReceivers, state);
        uint32 lastUpdate = state.updateTime;
        uint128 newBalance;
        uint32 newMaxEnd;
        {
            uint32 currMaxEnd = state.maxEnd;
            int128 currBalance = int128(
                _calcBalance(state.balance, lastUpdate, currMaxEnd, currReceivers, _currTimestamp())
            );
            realBalanceDelta = balanceDelta;
            // Cap `realBalanceDelta` at withdrawal of the entire `currBalance`
            if (realBalanceDelta < -currBalance) {
                realBalanceDelta = -currBalance;
            }
            newBalance = uint128(currBalance + realBalanceDelta);
            newMaxEnd = _calcMaxEnd(newBalance, newReceivers, maxEndHint1, maxEndHint2);
            _updateReceiverStates(
                _dripsStorage().states[assetId],
                currReceivers,
                lastUpdate,
                currMaxEnd,
                newReceivers,
                newMaxEnd
            );
        }
        state.updateTime = _currTimestamp();
        state.maxEnd = newMaxEnd;
        state.balance = newBalance;
        bytes32 dripsHistory = state.dripsHistoryHash;
        // slither-disable-next-line timestamp
        if (dripsHistory != 0 && _cycleOf(lastUpdate) != _cycleOf(_currTimestamp())) {
            state.currCycleConfigs = 2;
        } else {
            state.currCycleConfigs++;
        }
        bytes32 newDripsHash = _hashDrips(newReceivers);
        state.dripsHistoryHash =
            _hashDripsHistory(dripsHistory, newDripsHash, _currTimestamp(), newMaxEnd);
        emit DripsSet(userId, assetId, newDripsHash, dripsHistory, newBalance, newMaxEnd);
        // slither-disable-next-line timestamp
        if (newDripsHash != state.dripsHash) {
            state.dripsHash = newDripsHash;
            for (uint256 i = 0; i < newReceivers.length; i++) {
                DripsReceiver memory receiver = newReceivers[i];
                emit DripsReceiverSeen(newDripsHash, receiver.userId, receiver.config);
            }
        }
    }

    /// @notice Verifies that the provided list of receivers is currently active for the user.
    /// @param currReceivers The verified list of receivers.
    /// @param state The user's state.
    function _verifyDripsReceivers(DripsReceiver[] memory currReceivers, DripsState storage state)
        private
        view
    {
        require(_hashDrips(currReceivers) == state.dripsHash, "Invalid current drips list");
    }

    /// @notice Calculates the maximum end time of drips.
    /// @param balance The balance when drips have started
    /// @param receivers The list of drips receivers.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @param hint1 The first hint for finding the maximum end time.
    /// See `_setDrips` docs for `maxEndHint1` for more details.
    /// @param hint2 The second hint for finding the maximum end time.
    /// See `_setDrips` docs for `maxEndHint2` for more details.
    /// @return maxEnd The maximum end time of drips
    function _calcMaxEnd(
        uint128 balance,
        DripsReceiver[] memory receivers,
        uint32 hint1,
        uint32 hint2
    ) private view returns (uint32 maxEnd) {
        unchecked {
            (uint256[] memory configs, uint256 configsLen) = _buildConfigs(receivers);

            uint256 enoughEnd = _currTimestamp();
            // slither-disable-start incorrect-equality,timestamp
            if (configsLen == 0 || balance == 0) {
                return uint32(enoughEnd);
            }

            uint256 notEnoughEnd = type(uint32).max;
            if (_isBalanceEnough(balance, configs, configsLen, notEnoughEnd)) {
                return uint32(notEnoughEnd);
            }

            if (hint1 > enoughEnd && hint1 < notEnoughEnd) {
                if (_isBalanceEnough(balance, configs, configsLen, hint1)) {
                    enoughEnd = hint1;
                } else {
                    notEnoughEnd = hint1;
                }
            }

            if (hint2 > enoughEnd && hint2 < notEnoughEnd) {
                if (_isBalanceEnough(balance, configs, configsLen, hint2)) {
                    enoughEnd = hint2;
                } else {
                    notEnoughEnd = hint2;
                }
            }

            while (true) {
                uint256 end = (enoughEnd + notEnoughEnd) / 2;
                if (end == enoughEnd) {
                    return uint32(end);
                }
                if (_isBalanceEnough(balance, configs, configsLen, end)) {
                    enoughEnd = end;
                } else {
                    notEnoughEnd = end;
                }
            }
            // slither-disable-end incorrect-equality,timestamp
        }
    }

    /// @notice Check if a given balance is enough to cover drips with the given `maxEnd`.
    /// @param balance The balance when drips have started
    /// @param configs The list of drips configurations
    /// @param configsLen The length of `configs`
    /// @param maxEnd The maximum end time of drips
    /// @return isEnough `true` if the balance is enough, `false` otherwise
    function _isBalanceEnough(
        uint256 balance,
        uint256[] memory configs,
        uint256 configsLen,
        uint256 maxEnd
    ) private view returns (bool isEnough) {
        unchecked {
            uint256 spent = 0;
            for (uint256 i = 0; i < configsLen; i++) {
                (uint256 amtPerSec, uint256 start, uint256 end) = _getConfig(configs, i);
                // slither-disable-next-line timestamp
                if (maxEnd <= start) {
                    continue;
                }
                // slither-disable-next-line timestamp
                if (end > maxEnd) {
                    end = maxEnd;
                }
                spent += _drippedAmt(amtPerSec, start, end);
                if (spent > balance) {
                    return false;
                }
            }
            return true;
        }
    }

    /// @notice Build a preprocessed list of drips configurations from receivers.
    /// @param receivers The list of drips receivers.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @return configs The list of drips configurations
    /// @return configsLen The length of `configs`
    function _buildConfigs(DripsReceiver[] memory receivers)
        private
        view
        returns (uint256[] memory configs, uint256 configsLen)
    {
        unchecked {
            require(receivers.length <= _MAX_DRIPS_RECEIVERS, "Too many drips receivers");
            configs = new uint256[](receivers.length);
            for (uint256 i = 0; i < receivers.length; i++) {
                DripsReceiver memory receiver = receivers[i];
                if (i > 0) {
                    require(_isOrdered(receivers[i - 1], receiver), "Drips receivers not sorted");
                }
                configsLen = _addConfig(configs, configsLen, receiver);
            }
        }
    }

    /// @notice Preprocess and add a drips receiver to the list of configurations.
    /// @param configs The list of drips configurations
    /// @param configsLen The length of `configs`
    /// @param receiver The added drips receiver.
    /// @return newConfigsLen The new length of `configs`
    function _addConfig(uint256[] memory configs, uint256 configsLen, DripsReceiver memory receiver)
        private
        view
        returns (uint256 newConfigsLen)
    {
        uint256 amtPerSec = receiver.config.amtPerSec();
        require(amtPerSec >= _minAmtPerSec, "Drips receiver amtPerSec too low");
        (uint256 start, uint256 end) =
            _dripsRangeInFuture(receiver, _currTimestamp(), type(uint32).max);
        // slither-disable-next-line incorrect-equality,timestamp
        if (start == end) {
            return configsLen;
        }
        configs[configsLen] = (amtPerSec << 64) | (start << 32) | end;
        return configsLen + 1;
    }

    /// @notice Load a drips configuration from the list.
    /// @param configs The list of drips configurations
    /// @param idx The loaded configuration index. It must be smaller than the `configs` length.
    /// @return amtPerSec The amount per second being dripped.
    /// @return start The timestamp when dripping starts.
    /// @return end The maximum timestamp when dripping ends.
    function _getConfig(uint256[] memory configs, uint256 idx)
        private
        pure
        returns (uint256 amtPerSec, uint256 start, uint256 end)
    {
        uint256 val;
        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            val := mload(add(32, add(configs, shl(5, idx))))
        }
        return (val >> 64, uint32(val >> 32), uint32(val));
    }

    /// @notice Calculates the hash of the drips configuration.
    /// It's used to verify if drips configuration is the previously set one.
    /// @param receivers The list of the drips receivers.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// If the drips have never been updated, pass an empty array.
    /// @return dripsHash The hash of the drips configuration
    function _hashDrips(DripsReceiver[] memory receivers)
        internal
        pure
        returns (bytes32 dripsHash)
    {
        if (receivers.length == 0) {
            return bytes32(0);
        }
        return keccak256(abi.encode(receivers));
    }

    /// @notice Calculates the hash of the drips history after the drips configuration is updated.
    /// @param oldDripsHistoryHash The history hash which was valid before the drips were updated.
    /// The `dripsHistoryHash` of a user before they set drips for the first time is `0`.
    /// @param dripsHash The hash of the drips receivers being set.
    /// @param updateTime The timestamp when the drips are updated.
    /// @param maxEnd The maximum end of the drips being set.
    /// @return dripsHistoryHash The hash of the updated drips history.
    function _hashDripsHistory(
        bytes32 oldDripsHistoryHash,
        bytes32 dripsHash,
        uint32 updateTime,
        uint32 maxEnd
    ) internal pure returns (bytes32 dripsHistoryHash) {
        return keccak256(abi.encode(oldDripsHistoryHash, dripsHash, updateTime, maxEnd));
    }

    /// @notice Applies the effects of the change of the drips on the receivers' drips states.
    /// @param states The drips states for the used asset.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user.
    /// If this is the first update, pass an empty array.
    /// @param lastUpdate the last time the sender updated the drips.
    /// If this is the first update, pass zero.
    /// @param currMaxEnd The maximum end time of drips according to the last drips update.
    /// @param newReceivers  The list of the drips receivers of the user to be set.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @param newMaxEnd The maximum end time of drips according to the new drips configuration.
    function _updateReceiverStates(
        mapping(uint256 => DripsState) storage states,
        DripsReceiver[] memory currReceivers,
        uint32 lastUpdate,
        uint32 currMaxEnd,
        DripsReceiver[] memory newReceivers,
        uint32 newMaxEnd
    ) private {
        uint256 currIdx = 0;
        uint256 newIdx = 0;
        while (true) {
            bool pickCurr = currIdx < currReceivers.length;
            // slither-disable-next-line uninitialized-local
            DripsReceiver memory currRecv;
            if (pickCurr) {
                currRecv = currReceivers[currIdx];
            }

            bool pickNew = newIdx < newReceivers.length;
            // slither-disable-next-line uninitialized-local
            DripsReceiver memory newRecv;
            if (pickNew) {
                newRecv = newReceivers[newIdx];
            }

            // Limit picking both curr and new to situations when they differ only by time
            if (
                pickCurr && pickNew
                    && (
                        currRecv.userId != newRecv.userId
                            || currRecv.config.amtPerSec() != newRecv.config.amtPerSec()
                    )
            ) {
                pickCurr = _isOrdered(currRecv, newRecv);
                pickNew = !pickCurr;
            }

            if (pickCurr && pickNew) {
                // Shift the existing drip to fulfil the new configuration
                DripsState storage state = states[currRecv.userId];
                (uint32 currStart, uint32 currEnd) =
                    _dripsRangeInFuture(currRecv, lastUpdate, currMaxEnd);
                (uint32 newStart, uint32 newEnd) =
                    _dripsRangeInFuture(newRecv, _currTimestamp(), newMaxEnd);
                int256 amtPerSec = int256(uint256(currRecv.config.amtPerSec()));
                // Move the start and end times if updated. This has the same effects as calling
                // _addDeltaRange(state, currStart, currEnd, -amtPerSec);
                // _addDeltaRange(state, newStart, newEnd, amtPerSec);
                // but it allows skipping storage access if there's no change to the starts or ends.
                _addDeltaRange(state, currStart, newStart, -amtPerSec);
                _addDeltaRange(state, currEnd, newEnd, amtPerSec);
                // Ensure that the user receives the updated cycles
                uint32 currStartCycle = _cycleOf(currStart);
                uint32 newStartCycle = _cycleOf(newStart);
                // The `currStartCycle > newStartCycle` check is just an optimization.
                // If it's false, then `state.nextReceivableCycle > newStartCycle` must be
                // false too, there's no need to pay for the storage access to check it.
                // slither-disable-next-line timestamp
                if (currStartCycle > newStartCycle && state.nextReceivableCycle > newStartCycle) {
                    state.nextReceivableCycle = newStartCycle;
                }
            } else if (pickCurr) {
                // Remove an existing drip
                // slither-disable-next-line similar-names
                DripsState storage state = states[currRecv.userId];
                (uint32 start, uint32 end) = _dripsRangeInFuture(currRecv, lastUpdate, currMaxEnd);
                // slither-disable-next-line similar-names
                int256 amtPerSec = int256(uint256(currRecv.config.amtPerSec()));
                _addDeltaRange(state, start, end, -amtPerSec);
            } else if (pickNew) {
                // Create a new drip
                DripsState storage state = states[newRecv.userId];
                // slither-disable-next-line uninitialized-local
                (uint32 start, uint32 end) =
                    _dripsRangeInFuture(newRecv, _currTimestamp(), newMaxEnd);
                int256 amtPerSec = int256(uint256(newRecv.config.amtPerSec()));
                _addDeltaRange(state, start, end, amtPerSec);
                // Ensure that the user receives the updated cycles
                uint32 startCycle = _cycleOf(start);
                // slither-disable-next-line timestamp
                uint32 nextReceivableCycle = state.nextReceivableCycle;
                if (nextReceivableCycle == 0 || nextReceivableCycle > startCycle) {
                    state.nextReceivableCycle = startCycle;
                }
            } else {
                break;
            }

            if (pickCurr) {
                currIdx++;
            }
            if (pickNew) {
                newIdx++;
            }
        }
    }

    /// @notice Calculates the time range in the future in which a receiver will be dripped to.
    /// @param receiver The drips receiver
    /// @param maxEnd The maximum end time of drips
    function _dripsRangeInFuture(DripsReceiver memory receiver, uint32 updateTime, uint32 maxEnd)
        private
        view
        returns (uint32 start, uint32 end)
    {
        return _dripsRange(receiver, updateTime, maxEnd, _currTimestamp(), type(uint32).max);
    }

    /// @notice Calculates the time range in which a receiver is to be dripped to.
    /// This range is capped to provide a view on drips through a specific time window.
    /// @param receiver The drips receiver
    /// @param updateTime The time when drips are configured
    /// @param maxEnd The maximum end time of drips
    /// @param startCap The timestamp the drips range start should be capped to
    /// @param endCap The timestamp the drips range end should be capped to
    function _dripsRange(
        DripsReceiver memory receiver,
        uint32 updateTime,
        uint32 maxEnd,
        uint32 startCap,
        uint32 endCap
    ) private pure returns (uint32 start, uint32 end_) {
        start = receiver.config.start();
        // slither-disable-start timestamp
        if (start == 0) {
            start = updateTime;
        }
        uint40 end = uint40(start) + receiver.config.duration();
        // slither-disable-next-line incorrect-equality
        if (end == start || end > maxEnd) {
            end = maxEnd;
        }
        if (start < startCap) {
            start = startCap;
        }
        if (end > endCap) {
            end = endCap;
        }
        if (end < start) {
            end = start;
        }
        // slither-disable-end timestamp
        return (start, uint32(end));
    }

    /// @notice Adds funds received by a user in a given time range
    /// @param state The user state
    /// @param start The timestamp from which the delta takes effect
    /// @param end The timestamp until which the delta takes effect
    /// @param amtPerSec The dripping rate
    function _addDeltaRange(DripsState storage state, uint32 start, uint32 end, int256 amtPerSec)
        private
    {
        // slither-disable-next-line incorrect-equality,timestamp
        if (start == end) {
            return;
        }
        mapping(uint32 => AmtDelta) storage amtDeltas = state.amtDeltas;
        _addDelta(amtDeltas, start, amtPerSec);
        _addDelta(amtDeltas, end, -amtPerSec);
    }

    /// @notice Adds delta of funds received by a user at a given time
    /// @param amtDeltas The user amount deltas
    /// @param timestamp The timestamp when the deltas need to be added
    /// @param amtPerSec The dripping rate
    function _addDelta(
        mapping(uint32 => AmtDelta) storage amtDeltas,
        uint256 timestamp,
        int256 amtPerSec
    ) private {
        unchecked {
            // In order to set a delta on a specific timestamp it must be introduced in two cycles.
            // These formulas follow the logic from `_drippedAmt`, see it for more details.
            int256 amtPerSecMultiplier = int160(_AMT_PER_SEC_MULTIPLIER);
            int256 fullCycle = (int256(uint256(_cycleSecs)) * amtPerSec) / amtPerSecMultiplier;
            // slither-disable-next-line weak-prng
            int256 nextCycle = (int256(timestamp % _cycleSecs) * amtPerSec) / amtPerSecMultiplier;
            AmtDelta storage amtDelta = amtDeltas[_cycleOf(uint32(timestamp))];
            // Any over- or under-flows are fine, they're guaranteed to be fixed by a matching
            // under- or over-flow from the other call to `_addDelta` made by `_addDeltaRange`.
            // This is because the total balance of `Drips` can never exceed `type(int128).max`,
            // so in the end no amtDelta can have delta higher than `type(int128).max`.
            amtDelta.thisCycle += int128(fullCycle - nextCycle);
            amtDelta.nextCycle += int128(nextCycle);
        }
    }

    /// @notice Checks if two receivers fulfil the sortedness requirement of the receivers list.
    /// @param prev The previous receiver
    /// @param next The next receiver
    function _isOrdered(DripsReceiver memory prev, DripsReceiver memory next)
        private
        pure
        returns (bool)
    {
        if (prev.userId != next.userId) {
            return prev.userId < next.userId;
        }
        return prev.config.lt(next.config);
    }

    /// @notice Calculates the amount dripped over a time range.
    /// The amount dripped in the `N`th second of each cycle is:
    /// `(N + 1) * amtPerSec / AMT_PER_SEC_MULTIPLIER - N * amtPerSec / AMT_PER_SEC_MULTIPLIER`.
    /// For a range of `N`s from `0` to `M` the sum of the dripped amounts is calculated as:
    /// `M * amtPerSec / AMT_PER_SEC_MULTIPLIER` assuming that `M <= cycleSecs`.
    /// For an arbitrary time range across multiple cycles the amount is calculated as the sum of
    /// the amount dripped in the start cycle, each of the full cycles in between and the end cycle.
    /// This algorithm has the following properties:
    /// - During every second full units are dripped, there are no partially dripped units.
    /// - Undripped fractions are dripped when they add up into full units.
    /// - Undripped fractions don't add up across cycle end boundaries.
    /// - Some seconds drip more units and some less.
    /// - Every `N`th second of each cycle drips the same amount.
    /// - Every full cycle drips the same amount.
    /// - The amount dripped in a given second is independent from the dripping start and end.
    /// - Dripping over time ranges `A:B` and then `B:C` is equivalent to dripping over `A:C`.
    /// - Different drips existing in the system don't interfere with each other.
    /// @param amtPerSec The dripping rate
    /// @param start The dripping start time
    /// @param end The dripping end time
    /// @return amt The dripped amount
    function _drippedAmt(uint256 amtPerSec, uint256 start, uint256 end)
        private
        view
        returns (uint256 amt)
    {
        // This function is written in Yul because it can be called thousands of times
        // per transaction and it needs to be optimized as much as possible.
        // As of Solidity 0.8.13, rewriting it in unchecked Solidity triples its gas cost.
        uint256 cycleSecs = _cycleSecs;
        // slither-disable-next-line assembly
        assembly {
            let endedCycles := sub(div(end, cycleSecs), div(start, cycleSecs))
            // slither-disable-next-line divide-before-multiply
            let amtPerCycle := div(mul(cycleSecs, amtPerSec), _AMT_PER_SEC_MULTIPLIER)
            amt := mul(endedCycles, amtPerCycle)
            // slither-disable-next-line weak-prng
            let amtEnd := div(mul(mod(end, cycleSecs), amtPerSec), _AMT_PER_SEC_MULTIPLIER)
            amt := add(amt, amtEnd)
            // slither-disable-next-line weak-prng
            let amtStart := div(mul(mod(start, cycleSecs), amtPerSec), _AMT_PER_SEC_MULTIPLIER)
            amt := sub(amt, amtStart)
        }
    }

    /// @notice Calculates the cycle containing the given timestamp.
    /// @param timestamp The timestamp.
    /// @return cycle The cycle containing the timestamp.
    function _cycleOf(uint32 timestamp) private view returns (uint32 cycle) {
        unchecked {
            return timestamp / _cycleSecs + 1;
        }
    }

    /// @notice The current timestamp, casted to the contract's internal representation.
    /// @return timestamp The current timestamp
    function _currTimestamp() private view returns (uint32 timestamp) {
        return uint32(block.timestamp);
    }

    /// @notice The current cycle start timestamp, casted to the contract's internal representation.
    /// @return timestamp The current cycle start timestamp
    function _currCycleStart() private view returns (uint32 timestamp) {
        uint32 currTimestamp = _currTimestamp();
        // slither-disable-next-line weak-prng
        return currTimestamp - (currTimestamp % _cycleSecs);
    }

    /// @notice Returns the Drips storage.
    /// @return dripsStorage The storage.
    function _dripsStorage() private view returns (DripsStorage storage dripsStorage) {
        bytes32 slot = _dripsStorageSlot;
        // slither-disable-next-line assembly
        assembly {
            dripsStorage.slot := slot
        }
    }
}
