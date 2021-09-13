// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

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
        uint32 weight;
        bool isAttached;
        // Unused. Hints the compiler that it has full control over the content
        // of the whole storage slot and allows it to optimize more aggressively.
        uint56 slotFiller;
    }

    address internal constant ADDR_ROOT = address(0);

    /// @notice Return the next non-zero receiver weight and its address.
    /// Removes all the items that have zero receiver weights found
    /// between the current and the next item from the list.
    /// Iterating over the whole list prunes all the zeroed items.
    /// @param prevReceiver The previously returned `receiver` or ADDR_ROOT to start iterating
    /// @param prevReceiverHint The previously returned `receiverHint`
    /// or ADDR_ROOT to start iterating
    /// @return receiver The receiver address, ADDR_ROOT if the end of the list was reached
    /// @return receiverHint A value passed as `prevReceiverHint` on the next call
    /// @return weight The receiver weight
    function nextWeightPruning(
        ReceiverWeights storage self,
        address prevReceiver,
        address prevReceiverHint
    )
        internal
        returns (
            address receiver,
            address receiverHint,
            uint32 weight
        )
    {
        if (prevReceiver == ADDR_ROOT) prevReceiverHint = self.data[ADDR_ROOT].next;
        receiver = prevReceiverHint;
        while (receiver != ADDR_ROOT) {
            weight = self.data[receiver].weight;
            receiverHint = self.data[receiver].next;
            if (weight != 0) break;
            delete self.data[receiver];
            receiver = receiverHint;
        }
        if (receiver != prevReceiverHint) self.data[prevReceiver].next = receiver;
    }

    /// @notice Return the next non-zero receiver weight and its address
    /// @param prevReceiver The previously returned `receiver` or ADDR_ROOT to start iterating
    /// @param prevReceiverHint The previously returned `receiverHint`
    /// or ADDR_ROOT to start iterating
    /// @return receiver The receiver address, ADDR_ROOT if the end of the list was reached
    /// @return receiverHint A value passed as `prevReceiverHint` on the next call
    /// @return weight The receiver weight
    function nextWeight(
        ReceiverWeights storage self,
        address prevReceiver,
        address prevReceiverHint
    )
        internal
        view
        returns (
            address receiver,
            address receiverHint,
            uint32 weight
        )
    {
        receiver = (prevReceiver == ADDR_ROOT) ? self.data[ADDR_ROOT].next : prevReceiverHint;
        while (receiver != ADDR_ROOT) {
            weight = self.data[receiver].weight;
            receiverHint = self.data[receiver].next;
            if (weight != 0) break;
            receiver = receiverHint;
        }
    }

    /// @notice Set weight for a specific receiver
    /// @param receiver The receiver to set weight
    /// @param weight The weight to set
    /// @return previousWeight The previously set weight, may be zero
    function setWeight(
        ReceiverWeights storage self,
        address receiver,
        uint32 weight
    ) internal returns (uint32 previousWeight) {
        require(receiver != ADDR_ROOT, "Invalid receiver address");
        // Ensure that the weight for a specific receiver is attached to the list
        if (!self.data[receiver].isAttached) {
            address rootNext = self.data[ADDR_ROOT].next;
            self.data[ADDR_ROOT].next = receiver;
            self.data[receiver].next = rootNext;
            self.data[receiver].isAttached = true;
        }
        previousWeight = self.data[receiver].weight;
        self.data[receiver].weight = weight;
    }
}
