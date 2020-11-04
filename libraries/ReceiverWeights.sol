// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.2;

/// @notice A list of receivers to their weights, iterable and with random access
struct ReceiverWeights {
    mapping(address => ReceiverWeightsImpl.ReceiverWeightStored) data;
}

/// @notice Helper methods for receiver weights list.
/// The list works optimally if after applying a series of changes it's iterated over.
/// The list uses 1 word of storage per receiver with a non-zero weight.
library ReceiverWeightsImpl {
    using ReceiverWeightsImpl for ReceiverWeights;

    struct ReceiverWeightStored {
        address next;
        uint32 weightReceiver;
        uint32 weightProxy;
    }

    address internal constant ADDR_ROOT = address(0);
    address internal constant ADDR_END = address(1);

    /// @notice Return the next non-zero receiver or proxy weight and its address.
    /// Removes all the items that have zero receiver and proxy weights found
    /// between the current and the next item from the list.
    /// Iterating over the whole list prunes all the zeroed items.
    /// @param current The previously returned receiver address or ADDR_ROOT to start iterating
    /// @return next The next receiver address, ADDR_ROOT if the end of the list was reached
    /// @return weightReceiver The next receiver weight, may be zero if `weightProxy` is non-zero
    /// @return weightProxy The next proxy weight, may be zero if `weightReceiver` is non-zero
    function nextWeightPruning(ReceiverWeights storage self, address current)
        internal
        returns (
            address next,
            uint32 weightReceiver,
            uint32 weightProxy
        )
    {
        next = self.data[current].next;
        weightReceiver = 0;
        weightProxy = 0;
        if (next != ADDR_END && next != ADDR_ROOT) {
            weightReceiver = self.data[next].weightReceiver;
            weightProxy = self.data[next].weightProxy;
            // remove elements being zero
            if (weightReceiver == 0 && weightProxy == 0) {
                do {
                    address newNext = self.data[next].next;
                    // Somehow it's ~1500 gas cheaper than `delete self[next]`
                    self.data[next].next = ADDR_ROOT;
                    next = newNext;
                    if (next == ADDR_END) {
                        // Removing the last item on the list, clear the storage
                        if (current == ADDR_ROOT) next = ADDR_ROOT;
                        break;
                    }
                    weightReceiver = self.data[next].weightReceiver;
                    weightProxy = self.data[next].weightProxy;
                } while (weightReceiver == 0 && weightProxy == 0);
                // link the previous non-zero element with the next non-zero element
                // or ADDR_END if it became the last element on the list
                self.data[current].next = next;
            }
        }
        if (next == ADDR_END) next = ADDR_ROOT;
    }

    /// @notice Return the next non-zero receiver or proxy weight and its address.
    /// Requires that the iterated part of the list is pruned with `nextWeightPruning`.
    /// @param current The previously returned receiver address or ADDR_ROOT to start iterating
    /// @return next The next receiver address, ADDR_ROOT if the end of the list was reached
    /// @return weightReceiver The next receiver weight, may be zero if `weightProxy` is non-zero
    /// @return weightProxy The next proxy weight, may be zero if `weightReceiver` is non-zero
    function nextWeight(ReceiverWeights storage self, address current)
        internal
        view
        returns (
            address next,
            uint32 weightReceiver,
            uint32 weightProxy
        )
    {
        next = self.data[current].next;
        if (next == ADDR_END) next = ADDR_ROOT;
        if (next != ADDR_ROOT) {
            weightReceiver = self.data[next].weightReceiver;
            weightProxy = self.data[next].weightProxy;
        }
    }

    /// @notice Set weight for a specific receiver
    /// @param receiver The receiver to set weight
    /// @param weight The weight to set
    /// @return previousWeight The previously set weight, may be zero
    function setReceiverWeight(
        ReceiverWeights storage self,
        address receiver,
        uint32 weight
    ) internal returns (uint32 previousWeight) {
        self.attachWeightToList(receiver);
        previousWeight = self.data[receiver].weightReceiver;
        self.data[receiver].weightReceiver = weight;
    }

    /// @notice Set weight for a specific proxy
    /// @param proxy The proxy to set weight
    /// @param weight The weight to set
    /// @return previousWeight The previously set weight, may be zero
    function setProxyWeight(
        ReceiverWeights storage self,
        address proxy,
        uint32 weight
    ) internal returns (uint32 previousWeight) {
        self.attachWeightToList(proxy);
        previousWeight = self.data[proxy].weightProxy;
        self.data[proxy].weightProxy = weight;
    }

    /// @notice Ensures that weight for a specific receiver is attached to the list
    /// @param receiver The receiver whose weight should be attached
    function attachWeightToList(ReceiverWeights storage self, address receiver) internal {
        require(receiver != ADDR_ROOT && receiver != ADDR_END, "Invalid receiver address");
        // Item not attached to the list
        if (self.data[receiver].next == ADDR_ROOT) {
            address rootNext = self.data[ADDR_ROOT].next;
            self.data[ADDR_ROOT].next = receiver;
            // The first item ever added to the list, root item not initialized yet
            if (rootNext == ADDR_ROOT) rootNext = ADDR_END;
            self.data[receiver].next = rootNext;
        }
    }
}
