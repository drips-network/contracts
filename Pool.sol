// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.2;

contract Pool {
    struct Sender {
        uint256 balance;
    }

    mapping(address => Sender) internal senders;

    function topUp() public payable {
        topUpSender(msg.sender);
    }

    function topUpSender(address sender) public payable {
        senders[sender].balance += msg.value;
    }

    function withdraw(uint256 value) public {
        withdrawTo(value, msg.sender);
    }

    function withdrawTo(uint256 value, address payable receiver) public {
        uint256 balance = senders[msg.sender].balance;
        require(value <= balance, "Not enough funds in account");
        balance -= value;
        senders[msg.sender].balance = balance;
        receiver.transfer(value);
    }
}

struct ReceiverWeight {
    address next;
    uint32 weight;
}

/// @notice Helper methods for receiver weights list.
/// The list works optimally if after applying a series of changes it's iterated over.
/// The list uses 1 word of storage per receiver with a non-zero weight.
library ReceiverWeightsImpl {
    address internal constant ADDR_ROOT = address(0);
    address internal constant ADDR_UNINITIALIZED = address(0);
    address internal constant ADDR_END = address(1);

    /// @notice Return the next non-zero receiver weight and its address.
    /// Removes all the zeroed items found between the current and the next receivers.
    /// Iterating over the whole list removes all the zeroed items.
    /// @param current The previously returned receiver address or zero to start iterating
    /// @return next The next receiver address
    /// @return weight The next receiver weight, zero if the end of the list was reached
    function nextWeight(
        mapping(address => ReceiverWeight) storage self,
        address current
    ) internal returns (address next, uint32 weight) {
        next = self[current].next;
        weight = 0;
        if (next != ADDR_END && next != ADDR_UNINITIALIZED) {
            weight = self[next].weight;
            // remove elements being zero
            if (weight == 0) {
                do {
                    address newNext = self[next].next;
                    // Somehow it's ~1500 gas cheaper than `delete self[next]`
                    self[next].next = ADDR_UNINITIALIZED;
                    next = newNext;
                    if (next == ADDR_END) break;
                    weight = self[next].weight;
                } while (weight == 0);
                // link the previous non-zero element with the next non-zero element
                // or ADDR_END if it became the last element on the list
                self[current].next = next;
            }
        }
    }

    /// @notice Get weight for a specific receiver
    /// @param receiver The receiver to get weight
    /// @return weight The receinver weight
    function getWeight(
        mapping(address => ReceiverWeight) storage self,
        address receiver
    ) internal view returns (uint32 weight) {
        weight = self[receiver].weight;
    }

    /// @notice Set weight for a specific receiver
    /// @param receiver The receiver to set weight
    /// @param weight The weight to set
    /// @return previousWeight The previously set weight, may be zero
    function setWeight(
        mapping(address => ReceiverWeight) storage self,
        address receiver,
        uint32 weight
    ) internal returns (uint32 previousWeight) {
        previousWeight = self[receiver].weight;
        self[receiver].weight = weight;
        // Item not attached to the list
        if (self[receiver].next == ADDR_UNINITIALIZED) {
            address rootNext = self[ADDR_ROOT].next;
            self[ADDR_ROOT].next = receiver;
            // The first item ever added to the list, root item not initialized yet
            if (rootNext == ADDR_UNINITIALIZED) rootNext = ADDR_END;
            self[receiver].next = rootNext;
        }
    }
}
