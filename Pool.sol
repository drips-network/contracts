// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Funding pool contract. Automatically sends funds to a configurable set of receivers.
///
/// The contract has 2 types of users: the senders and the receivers.
///
/// A sender has some funds and a set of addresses of receivers, to whom he wants to send funds.
/// In order to send there are 3 conditions, which must be fulfilled:
///
/// 1. There must be funds on his account in this contract.
///    They can be added with `topUp` and removed with `withdraw`.
/// 2. Total amount sent to the receivers on each block must be set to a non-zero value.
///    This is done with `setAmountPerBlock`.
/// 3. A set of receivers must be non-empty.
///    Receivers can be added, removed and updated with `setReceiver`.
///    Each receiver has a weight, which is used to calculate how the total sent amount is split.
///
/// Each of these functions can be called in any order and at any time, they have immediate effects.
/// When all of these conditions are fulfilled, on each block the configured amount is being sent.
/// It's extracted from the `withdraw`able balance and transferred to the receivers.
/// The process continues automatically until the sender's balance is empty.
///
/// The receiver has an account, from which he can `collect` funds sent by the senders.
/// The available amount is updated every `cycleBlocks` blocks,
/// so recently sent funds may not be `collect`able immediately.
/// `cycleBlocks` is a constant configured when the pool is deployed.
///
/// A single address can be used both as a sender and as a receiver.
/// It will have 2 balances in the contract, one with funds being sent and one with received,
/// but with no connection between them and no shared configuration.
/// In order to send received funds, they must be first `collect`ed and then `topUp`ped
/// if they are to be sent through the contract.
///
/// The concept of something happening periodically, e.g. every block or every `cycleBlocks` are
/// only high-level abstractions for the user, Ethereum isn't really capable of scheduling work.
/// The actual implementation emulates that behavior by calculating the results of the scheduled
/// events based on how many blocks have been mined and only when a user needs their outcomes.
///
/// The contract assumes that all amounts in the system can be stored in signed 128-bit integers.
/// It's guaranteed to be safe only when working with assets with supply lower than `2 ^ 127`.
abstract contract Pool {
    using ReceiverWeightsImpl for ReceiverWeights;

    /// @notice On every block `B`, which is a multiple of `cycleBlocks`, the receivers
    /// gain access to funds collected on all blocks from `B - cycleBlocks` to `B - 1`.
    uint64 public immutable cycleBlocks;
    /// @dev Block number at which all funding periods must be finished
    uint64 internal constant MAX_BLOCK_NUMBER = type(uint64).max - 2;
    /// @notice Maximum sum of all receiver weights of a single sender.
    /// Limits loss of per-block funding accuracy, they are always multiples of weights sum.
    uint32 public constant SENDER_WEIGHTS_SUM_MAX = 1000;
    /// @notice Maximum number of receivers of a single sender.
    /// Limits costs of changes in sender's configuration.
    uint32 public constant SENDER_WEIGHTS_COUNT_MAX = 100;

    struct Sender {
        // Block number at which the funding period has started
        uint64 startBlock;
        // The amount available when the funding period has started
        uint128 startBalance;
        // The total weight of all the receivers
        uint32 weightSum;
        // The number of the receivers
        uint32 weightCount;
        // --- SLOT BOUNDARY
        // The target amount sent on each block.
        // The actual amount is rounded down to the closes multiple of `weightSum`.
        uint128 amtPerBlock;
        // --- SLOT BOUNDARY
        // The receivers' addresses and their weights
        ReceiverWeights receiverWeights;
    }

    struct Receiver {
        // The next cycle to be collected
        uint64 nextCollectedCycle;
        // The amount of funds received for the last collected cycle.
        // It never is negative, it's a signed integer only for convenience of casting.
        int128 lastFundsPerCycle;
        // --- SLOT BOUNDARY
        // The changes of collected amounts on specific cycle.
        // The keys are cycles, each cycle becomes collectable on block `C * cycleBlocks`.
        mapping(uint64 => AmtDelta) amtDeltas;
    }

    struct AmtDelta {
        // Amount delta applied on this cycle
        int128 thisCycle;
        // Amount delta applied on the next cycle
        int128 nextCycle;
    }

    struct ReceiverWeight {
        address receiver;
        uint32 weight;
    }

    /// @dev Details about all the senders, the key is the owner's address
    mapping(address => Sender) internal senders;
    /// @dev Details about all the receivers, the key is the owner's address
    mapping(address => Receiver) internal receivers;

    /// @param _cycleBlocks The length of cycleBlocks to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of funds being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 _cycleBlocks) public {
        cycleBlocks = _cycleBlocks;
    }

    /// @notice Returns amount of received funds available for collection
    /// by the sender of the message
    /// @return collected The available amount
    function collectable() public view returns (uint128) {
        Receiver storage receiver = receivers[msg.sender];
        uint64 collectedCycle = receiver.nextCollectedCycle;
        if (collectedCycle == 0) return 0;
        uint64 currFinishedCycle = uint64(block.number) / cycleBlocks;
        if (collectedCycle > currFinishedCycle) return 0;
        int128 collected = 0;
        int128 lastFundsPerCycle = receiver.lastFundsPerCycle;
        for (; collectedCycle <= currFinishedCycle; collectedCycle++) {
            lastFundsPerCycle += receiver.amtDeltas[collectedCycle - 1].nextCycle;
            lastFundsPerCycle += receiver.amtDeltas[collectedCycle].thisCycle;
            collected += lastFundsPerCycle;
        }
        return uint128(collected);
    }

    /// @notice Collects all received funds available for collection
    /// by a sender of the message and sends them to that sender
    function collect() public {
        Receiver storage receiver = receivers[msg.sender];
        uint64 collectedCycle = receiver.nextCollectedCycle;
        if (collectedCycle == 0) return;
        uint64 currFinishedCycle = uint64(block.number) / cycleBlocks;
        if (collectedCycle > currFinishedCycle) return;
        int128 collected = 0;
        int128 lastFundsPerCycle = receiver.lastFundsPerCycle;
        for (; collectedCycle <= currFinishedCycle; collectedCycle++) {
            lastFundsPerCycle += receiver.amtDeltas[collectedCycle - 1].nextCycle;
            lastFundsPerCycle += receiver.amtDeltas[collectedCycle].thisCycle;
            collected += lastFundsPerCycle;
            delete receiver.amtDeltas[collectedCycle - 1];
        }
        receiver.lastFundsPerCycle = lastFundsPerCycle;
        receiver.nextCollectedCycle = collectedCycle;
        if (collected > 0) transferToSender(uint128(collected));
    }

    /// @notice Must be called when funds have been transferred into the pool contract
    /// in order to top up the message sender
    /// @param amount The topped up amount
    function onTopUp(uint128 amount) internal suspendPayments {
        senders[msg.sender].startBalance += amount;
    }

    /// @notice Returns amount of unsent funds available for withdrawal by the sender of the message
    /// @return balance The available balance
    function withdrawable() public view returns (uint128) {
        Sender storage sender = senders[msg.sender];
        // Hasn't been sending anything
        if (sender.weightSum == 0 || sender.amtPerBlock < sender.weightSum) {
            return sender.startBalance;
        }
        uint128 amtPerBlock = sender.amtPerBlock - (sender.amtPerBlock % sender.weightSum);
        uint192 alreadySent = (uint64(block.number) - sender.startBlock) * amtPerBlock;
        if (alreadySent > sender.startBalance) {
            return sender.startBalance % amtPerBlock;
        }
        return sender.startBalance - uint128(alreadySent);
    }

    /// @notice Withdraws unsent funds of the sender of the message and sends them to that sender
    /// @param amount The amount to be withdrawn, must not be higher than available funds
    function withdraw(uint128 amount) public {
        if (amount == 0) return;
        withdrawInternal(amount);
        transferToSender(amount);
    }

    /// @notice Withdraws unsent funds of the sender of the message
    /// @param amount The amount to be withdrawn, must not be higher than available funds
    function withdrawInternal(uint128 amount) internal suspendPayments {
        uint128 startBalance = senders[msg.sender].startBalance;
        require(amount <= startBalance, "Not enough funds in the sender account");
        senders[msg.sender].startBalance = startBalance - amount;
    }

    /// @notice Sets the target amount sent on every block from the sender of the message.
    /// On every block this amount is rounded down to the closest multiple of the sum of the weights
    /// of the receivers and split between all sender's receivers proportionally to their weights.
    /// Each receiver then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    /// @param amount The target per-block amount
    function setAmountPerBlock(uint128 amount) public suspendPayments {
        senders[msg.sender].amtPerBlock = amount;
    }

    /// @notice Gets the target amount sent on every block from the sender of the message.
    /// The actual amount sent on every block may differ from the target value.
    /// It's rounded down to the closest multiple of the sum of the weights of
    /// the sender's receivers and split between them proportionally to their weights.
    /// Each receiver then receives their part from the sender's balance.
    /// If zero, funding is stopped.
    /// @return amount The target per-block amount
    function getAmountPerBlock() public view returns (uint128 amount) {
        return senders[msg.sender].amtPerBlock;
    }

    /// @notice Sets the weight of a receiver of the sender of the message.
    /// The weight regulates the share of the amount being sent on every block in relation to
    /// other sender's receivers.
    /// Setting a non-zero weight for a new receiver adds it to the list of sender's receivers.
    /// Setting the zero weight for a receiver removes it from the list of sender's receivers.
    /// @param receiver The address of the receiver
    /// @param weight The weight of the receiver
    function setReceiver(address receiver, uint32 weight) public suspendPayments {
        Sender storage sender = senders[msg.sender];
        uint32 oldWeight = sender.receiverWeights.setReceiverWeight(receiver, weight);
        sender.weightSum -= oldWeight;
        sender.weightSum += weight;
        require(sender.weightSum <= SENDER_WEIGHTS_SUM_MAX, "Too much total receivers weight");
        if (weight != 0 && oldWeight == 0) {
            sender.weightCount++;
            require(sender.weightCount <= SENDER_WEIGHTS_COUNT_MAX, "Too many receivers");
        } else if (weight == 0 && oldWeight != 0) {
            sender.weightCount--;
        }
    }

    /// @notice Gets the receivers and their weights of the sender of the message.
    /// The weight regulates the share of the amount being sent on every block in relation to
    /// other sender's receivers.
    /// Only receivers with non-zero weights are returned.
    function getAllReceivers() public view returns (ReceiverWeight[] memory) {
        Sender storage sender = senders[msg.sender];
        ReceiverWeight[] memory allReceivers = new ReceiverWeight[](sender.weightCount);
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        for (uint256 i = 0; i < sender.weightCount; i++) {
            uint32 weight;
            (receiver, weight, ) = sender.receiverWeights.nextWeight(receiver);
            allReceivers[i] = ReceiverWeight(receiver, weight);
        }
        return allReceivers;
    }

    /// @notice Called when funds need to be transferred out of the pool to the message sender
    /// @param amount The transferred amount, never zero
    function transferToSender(uint128 amount) internal virtual;

    /// @notice Stops payments of `msg.sender` for the duration of the modified function.
    /// This removes and then restores any effects of the sender on all of its receivers' futures.
    /// It allows the function to safely modify any properties of the sender
    /// without having to updating the state of its receivers.
    modifier suspendPayments {
        stopPayments();
        _;
        startPayments();
    }

    /// @notice Stops the sender's payments on the current block
    function stopPayments() internal {
        uint64 blockNumber = uint64(block.number);
        Sender storage sender = senders[msg.sender];
        // Hasn't been sending anything
        if (sender.weightSum == 0 || sender.amtPerBlock < sender.weightSum) return;
        uint128 amtPerWeight = sender.amtPerBlock / sender.weightSum;
        uint128 amtPerBlock = amtPerWeight * sender.weightSum;
        uint256 endBlockUncapped = sender.startBlock + uint256(sender.startBalance / amtPerBlock);
        uint64 endBlock = endBlockUncapped > MAX_BLOCK_NUMBER
            ? MAX_BLOCK_NUMBER
            : uint64(endBlockUncapped);
        // The funding period has run out
        if (endBlock <= blockNumber) {
            sender.startBalance %= amtPerBlock;
            return;
        }
        sender.startBalance -= (blockNumber - sender.startBlock) * amtPerBlock;
        setDeltasFromNow(-int128(amtPerWeight), endBlock);
    }

    /// @notice Starts the sender's payments from the current block
    function startPayments() internal {
        uint64 blockNumber = uint64(block.number);
        Sender storage sender = senders[msg.sender];
        // Won't be sending anything
        if (sender.weightSum == 0 || sender.amtPerBlock < sender.weightSum) return;
        uint128 amtPerWeight = sender.amtPerBlock / sender.weightSum;
        uint128 amtPerBlock = amtPerWeight * sender.weightSum;
        // Won't be sending anything
        if (sender.startBalance < amtPerBlock) return;
        sender.startBlock = blockNumber;
        uint256 endBlockUncapped = blockNumber + uint256(sender.startBalance / amtPerBlock);
        uint64 endBlock = endBlockUncapped > MAX_BLOCK_NUMBER
            ? MAX_BLOCK_NUMBER
            : uint64(endBlockUncapped);
        setDeltasFromNow(int128(amtPerWeight), endBlock);
    }

    /// @notice Sets deltas to all sender's receivers from current block to endBlock
    /// proportionally to their weights
    /// @param amtPerWeightPerBlockDelta Amount of per-block delta applied per receiver weight
    /// @param blockEnd The block number from which the delta stops taking effect
    function setDeltasFromNow(int128 amtPerWeightPerBlockDelta, uint64 blockEnd) internal {
        uint64 blockNumber = uint64(block.number);
        Sender storage sender = senders[msg.sender];
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiverAddr = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 weight;
            (receiverAddr, weight, ) = sender.receiverWeights.nextWeightPruning(receiverAddr);
            if (receiverAddr == ReceiverWeightsImpl.ADDR_ROOT) break;
            Receiver storage receiver = receivers[receiverAddr];
            // The receiver was never used, initialize it
            if (amtPerWeightPerBlockDelta > 0 && receiver.nextCollectedCycle == 0)
                receiver.nextCollectedCycle = blockNumber / cycleBlocks + 1;
            int128 perBlockDelta = weight * amtPerWeightPerBlockDelta;
            // Set delta in a block range from now to `blockEnd`
            setSingleDelta(receiver.amtDeltas, blockNumber, perBlockDelta);
            setSingleDelta(receiver.amtDeltas, blockEnd, -perBlockDelta);
        }
    }

    /// @notice Sets delta of a single receiver on a given block number
    /// @param amtDeltas The deltas of the per-cycle receiving rate
    /// @param blockNumber The block number from which the delta takes effect
    /// @param perBlockDelta Change of the per-block receiving rate
    function setSingleDelta(
        mapping(uint64 => AmtDelta) storage amtDeltas,
        uint64 blockNumber,
        int128 perBlockDelta
    ) internal {
        // In order to set a delta on a specific block it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint64 thisCycle = blockNumber / cycleBlocks + 1;
        uint64 nextCycleBlocks = blockNumber % cycleBlocks;
        uint64 thisCycleBlocks = cycleBlocks - nextCycleBlocks;
        amtDeltas[thisCycle].thisCycle += thisCycleBlocks * perBlockDelta;
        amtDeltas[thisCycle].nextCycle += nextCycleBlocks * perBlockDelta;
    }
}

/// @notice Funding pool contract for Ether.
/// See the base `Pool` contract docs for more details.
contract EthPool is Pool {
    /// @param cycleBlocks The length of cycleBlocks to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of Ether being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 cycleBlocks) public Pool(cycleBlocks) {
        return;
    }

    /// @notice Tops up the sender balance of a sender of the message with the amount in the message
    function topUp() public payable {
        if (msg.value > 0) onTopUp(uint128(msg.value));
    }

    function transferToSender(uint128 amount) internal override {
        msg.sender.transfer(amount);
    }
}

/// @notice Funding pool contract for any ERC-20 token.
/// See the base `Pool` contract docs for more details.
contract Erc20Pool is Pool {
    /// @notice The address of the ERC-20 contract which tokens the pool works with
    IERC20 public immutable erc20;

    /// @param cycleBlocks The length of cycleBlocks to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of tokens being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    /// @param _erc20 The address of an ERC-20 contract which tokens the pool will work with.
    /// To guarantee safety the supply of the tokens must be lower than `2 ^ 127`.
    constructor(uint64 cycleBlocks, IERC20 _erc20) public Pool(cycleBlocks) {
        erc20 = _erc20;
    }

    /// @notice Tops up the sender balance of a sender of the message.
    /// The sender must first grant the contract a sufficient allowance.
    /// @param amount The amount to top up with
    function topUp(uint128 amount) public {
        if (amount == 0) return;
        erc20.transferFrom(msg.sender, address(this), amount);
        onTopUp(amount);
    }

    function transferToSender(uint128 amount) internal override {
        erc20.transfer(msg.sender, amount);
    }
}

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
    address internal constant ADDR_UNINITIALIZED = address(0);
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
        if (next != ADDR_END && next != ADDR_UNINITIALIZED) {
            weightReceiver = self.data[next].weightReceiver;
            weightProxy = self.data[next].weightProxy;
            // remove elements being zero
            if (weightReceiver == 0 && weightProxy == 0) {
                do {
                    address newNext = self.data[next].next;
                    // Somehow it's ~1500 gas cheaper than `delete self[next]`
                    self.data[next].next = ADDR_UNINITIALIZED;
                    next = newNext;
                    if (next == ADDR_END) {
                        // Removing the last item on the list, clear the storage
                        if (current == ADDR_ROOT) next = ADDR_UNINITIALIZED;
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
        if (self.data[receiver].next == ADDR_UNINITIALIZED) {
            address rootNext = self.data[ADDR_ROOT].next;
            self.data[ADDR_ROOT].next = receiver;
            // The first item ever added to the list, root item not initialized yet
            if (rootNext == ADDR_UNINITIALIZED) rootNext = ADDR_END;
            self.data[receiver].next = rootNext;
        }
    }
}
