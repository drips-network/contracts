// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

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
    /// Only the last non-skipped history entry affects the `nextSqueezableDrips` timestamp,
    /// so if a squeezed history list ends with `N` skipped entries, these `N` entries
    /// still will be squeezable in the following calls to `squeezeDrips`.
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
/// It's constructed from `amtPerSec`, `start` and `duration` as
/// `amtPerSec << 64 | start << 32 | duration`.
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
    /// @param _amtPerSec The amount per second being dripped. Must never be zero.
    /// It must have additional `Drips._AMT_PER_SEC_EXTRA_DECIMALS` decimals and can have fractions.
    /// To achieve that the passed value must be multiplied by `Drips._AMT_PER_SEC_MULTIPLIER`.
    /// @param _start The timestamp when dripping should start.
    /// If zero, use the timestamp when drips are configured.
    /// @param _duration The duration of dripping.
    /// If zero, drip until balance runs out.
    function create(
        uint192 _amtPerSec,
        uint32 _start,
        uint32 _duration
    ) internal pure returns (DripsConfig) {
        uint256 config = _amtPerSec;
        config = (config << 32) | _start;
        config = (config << 32) | _duration;
        return DripsConfig.wrap(config);
    }

    /// @notice Extracts amtPerSec from a `DripsConfig`
    function amtPerSec(DripsConfig config) internal pure returns (uint192) {
        return uint192(DripsConfig.unwrap(config) >> 64);
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

/// @notice Drips can keep track of at most `type(int128).max`
/// which is `2 ^ 127 - 1` units of each asset.
/// It's up to the caller to guarantee that this limit is never exceeded,
/// failing to do so may result in a total protocol collapse.
abstract contract Drips {
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits cost of changes in drips configuration.
    uint8 internal constant _MAX_DRIPS_RECEIVERS = 100;
    /// @notice The additional decimals for all amtPerSec values.
    uint8 internal constant _AMT_PER_SEC_EXTRA_DECIMALS = 18;
    /// @notice The multiplier for all amtPerSec values. It's `10 ** _AMT_PER_SEC_EXTRA_DECIMALS`.
    uint256 internal constant _AMT_PER_SEC_MULTIPLIER = 1_000_000_000_000_000_000;
    /// @notice The total amount the contract can keep track of each asset.
    uint256 internal constant _MAX_TOTAL_DRIPS_BALANCE = uint128(type(int128).max);
    /// @notice On every timestamp `T`, which is a multiple of `cycleSecs`, the receivers
    /// gain access to drips received during `T - cycleSecs` to `T - 1`.
    /// Always higher than 1.
    //uint32 internal immutable _cycleSecs;
    uint32 public immutable _cycleSecs;
    /// @notice The storage slot holding a single `DripsStorage` structure.
    //bytes32 private immutable _dripsStorageSlot;
    bytes32 public immutable _dripsStorageSlot;

    /// @notice Emitted when the drips configuration of a user is updated.
    /// @param userId The user ID.
    /// @param assetId The used asset ID
    /// @param receiversHash The drips receivers list hash
    /// @param dripsHistoryHash The drips history hash which was valid right before the update.
    /// @param balance The new drips balance. These funds will be dripped to the receivers.
    /// @param maxEnd The maximum end time of drips
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
        bytes32 indexed receiversHash,
        uint256 indexed userId,
        DripsConfig config
    );

    /// @notice Emitted when drips are received.
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

    /// @notice Emitted when drips are squeezed.
    /// @param userId The squeezing user ID.
    /// @param assetId The used asset ID.
    /// @param senderId The ID of the user sending drips which are squeezed.
    /// @param amt The squeezed amount.
    /// @param nextSqueezed The next timestamp that can be squeezed.
    event SqueezedDrips(
        uint256 indexed userId,
        uint256 indexed assetId,
        uint256 indexed senderId,
        uint128 amt,
        uint32 nextSqueezed
    );

    struct DripsStorage {
        /// @notice User drips states.
        /// The keys are the asset ID and the user ID.
        mapping(uint256 => mapping(uint256 => DripsState)) states;
    }

    struct DripsState {
        /// @notice The drips history hash, see `_hashDripsHistory`.
        bytes32 dripsHistoryHash;
        /// @notice The next timestamp for which the user can squeeze drips from the sender.
        /// The key is the sender's user ID. See `_nextSqueezedDrips`.
        mapping(uint256 => uint32) nextSqueezed;
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
        _dripsStorageSlot = dripsStorageSlot;
    }

    /// @notice Calculate effects of calling `_receiveDrips` with the given parameters.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivableAmt The amount which would be received
    /// @return receivableCycles The number of cycles which would still be receivable after the call
    function _receivableDrips(
        uint256 userId,
        uint256 assetId,
        uint32 maxCycles
    )   public
        // internal
        view returns (uint128 receivableAmt, uint32 receivableCycles) {
        (receivableAmt, receivableCycles, , , ) = _receivableDripsVerbose(
            userId,
            assetId,
            maxCycles
        );
    }

    /// @notice Receive drips from unreceived cycles of the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The received amount
    /// @return receivableCycles The number of cycles which still can be received
    function _receiveDrips(
        uint256 userId,
        uint256 assetId,
        uint32 maxCycles
    ) public virtual
        //internal
        returns (uint128 receivedAmt, uint32 receivableCycles) {
        uint32 fromCycle;
        uint32 toCycle;
        int128 finalAmtPerCycle;
        (
            receivedAmt,
            receivableCycles,
            fromCycle,
            toCycle,
            finalAmtPerCycle
        ) = _receivableDripsVerbose(userId, assetId, maxCycles);
        if (fromCycle != toCycle) {
            DripsState storage state = _dripsStorage().states[assetId][userId];
            state.nextReceivableCycle = toCycle;
            mapping(uint32 => AmtDelta) storage amtDeltas = state.amtDeltas;
            for (uint32 cycle = fromCycle; cycle < toCycle; cycle++) {
                delete amtDeltas[cycle];
            }
            // The next cycle delta must be relative to the last received cycle, which got zeroed.
            // In other words the next cycle delta must be an absolute value.
            if (finalAmtPerCycle != 0) amtDeltas[toCycle].thisCycle += finalAmtPerCycle;
        }
        emit ReceivedDrips(userId, assetId, receivedAmt, receivableCycles);
    }

    /// @notice Receivable drips from unreceived cycles of the user.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// @return receivedAmt The receivable amount
    /// @return receivableCycles The number of cycles which still will be receivable
    /// @return fromCycle The cycle from which funds can be received
    /// @return toCycle The cycle to which funds can be received
    /// @return amtPerCycle The amount per cycle when `toCycle` starts.
    function _receivableDripsVerbose(
        uint256 userId,
        uint256 assetId,
        uint32 maxCycles
    )
        //private
        internal
        virtual
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
        DripsState storage state = _dripsStorage().states[assetId][userId];
        for (uint32 cycle = fromCycle; cycle < toCycle; cycle++) {
            amtPerCycle += state.amtDeltas[cycle].thisCycle;
            receivedAmt += uint128(amtPerCycle);
            amtPerCycle += state.amtDeltas[cycle].nextCycle;
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
        //private
        public
        view
        returns (uint32 fromCycle, uint32 toCycle)
    {
        fromCycle = _dripsStorage().states[assetId][userId].nextReceivableCycle;
        toCycle = _cycleOf(_currTimestamp());
        if (fromCycle == 0 || toCycle < fromCycle) toCycle = fromCycle;
    }

    /// @notice Receive drips from the currently running cycle from a single sender.
    /// It doesn't receive drips from the previous, finished cycles, to do that use `_receiveDrips`.
    /// Squeezed funds won't be received in the next calls to `_squeezeDrips` or `_receiveDrips`.
    /// Only funds dripped from `_nextSqueezedDrips` to `block.timestamp` can be squeezed.
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
    /// The next call to `_squeezeDrips` will be able to squeeze only funds which
    /// have been dripped after the last timestamp squeezed in this call.
    /// This may cause some funds to be unreceivable until the current cycle ends
    /// and they can be received using `_receiveDrips`.
    /// @return amt The squeezed amount.
    /// @return nextSqueezed The next timestamp that can be squeezed.
    function _squeezeDrips(
        uint256 userId,
        uint256 assetId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) internal returns (uint128 amt, uint32 nextSqueezed) {
        (amt, nextSqueezed) = _squeezableDrips(
            userId,
            assetId,
            senderId,
            historyHash,
            dripsHistory
        );
        DripsState storage state = _dripsStorage().states[assetId][userId];
        state.nextSqueezed[senderId] = nextSqueezed;
        uint32 cycleStart = _currTimestamp() - (_currTimestamp() % _cycleSecs);
        _addDeltaRange(state, cycleStart, cycleStart + 1, -int256(amt * _AMT_PER_SEC_MULTIPLIER));
        emit SqueezedDrips(userId, assetId, senderId, amt, nextSqueezed);
    }

    /// @notice Calculate effects of calling `_squeezeDrips` with the given parameters.
    /// See its documentation for more details.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param assetId The used asset ID.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @param historyHash The sender's history hash which was valid right before `dripsHistory`.
    /// @param dripsHistory The sequence of the sender's drips configurations.
    /// @return amt The squeezed amount.
    /// @return nextSqueezed The next timestamp that can be squeezed.
    function _squeezableDrips(
        uint256 userId,
        uint256 assetId,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) internal view returns (uint128 amt, uint32 nextSqueezed) {
        bytes32 currHistoryHash = _dripsStorage().states[assetId][senderId].dripsHistoryHash;
        _verifyDripsHistory(historyHash, dripsHistory, currHistoryHash);
        uint32 squeezeStart = _nextSqueezedDrips(userId, assetId, senderId);
        uint32 squeezeEnd = _currTimestamp();
        nextSqueezed = squeezeStart;
        uint256 i = dripsHistory.length;
        while (i > 0 && squeezeStart < squeezeEnd) {
            DripsHistory memory drips = dripsHistory[--i];
            if (drips.receivers.length != 0) {
                amt += _squeezedAmt(userId, drips, squeezeStart, squeezeEnd);
                if (nextSqueezed < squeezeEnd) nextSqueezed = squeezeEnd;
            }
            squeezeEnd = drips.updateTime;
        }
    }

    /// @notice Verify a drips history and revert if it's invalid.
    /// @param historyHash The user's history hash which was valid right before `dripsHistory`.
    /// @param dripsHistory The sequence of the user's drips configurations.
    /// @param finalHistoryHash The history hash at the end of `dripsHistory`.
    function _verifyDripsHistory(
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory,
        bytes32 finalHistoryHash
    //) private pure {
    ) internal pure {
        for (uint256 i = 0; i < dripsHistory.length; i++) {
            DripsHistory memory drips = dripsHistory[i];
            bytes32 dripsHash = drips.dripsHash;
            if (drips.receivers.length != 0) {
                require(dripsHash == 0, "Drips history entry with hash and receivers");
                dripsHash = _hashDrips(drips.receivers);
            }
            historyHash = _hashDripsHistory(historyHash, dripsHash, drips.updateTime, drips.maxEnd);
        }
        require(historyHash == finalHistoryHash, "Invalid drips history");
    }

    /// @notice Calculate the amount squeezable by a user from a single drips history entry.
    /// @param userId The ID of the user to squeeze drips for.
    /// @param dripsHistory The squeezed history entry.
    /// @param squeezeStart The squeezed time range start.
    /// @param squeezeStart The squeezed time range end.
    /// @return squeezedAmt The squeezed amount.
    function _squeezedAmt(
        uint256 userId,
        DripsHistory memory dripsHistory,
        uint32 squeezeStart,
        uint32 squeezeEnd
    //) private view returns (uint128 squeezedAmt) {
    ) internal view returns (uint128 squeezedAmt) {
        DripsReceiver[] memory receivers = dripsHistory.receivers;
        // Binary search for the `idx` of the first `userId` receiver being
        uint256 idx = 0;
        uint256 idxCap = receivers.length;
        while (idx < idxCap) {
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
            (uint32 start, uint32 end) = _dripsRange(
                receiver,
                updateTime,
                maxEnd,
                squeezeStart,
                squeezeEnd
            );
            amt += _drippedAmt(receiver.config.amtPerSec(), start, end);
        }
        return uint128(amt);
    }

    /// @notice Get the next timestamp for which the user can squeeze drips from the sender.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param assetId The used asset ID.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @return nextSqueezed The next timestamp that can be squeezed.
    function _nextSqueezedDrips(
        uint256 userId,
        uint256 assetId,
        uint256 senderId
    ) internal view returns (uint32 nextSqueezed) {
        nextSqueezed = _dripsStorage().states[assetId][userId].nextSqueezed[senderId];
        uint32 cycleStart = _currTimestamp() - (_currTimestamp() % _cycleSecs);
        if (nextSqueezed < cycleStart) nextSqueezed = cycleStart;
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
        //internal
        public
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
        return (
            state.dripsHash,
            state.dripsHistoryHash,
            state.updateTime,
            state.balance,
            state.maxEnd
        );
    }

    /// @notice User drips balance at a given timestamp
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param receivers The current drips receivers list
    /// @param timestamp The timestamps for which balance should be calculated.
    /// It can't be lower than the timestamp of the last call to `setDrips`.
    /// If it's bigger than `block.timestamp`, then it's a prediction assuming
    /// that `setDrips` won't be called before `timestamp`.
    /// @return balance The user balance on `timestamp`
    function _balanceAt(
        uint256 userId,
        uint256 assetId,
        DripsReceiver[] memory receivers,
        uint32 timestamp
    ) internal view returns (uint128 balance) {
        DripsState storage state = _dripsStorage().states[assetId][userId];
        require(timestamp >= state.updateTime, "Timestamp before last drips update");
        require(_hashDrips(receivers) == state.dripsHash, "Invalid current drips list");
        return _balanceAt(state.balance, state.updateTime, state.maxEnd, receivers, timestamp);
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
    function _balanceAt(
        uint128 lastBalance,
        uint32 lastUpdate,
        uint32 maxEnd,
        DripsReceiver[] memory receivers,
        uint32 timestamp
    //) private view returns (uint128 balance) {
    ) internal view returns (uint128 balance) {
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
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change being applied.
    /// Positive when adding funds to the drips balance, negative to removing them.
    /// @param newReceivers The list of the drips receivers of the user to be set.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the user.
    /// @return realBalanceDelta The actually applied drips balance change.
    function _setDrips(
        uint256 userId,
        uint256 assetId,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) internal returns (uint128 newBalance, int128 realBalanceDelta) {
        DripsState storage state = _dripsStorage().states[assetId][userId];
        bytes32 currDripsHash = _hashDrips(currReceivers);
        require(currDripsHash == state.dripsHash, "Invalid current drips list");
        uint32 lastUpdate = state.updateTime;
        uint32 currMaxEnd = state.maxEnd;
        {
            uint128 lastBalance = state.balance;
            uint128 currBalance = _balanceAt(
                lastBalance,
                lastUpdate,
                currMaxEnd,
                currReceivers,  // <--- what if there is some other _hashDrips(currReceivers) == currDripsHash
                _currTimestamp()
            );
            int136 balance = int128(currBalance) + int136(balanceDelta);
            if (balance < 0) balance = 0;
            newBalance = uint128(uint136(balance));
            realBalanceDelta = int128(balance - int128(currBalance));
        }
        uint32 newMaxEnd = _calcMaxEnd(newBalance, newReceivers);
        _updateReceiverStates(
            _dripsStorage().states[assetId],
            currReceivers,
            lastUpdate,
            currMaxEnd,
            newReceivers,
            newMaxEnd
        );
        state.updateTime = _currTimestamp();
        state.maxEnd = newMaxEnd;
        state.balance = newBalance;
        bytes32 newDripsHash = _hashDrips(newReceivers);
        bytes32 dripsHistory = state.dripsHistoryHash;
        state.dripsHistoryHash = _hashDripsHistory(
            dripsHistory,
            newDripsHash,
            _currTimestamp(),
            newMaxEnd
        );
        emit DripsSet(userId, assetId, newDripsHash, dripsHistory, newBalance, newMaxEnd);
        if (newDripsHash != currDripsHash) {
            state.dripsHash = newDripsHash;
            for (uint256 i = 0; i < newReceivers.length; i++) {
                DripsReceiver memory receiver = newReceivers[i];
                emit DripsReceiverSeen(newDripsHash, receiver.userId, receiver.config);
            }
        }
    }

    /// @notice Calculates the maximum end time of drips.
    /// @param balance The balance when drips have started
    /// @param receivers The list of drips receivers.
    /// Must be sorted, deduplicated and without 0 amtPerSecs.
    /// @return maxEnd The maximum end time of drips
    function _calcMaxEnd(uint128 balance, DripsReceiver[] memory receivers)
        internal
        view
        virtual
        returns (uint32 maxEnd)
    {
        require(receivers.length <= _MAX_DRIPS_RECEIVERS, "Too many drips receivers");
        uint256[] memory configs = new uint256[](receivers.length);
        uint256 configsLen = 0;
        for (uint256 i = 0; i < receivers.length; i++) {
            DripsReceiver memory receiver = receivers[i];
            if (i > 0) require(_isOrdered(receivers[i - 1], receiver), "Receivers not sorted");
            configsLen = _addConfig(configs, configsLen, receiver);
        }
        return _calcMaxEnd(balance, configs, configsLen);
    }

    /// @notice Calculates the maximum end time of drips.
    /// @param balance The balance when drips have started
    /// @param configs The list of drips configurations
    /// @param configsLen The length of `configs`
    /// @return maxEnd The maximum end time of drips
    function _calcMaxEnd(
        uint128 balance,
        uint256[] memory configs,
        uint256 configsLen
    //) private view returns (uint32 maxEnd) {
    ) internal view returns (uint32 maxEnd) {
        unchecked {
            uint256 enoughEnd = _currTimestamp();
            if (configsLen == 0 || balance == 0) return uint32(enoughEnd);
            uint256 notEnoughEnd = type(uint32).max;
            if (_isBalanceEnough(balance, configs, configsLen, notEnoughEnd))
                return uint32(notEnoughEnd);
            while (true) {
                uint256 end = (enoughEnd + notEnoughEnd) / 2;
                if (end == enoughEnd) return uint32(end);
                if (_isBalanceEnough(balance, configs, configsLen, end)) {
                    enoughEnd = end;
                } else {
                    notEnoughEnd = end;
                }
            }
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
    //) private view returns (bool isEnough) {
    ) internal view returns (bool isEnough) {
        unchecked {
            uint256 spent = 0;
            for (uint256 i = 0; i < configsLen; i++) {
                (uint256 amtPerSec, uint256 start, uint256 end) = _getConfig(configs, i);
                if (maxEnd <= start) continue;
                if (end > maxEnd) end = maxEnd;
                spent += _drippedAmt(amtPerSec, start, end);
                if (spent > balance) return false;
            }
            return true;
        }
    }

    /// @notice Preprocess and add a drips receiver to the list of configurations.
    /// @param configs The list of drips configurations
    /// @param configsLen The length of `configs`
    /// @param receiver The added drips receivers.
    /// @return newConfigsLen The new length of `configs`
    function _addConfig(
        uint256[] memory configs,
        uint256 configsLen,
        DripsReceiver memory receiver
    //) private view returns (uint256 newConfigsLen) {
    ) internal view returns (uint256 newConfigsLen) {
        uint192 amtPerSec = receiver.config.amtPerSec();
        require(amtPerSec != 0, "Drips receiver amtPerSec is zero");
        (uint32 start, uint32 end) = _dripsRangeInFuture(
            receiver,
            _currTimestamp(),
            type(uint32).max
        );
        if (start == end) return configsLen;
        configs[configsLen] = (uint256(amtPerSec) << 64) | (uint256(start) << 32) | end;
        return configsLen + 1;
    }

    /// @notice Load a drips configuration from the list.
    /// @param configs The list of drips configurations
    /// @param idx The loaded configuration index. It must be smaller than the `configs` length.
    /// @return amtPerSec The amount per second being dripped.
    /// @return start The timestamp when dripping starts.
    /// @return end The maximum timestamp when dripping ends.
    function _getConfig(uint256[] memory configs, uint256 idx)
        //private
        internal
        pure
        returns (
            uint256 amtPerSec,
            uint256 start,
            uint256 end
        )
    {
        uint256 val;
        // solhint-disable-next-line no-inline-assembly
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
        if (receivers.length == 0) return bytes32(0);
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
    //) private {
    ) internal virtual {
        //return;
        //require(currReceivers.length == 1, "Attempt to reduce computation");
        //require(newReceivers.length == 1, "Attempt to reduce computation");
        uint256 currIdx = 0;
        uint256 newIdx = 0;
        while (true) {
            bool pickCurr = currIdx < currReceivers.length;
            DripsReceiver memory currRecv;
            if (pickCurr) currRecv = currReceivers[currIdx];

            bool pickNew = newIdx < newReceivers.length;
            DripsReceiver memory newRecv;
            if (pickNew) newRecv = newReceivers[newIdx];

            // if-1
            // Limit picking both curr and new to situations when they differ only by start/end time
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
                // if-2: same userId, same amtPerSec
                // Shift the existing drip to fulfil the new configuration

                // states[currRecv.userId].amtDeltas[_currTimestamp()].thisCycle = thisCycleMapping[currRecv.userId][_currTimestamp()];
                // states[currRecv.userId].amtDeltas[_currTimestamp()].nextCycle = nextCycleMapping[currRecv.userId][_currTimestamp()];
                // states[currRecv.userId].nextReceivableCycle = nextReceivableCycleMapping[currRecv.userId];

                DripsState storage state = states[currRecv.userId];
                (uint32 currStart, uint32 currEnd) = _dripsRangeInFuture(
                    currRecv,
                    lastUpdate,
                    currMaxEnd
                );
                (uint32 newStart, uint32 newEnd) = _dripsRangeInFuture(
                    newRecv,
                    _currTimestamp(),
                    newMaxEnd
                );
                {
                    int256 amtPerSec = int256(uint256(currRecv.config.amtPerSec()));
                    // Move the start and end times if updated
                    _addDeltaRange(state, currStart, newStart, -amtPerSec);
                    _addDeltaRange(state, currEnd, newEnd, amtPerSec);
                }
                // Ensure that the user receives the updated cycles
                uint32 currStartCycle = _cycleOf(currStart);
                uint32 newStartCycle = _cycleOf(newStart);
                if (currStartCycle > newStartCycle && state.nextReceivableCycle > newStartCycle) {
                    state.nextReceivableCycle = newStartCycle;
                }
                
            } else if (pickCurr) {
                // if-3
                // Remove an existing drip
                DripsState storage state = states[currRecv.userId];
                (uint32 start, uint32 end) = _dripsRangeInFuture(currRecv, lastUpdate, currMaxEnd);
                //require (end - start == 10);
                int256 amtPerSec = int256(uint256(currRecv.config.amtPerSec()));
                _addDeltaRange(state, start, end, -amtPerSec);
                //
            } else if (pickNew) {
                // if-4
                // Create a new drip
                DripsState storage state = states[newRecv.userId];
                (uint32 start, uint32 end) = _dripsRangeInFuture(
                    newRecv,
                    _currTimestamp(),
                    newMaxEnd
                );
                int256 amtPerSec = int256(uint256(newRecv.config.amtPerSec()));
                _addDeltaRange(state, start, end, amtPerSec);
                // Ensure that the user receives the updated cycles
                uint32 startCycle = _cycleOf(start);
                if (state.nextReceivableCycle == 0 || state.nextReceivableCycle > startCycle) {
                    state.nextReceivableCycle = startCycle;
                }
                //
                
            } else {
                break;
            }

            if (pickCurr) currIdx++;
            if (pickNew) newIdx++;
        }
    }

    /// @notice Calculates the time range in the future in which a receiver will be dripped to.
    /// @param receiver The drips receiver
    /// @param maxEnd The maximum end time of drips
    function _dripsRangeInFuture(
        DripsReceiver memory receiver,
        uint32 updateTime,
        uint32 maxEnd
    //) private view returns (uint32 start, uint32 end) {
    ) internal view returns (uint32 start, uint32 end) {
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
    //) private pure returns (uint32 start, uint32 end_) {
    ) internal pure returns (uint32 start, uint32 end_) {
        start = receiver.config.start();
        if (start == 0) start = updateTime;
        uint40 end = uint40(start) + receiver.config.duration();
        if (end == start || end > maxEnd) end = maxEnd;
        if (start < startCap) start = startCap;
        if (end > endCap) end = endCap;
        if (end < start) end = start;
        return (start, uint32(end));
    }

    /// @notice Adds funds received by a user in a given time range
    /// @param state The user state
    /// @param start The timestamp from which the delta takes effect
    /// @param end The timestamp until which the delta takes effect
    /// @param amtPerSec The dripping rate
    function _addDeltaRange(
        DripsState storage state,
        uint32 start,
        uint32 end,
        int256 amtPerSec
    //) private {
    ) internal {
        if (start == end) return;
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
    //) private {
    ) internal virtual {
        unchecked {
            
            // In order to set a delta on a specific timestamp it must be introduced in two cycles.
            // These formulas follow the logic from `_drippedAmt`, see it for more details.
            int256 amtPerSecMultiplier = int256(_AMT_PER_SEC_MULTIPLIER);
            int256 fullCycle = (int256(uint256(_cycleSecs)) * amtPerSec) / amtPerSecMultiplier;
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
    /// @param prev The next receiver
    function _isOrdered(DripsReceiver memory prev, DripsReceiver memory next)
        //private
        internal
        pure
        returns (bool)
    {
        if (prev.userId != next.userId) return prev.userId < next.userId;
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
    /// @param amt The dripped amount
    function _drippedAmt(
        uint256 amtPerSec,
        uint256 start,
        uint256 end
    //) private view returns (uint256 amt) {
    ) internal view returns (uint256 amt) {
        // This function is written in Yul because it can be called thousands of times
        // per transaction and it needs to be optimized as much as possible.
        // As of Solidity 0.8.13, rewriting it in unchecked Solidity triples its gas cost.
        uint256 cycleSecs = _cycleSecs;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let endedCycles := sub(div(end, cycleSecs), div(start, cycleSecs))
            let amtPerCycle := div(mul(cycleSecs, amtPerSec), _AMT_PER_SEC_MULTIPLIER)
            amt := mul(endedCycles, amtPerCycle)
            let amtEnd := div(mul(mod(end, cycleSecs), amtPerSec), _AMT_PER_SEC_MULTIPLIER)
            amt := add(amt, amtEnd)
            let amtStart := div(mul(mod(start, cycleSecs), amtPerSec), _AMT_PER_SEC_MULTIPLIER)
            amt := sub(amt, amtStart)
        }
    }

    /// @notice Calculates the cycle containing the given timestamp.
    /// @param timestamp The timestamp.
    /// @return cycle The cycle containing the timestamp.
    //function _cycleOf(uint32 timestamp) private view returns (uint32 cycle) {
    function _cycleOf(uint32 timestamp) internal view returns (uint32 cycle) {
        unchecked {
            return timestamp / _cycleSecs + 1;
            //return timestamp + 1;  // attempt to simplify
        }
    }

    /// @notice The current timestamp, casted to the library's internal representation.
    /// @return timestamp The current timestamp
    //function _currTimestamp() private view returns (uint32 timestamp) {
    function _currTimestamp() internal view returns (uint32 timestamp) {
        return uint32(block.timestamp);
    }

    /// @notice Returns the Drips storage.
    /// @return dripsStorage The storage.
    //function _dripsStorage() private view returns (DripsStorage storage dripsStorage) {
    function _dripsStorage() internal view returns (DripsStorage storage dripsStorage) {
        bytes32 slot = _dripsStorageSlot;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            dripsStorage.slot := slot
        }
    }
}
