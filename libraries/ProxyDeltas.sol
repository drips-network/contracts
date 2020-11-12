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
    struct ProxyDeltaStored {
        uint64 next;
        int128 thisCycleDelta;
        // --- SLOT BOUNDARY
        int128 nextCycleDelta;
    }

    uint64 internal constant CYCLE_ROOT = 0;
    uint64 internal constant CYCLE_END = type(uint64).max;

    /// @notice Return the next non-zero, non-obsolete delta and its cycle.
    /// The order is undefined, it may or may not be chronological.
    /// Prunes all the fully zeroed or obsolete items found between the current and the next cycle.
    /// Iterating over the whole list prunes all the zeroed and obsolete items.
    /// @param current The previously returned cycle or CYCLE_ROOT to start iterating
    /// @param finishedCycle The last finished cycle.
    /// Entries describing cycles before `finishedCycle` are considered obsolete.
    /// @return next The next iterated cycle or CYCLE_ROOT if the end of the list was reached.
    /// @return thisCycleDelta The receiver delta applied for the `next` cycle.
    /// May be zero if `nextCycleDelta` is non-zero
    /// @return nextCycleDelta The receiver delta applied for the cycle after the `next` cycle.
    /// May be zero if `thisCycleDelta` is non-zero
    function nextDeltaPruning(
        ProxyDeltas storage self,
        uint64 current,
        uint64 finishedCycle
    )
        internal
        returns (
            uint64 next,
            int128 thisCycleDelta,
            int128 nextCycleDelta
        )
    {
        next = self.data[current].next;
        thisCycleDelta = 0;
        nextCycleDelta = 0;
        if (next != CYCLE_END && next != CYCLE_ROOT) {
            thisCycleDelta = self.data[next].thisCycleDelta;
            nextCycleDelta = self.data[next].nextCycleDelta;
            // remove elements being zero or obsolete
            if ((thisCycleDelta == 0 && nextCycleDelta == 0) || next < finishedCycle) {
                do {
                    uint64 newNext = self.data[next].next;
                    delete self.data[next];
                    next = newNext;
                    if (next == CYCLE_END) {
                        // Removing the last item on the list, clear the storage
                        if (current == CYCLE_ROOT) {
                            next = CYCLE_ROOT;
                        }
                        break;
                    }
                    thisCycleDelta = self.data[next].thisCycleDelta;
                    nextCycleDelta = self.data[next].nextCycleDelta;
                } while ((thisCycleDelta == 0 && nextCycleDelta == 0) || next < finishedCycle);
                // link the previous non-zero element with the next non-zero element
                // or ADDR_END if it became the last element on the list
                self.data[current].next = next;
            }
        }
        if (next == CYCLE_END) next = CYCLE_ROOT;
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
        require(cycle != CYCLE_ROOT && cycle != CYCLE_END, "Invalid cycle number");
        // Item not attached to the list
        if (self.data[cycle].next == CYCLE_ROOT) {
            uint64 rootNext = self.data[CYCLE_ROOT].next;
            self.data[CYCLE_ROOT].next = cycle;
            // The first item ever added to the list, root item not initialized yet
            if (rootNext == CYCLE_ROOT) rootNext = CYCLE_END;
            self.data[cycle].next = rootNext;
        }
        self.data[cycle].thisCycleDelta += thisCycleDeltaAdded;
        self.data[cycle].nextCycleDelta += nextCycleDeltaAdded;
    }
}
