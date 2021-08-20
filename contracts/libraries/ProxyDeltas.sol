// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

/// @notice A list of cycles and their deltas of amounts received by a proxy.
/// For each cycle there are stored two deltas, one for the cycle itself
/// and one for the cycle right after it.
/// It reduces storage access for some usage scenarios.
/// The cycle is described by its own entry and an entry for the previous cycle.
/// Iterable and with random access.
struct ProxyDeltas {
    mapping(uint64 => ProxyDeltasImpl.ProxyDeltaStored) data;
}

/// @notice Helper methods for proxy deltas list.
/// The list works optimally if after applying a series of changes it's iterated over.
/// The list uses 2 words of storage per stored cycle.
library ProxyDeltasImpl {
    using ProxyDeltasImpl for ProxyDeltas;

    struct ProxyDeltaStored {
        uint64 next;
        int128 thisCycleDelta;
        bool isAttached;
        // Unused. Hints the compiler that it has full control over the content
        // of the whole storage slot and allows it to optimize more aggressively.
        uint56 slotFiller1;
        // --- SLOT BOUNDARY
        int128 nextCycleDelta;
        // Unused. Hints the compiler that it has full control over the content
        // of the whole storage slot and allows it to optimize more aggressively.
        uint128 slotFiller2;
    }

    uint64 internal constant CYCLE_ROOT = 0;

    /// @notice Return the next non-zero, non-obsolete delta and its cycle.
    /// The order is undefined, it may or may not be chronological.
    /// Prunes all the fully zeroed or obsolete items found between the current and the next cycle.
    /// Iterating over the whole list prunes all the zeroed and obsolete items.
    /// @param prevCycle The previously returned `cycle` or CYCLE_ROOT to start iterating
    /// @param prevCycleHint The previously returned `cycleHint` or CYCLE_ROOT to start iterating
    /// @param finishedCycle The last finished cycle.
    /// Entries describing cycles before `finishedCycle` are considered obsolete.
    /// @return cycle The next iterated cycle or CYCLE_ROOT if the end of the list was reached.
    /// @return cycleHint A value passed as `prevCycleHint` on the next call
    /// @return thisCycleDelta The receiver delta applied for the `next` cycle.
    /// May be zero if `nextCycleDelta` is non-zero
    /// @return nextCycleDelta The receiver delta applied for the cycle after the `next` cycle.
    /// May be zero if `thisCycleDelta` is non-zero
    function nextDeltaPruning(
        ProxyDeltas storage self,
        uint64 prevCycle,
        uint64 prevCycleHint,
        uint64 finishedCycle
    )
        internal
        returns (
            uint64 cycle,
            uint64 cycleHint,
            int128 thisCycleDelta,
            int128 nextCycleDelta
        )
    {
        if (prevCycle == CYCLE_ROOT) prevCycleHint = self.data[CYCLE_ROOT].next;
        cycle = prevCycleHint;
        while (cycle != CYCLE_ROOT) {
            thisCycleDelta = self.data[cycle].thisCycleDelta;
            nextCycleDelta = self.data[cycle].nextCycleDelta;
            cycleHint = self.data[cycle].next;
            if ((thisCycleDelta != 0 || nextCycleDelta != 0) && cycle >= finishedCycle) break;
            delete self.data[cycle];
            cycle = cycleHint;
        }
        if (cycle != prevCycleHint) self.data[prevCycle].next = cycle;
    }

    /// @notice Add value to the delta for a specific cycle.
    /// @param cycle The cycle for which deltas are modified.
    /// @param thisCycleDeltaAdded The value added to the delta for `cycle`
    /// @param nextCycleDeltaAdded The value added to the delta for the cycle after `cycle`
    function addToDelta(
        ProxyDeltas storage self,
        uint64 cycle,
        int128 thisCycleDeltaAdded,
        int128 nextCycleDeltaAdded
    ) internal {
        self.attachToList(cycle);
        self.data[cycle].thisCycleDelta += thisCycleDeltaAdded;
        self.data[cycle].nextCycleDelta += nextCycleDeltaAdded;
    }

    /// @notice Ensures that the delta for a specific cycle is attached to the list
    /// @param cycle The cycle for which delta should be attached
    function attachToList(ProxyDeltas storage self, uint64 cycle) internal {
        require(cycle != CYCLE_ROOT && cycle != type(uint64).max, "Invalid cycle number");
        if (!self.data[cycle].isAttached) {
            uint64 rootNext = self.data[CYCLE_ROOT].next;
            self.data[CYCLE_ROOT].next = cycle;
            self.data[cycle].next = rootNext;
            self.data[cycle].isAttached = true;
        }
    }
}
