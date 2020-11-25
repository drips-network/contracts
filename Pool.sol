// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/ProxyDeltas.sol";
import "./libraries/ReceiverWeights.sol";

/// @notice Funding pool contract. Automatically sends funds to a configurable set of receivers.
///
/// The contract has 3 types of users: the senders, the receivers and the proxies.
///
/// A sender has some funds and a set of addresses of receivers, to whom he wants to send funds
/// and proxies, who he trusts with choice of more receivers.
/// In order to send there are 3 conditions, which must be fulfilled:
///
/// 1. There must be funds on his account in this contract.
///    They can be added with `topUp` and removed with `withdraw`.
/// 2. Total amount sent to the receivers on each block must be set to a non-zero value.
///    This is done with `setAmountPerBlock`.
/// 3. A set of receivers and proxies must be non-empty.
///    Receivers can be added, removed and updated with `setReceiver`, proxies with `setProxy`.
///    Each receiver or proxy has a weight,
///    which is used to calculate how the total sent amount is split.
///
/// Each of these functions can be called in any order and at any time, they have immediate effects.
/// When all of these conditions are fulfilled, on each block the configured amount is being sent.
/// It's extracted from the `withdraw`able balance and transferred to the receivers.
/// The process continues automatically until the sender's balance is empty.
///
/// A receiver has an account, from which he can `collect` funds sent by the senders.
/// The available amount is updated every `cycleBlocks` blocks,
/// so recently sent funds may not be `collect`able immediately.
/// `cycleBlocks` is a constant configured when the pool is deployed.
///
/// A proxy has a list of receivers with attached weights, just like a sender.
/// When a sender is sending some funds to a proxy,
/// they are split and passed to the proxy's receivers according to their weights.
/// The proxy can change its list of receivers at any time with immediate effect,
/// but as if it was done on the beginning of the current cycle.
///
/// A single address can be used as a sender, a receiver and a proxy, even at the same time.
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
    using ProxyDeltasImpl for ProxyDeltas;

    /// @notice On every block `B`, which is a multiple of `cycleBlocks`, the receivers
    /// gain access to funds collected on all blocks from `B - cycleBlocks` to `B - 1`.
    uint64 public immutable cycleBlocks;
    /// @dev Block number at which all funding periods must be finished
    uint64 internal constant MAX_BLOCK_NUMBER = type(uint64).max - 2;
    /// @notice Maximum sum of all receiver weights of a single sender.
    /// Limits loss of per-block funding accuracy, they are always multiples of weights sum.
    uint32 public constant SENDER_WEIGHTS_SUM_MAX = 10000;
    /// @notice Maximum number of receivers of a single sender.
    /// Limits costs of changes in sender's configuration.
    uint32 public constant SENDER_WEIGHTS_COUNT_MAX = 100;
    /// @notice The sum of all receiver weights of a single proxy.
    /// It must remain constant throughout the whole life of a proxy.
    /// A sender's weight of a proxy must always be a multiple of this value.
    /// Limits loss of per-block funding accuracy.
    uint32 public constant PROXY_WEIGHTS_SUM = 100;
    /// @notice Maximum number of receivers of a single proxy.
    /// Whenever a proxy is added to a sender, this number is added to its `weightCount`.
    /// Limits costs of changes in sender's or proxy's configuration.
    uint32 public constant PROXY_WEIGHTS_COUNT_MAX = 10;
    /// @notice The amount passed to `withdraw` to withdraw all the funds
    uint128 public constant WITHDRAW_ALL = type(uint128).max;

    struct Sender {
        // Block number at which the funding period has started
        uint64 startBlock;
        // The amount available when the funding period has started
        uint128 startBalance;
        // The total weight of all the receivers, must never be larger than `SENDER_WEIGHTS_SUM_MAX`
        uint32 weightSum;
        // The number of the receivers, must never be larger than `SENDER_WEIGHTS_COUNT_MAX`.
        // A single address may serve as both a receiver and a proxy.
        // Each proxy is counted as `PROXY_WEIGHTS_COUNT_MAX`,
        // because that's how many actual receivers it may represent.
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

    struct Proxy {
        // The receivers' addresses and their weights
        ReceiverWeights receiverWeights;
        // --- SLOT BOUNDARY
        // The changes of amount per weight received from all senders on a specific cycle.
        ProxyDeltas amtPerWeightDeltas;
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

    struct ReceiverProxyWeight {
        address receiver;
        uint32 receiverWeight;
        uint32 proxyWeight;
    }

    /// @dev Details about all the senders, the key is the owner's address
    mapping(address => Sender) internal senders;
    /// @dev Details about all the proxies, the key is the owner's address
    mapping(address => Proxy) internal proxies;
    /// @dev Details about all the receivers, the key is the owner's address
    mapping(address => Receiver) internal receivers;

    /// @param _cycleBlocks The length of cycleBlocks to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of funds being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 _cycleBlocks) {
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
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    function withdraw(uint128 amount) public {
        if (amount == 0) return;
        uint128 withdrawn = withdrawInternal(amount);
        transferToSender(withdrawn);
    }

    /// @notice Withdraws unsent funds of the sender of the message
    /// @param amount The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @return withdrawn The actually withdrawn amount.
    /// Equal to `amount` unless `WITHDRAW_ALL` is used.
    function withdrawInternal(uint128 amount) internal suspendPayments returns (uint128 withdrawn) {
        uint128 startBalance = senders[msg.sender].startBalance;
        if (amount == WITHDRAW_ALL) amount = startBalance;
        require(amount <= startBalance, "Not enough funds in the sender account");
        senders[msg.sender].startBalance = startBalance - amount;
        return amount;
    }

    /// @notice Sets the target amount sent on every block from the sender of the message.
    /// On every block this amount is rounded down to the closest multiple of the sum of the weights
    /// of the receivers and proxies and split between them proportionally to their weights.
    /// Each receiver and proxy then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    /// @param amount The target per-block amount
    function setAmountPerBlock(uint128 amount) public suspendPayments {
        senders[msg.sender].amtPerBlock = amount;
    }

    /// @notice Gets the target amount sent on every block from the sender of the message.
    /// The actual amount sent on every block may differ from the target value.
    /// It's rounded down to the closest multiple of the sum of the weights of
    /// the sender's receivers and proxies and split between them proportionally to their weights.
    /// Each receiver and proxy then receives their part from the sender's balance.
    /// If zero, funding is stopped.
    /// @return amount The target per-block amount
    function getAmountPerBlock() public view returns (uint128 amount) {
        return senders[msg.sender].amtPerBlock;
    }

    /// @notice Sets the weight of the provided receivers and proxies of the sender of the message.
    /// The weight regulates the share of the amount sent on every block
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new receiver or
    /// a new proxy adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a receiver or a proxy
    /// removes it from the list of the sender's receivers.
    /// @param updatedReceivers The list of the updated receivers and their new weights
    /// @param updatedProxies The list of the updated proxies and their new weights
    function setReceivers(
        ReceiverWeight[] calldata updatedReceivers,
        ReceiverWeight[] calldata updatedProxies
    ) public suspendPayments {
        for (uint256 i = 0; i < updatedReceivers.length; i++) {
            setReceiverInternal(updatedReceivers[i].receiver, updatedReceivers[i].weight);
        }
        for (uint256 i = 0; i < updatedProxies.length; i++) {
            setProxyInternal(updatedProxies[i].receiver, updatedProxies[i].weight);
        }
    }

    /// @notice Sets the weight of the provided receiver of the sender of the message.
    /// The weight regulates the share of the amount sent on every block
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new receiver adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a receiver removes it from the list of the sender's receivers.
    /// @param receiver The address of the receiver
    /// @param weight The weight of the receiver
    function setReceiver(address receiver, uint32 weight) public suspendPayments {
        setReceiverInternal(receiver, weight);
    }

    /// @notice Sets the weight of the provided proxy of the sender of the message.
    /// The weight regulates the share of the amount sent on every block
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new proxy adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a proxy removes it from the list of the sender's receivers.
    /// @param proxy The address of the proxy
    /// @param weight The weight of the proxy, must be a multiple of `PROXY_WEIGHTS_SUM`
    function setProxy(address proxy, uint32 weight) public suspendPayments {
        setProxyInternal(proxy, weight);
    }

    /// @notice Sets the weight of the provided receiver of the sender of the message.
    /// The weight regulates the share of the amount sent on every block
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new receiver adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a receiver removes it from the list of the sender's receivers.
    /// @param receiver The address of the receiver
    /// @param weight The weight of the receiver
    function setReceiverInternal(address receiver, uint32 weight) internal {
        Sender storage sender = senders[msg.sender];
        uint64 senderWeightSum = sender.weightSum;
        uint32 oldWeight = sender.receiverWeights.setReceiverWeight(receiver, weight);
        senderWeightSum -= oldWeight;
        senderWeightSum += weight;
        require(senderWeightSum <= SENDER_WEIGHTS_SUM_MAX, "Too much total receivers weight");
        sender.weightSum = uint32(senderWeightSum);
        if (weight != 0 && oldWeight == 0) {
            sender.weightCount++;
            require(sender.weightCount <= SENDER_WEIGHTS_COUNT_MAX, "Too many receivers");
        } else if (weight == 0 && oldWeight != 0) {
            sender.weightCount--;
        }
    }

    /// @notice Sets the weight of the provided proxy of the sender of the message.
    /// The weight regulates the share of the amount sent on every block
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new proxy adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a proxy removes it from the list of the sender's receivers.
    /// @param proxy The address of the proxy
    /// @param weight The weight of the proxy, must be a multiple of `PROXY_WEIGHTS_SUM`
    function setProxyInternal(address proxy, uint32 weight) internal {
        require(proxies[proxy].receiverWeights.isZeroed() == false, "Proxy doesn't exist");
        require(
            weight % PROXY_WEIGHTS_SUM == 0,
            "Proxy weight not a multiple of PROXY_WEIGHTS_SUM"
        );
        Sender storage sender = senders[msg.sender];
        uint64 senderWeightSum = sender.weightSum;
        uint32 oldWeight = sender.receiverWeights.setProxyWeight(proxy, weight);
        senderWeightSum -= oldWeight;
        senderWeightSum += weight;
        require(senderWeightSum <= SENDER_WEIGHTS_SUM_MAX, "Too much total receivers weight");
        sender.weightSum = uint32(senderWeightSum);
        if (weight != 0 && oldWeight == 0) {
            sender.weightCount += PROXY_WEIGHTS_COUNT_MAX;
            require(sender.weightCount <= SENDER_WEIGHTS_COUNT_MAX, "Too many receivers");
        } else if (weight == 0 && oldWeight != 0) {
            sender.weightCount -= PROXY_WEIGHTS_COUNT_MAX;
        }
    }

    /// @notice Gets the receivers and the proxies to whom the sender of the message sends funds.
    /// Each entry contains weights, which regulate the share of the amount
    /// being sent on every block in relation to other sender's receivers and proxies.
    /// @return weights The list of receiver and proxy addresses and their weights.
    /// Each entry has at least one non-zero weight.
    function getAllReceivers() public view returns (ReceiverProxyWeight[] memory weights) {
        Sender storage sender = senders[msg.sender];
        ReceiverProxyWeight[] memory weightsSparse = new ReceiverProxyWeight[](sender.weightCount);
        uint32 weightsCount = 0;
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 receiverWeight;
            uint32 proxyWeight;
            (receiver, receiverWeight, proxyWeight) = sender.receiverWeights.nextWeight(receiver);
            if (receiver == ReceiverWeightsImpl.ADDR_ROOT) break;
            weightsSparse[weightsCount++] = ReceiverProxyWeight(
                receiver,
                receiverWeight,
                proxyWeight
            );
        }
        // Return only set items
        weights = new ReceiverProxyWeight[](weightsCount);
        for (uint32 i = 0; i < weightsCount; i++) {
            weights[i] = weightsSparse[i];
        }
    }

    /// @notice Sets the weight of a proxy owned by the sender of the message.
    /// The weight regulates the share of the amount being sent on every block in relation to
    /// other proxy's receivers.
    /// The amount sent to a proxy will be split and passed further to the receivers of the proxy.
    /// Setting weights for a proxy for the first time creates it, only then senders can use it.
    /// From inception the sum of proxy's receivers' weights must be equal to `PROXY_WEIGHTS_SUM`.
    /// @param weights The updated weights of the proxy receivers.
    /// Setting a non-zero weight for a new proxy adds it to the list of proxy's receivers.
    /// Setting the zero weight for a proxy removes it from the list of proxy's receivers.
    /// Omitting a receiver from the list leaves it unchanged.
    function setProxyWeights(ReceiverWeight[] calldata weights) public suspendProxy {
        Proxy storage proxy = proxies[msg.sender];
        uint64 weightSum = (proxy.receiverWeights.isZeroed()) ? 0 : PROXY_WEIGHTS_SUM;
        for (uint256 i = 0; i < weights.length; i++) {
            address receiverAddr = weights[i].receiver;
            uint32 weight = weights[i].weight;
            uint32 oldWeight = proxy.receiverWeights.setReceiverWeight(receiverAddr, weight);
            weightSum -= oldWeight;
            weightSum += weight;
            // Initialize the receiver
            if (weight != 0 && oldWeight == 0 && receivers[receiverAddr].nextCollectedCycle == 0) {
                receivers[receiverAddr].nextCollectedCycle = uint64(block.number) / cycleBlocks + 1;
            }
        }
        require(weightSum == PROXY_WEIGHTS_SUM, "Proxy doesn't have the constant weight sum");
    }

    /// @notice Gets the receivers to whom the proxy of the sender of the message passes funds.
    /// Each entry contains weights, which regulate the share of the amount
    /// being sent on every block in relation to other proxy's receivers.
    /// @return weights The list of receiver addresses and their non-zero weights.
    function getProxyWeights() public view returns (ReceiverWeight[] memory weights) {
        Proxy storage proxy = proxies[msg.sender];
        ReceiverWeight[] memory weightsSparse = new ReceiverWeight[](PROXY_WEIGHTS_COUNT_MAX);
        uint32 weightsCount = 0;
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 weight;
            (receiver, weight, ) = proxy.receiverWeights.nextWeight(receiver);
            if (receiver == ReceiverWeightsImpl.ADDR_ROOT) break;
            weightsSparse[weightsCount++] = ReceiverWeight(receiver, weight);
        }
        // Return only set items
        weights = new ReceiverWeight[](weightsCount);
        for (uint32 i = 0; i < weightsCount; i++) {
            weights[i] = weightsSparse[i];
        }
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
        uint64 endBlock =
            endBlockUncapped > MAX_BLOCK_NUMBER ? MAX_BLOCK_NUMBER : uint64(endBlockUncapped);
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
        uint64 endBlock =
            endBlockUncapped > MAX_BLOCK_NUMBER ? MAX_BLOCK_NUMBER : uint64(endBlockUncapped);
        setDeltasFromNow(int128(amtPerWeight), endBlock);
    }

    /// @notice Sets deltas to all sender's receivers and proxies from current block to `blockEnd`
    /// proportionally to their weights
    /// Effects are applied as if the change was made on the beginning of the current cycle.
    /// @param amtPerWeightPerBlockDelta Amount of per-block delta applied per receiver weight
    /// @param blockEnd The block number from which the delta stops taking effect
    function setDeltasFromNow(int128 amtPerWeightPerBlockDelta, uint64 blockEnd) internal {
        Sender storage sender = senders[msg.sender];
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiverAddr = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 receiverWeight;
            uint32 proxyWeight;
            (receiverAddr, receiverWeight, proxyWeight) = sender.receiverWeights.nextWeightPruning(
                receiverAddr
            );
            if (receiverAddr == ReceiverWeightsImpl.ADDR_ROOT) break;
            if (receiverWeight != 0) {
                int128 perBlockDelta = receiverWeight * amtPerWeightPerBlockDelta;
                setReceiverDeltaFromNow(receiverAddr, perBlockDelta, blockEnd);
            }
            if (proxyWeight != 0) {
                int128 perBlockDelta = proxyWeight * amtPerWeightPerBlockDelta;
                updateProxyReceiversDeltaFromNow(receiverAddr, perBlockDelta, blockEnd);
            }
        }
    }

    /// @notice Updates deltas of a proxy from current block to `blockEnd`.
    /// It updates deltas of both the proxy itself and all of its receivers.
    /// Effects are applied as if the change was made on the beginning of the current cycle.
    /// @param proxyAddr The address of the proxy
    /// @param perBlockDelta Change of the per-block receiving rate of the proxy
    /// @param blockEnd The block number from which the delta stops taking effect
    function updateProxyReceiversDeltaFromNow(
        address proxyAddr,
        int128 perBlockDelta,
        uint64 blockEnd
    ) internal {
        uint64 blockNumber = uint64(block.number);
        int128 perBlockPerProxyWeightDelta = perBlockDelta / PROXY_WEIGHTS_SUM;
        Proxy storage proxy = proxies[proxyAddr];
        updateSingleProxyDelta(proxy.amtPerWeightDeltas, blockNumber, perBlockPerProxyWeightDelta);
        updateSingleProxyDelta(proxy.amtPerWeightDeltas, blockEnd, -perBlockPerProxyWeightDelta);
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 weight;
            (receiver, weight, ) = proxy.receiverWeights.nextWeightPruning(receiver);
            if (receiver == ReceiverWeightsImpl.ADDR_ROOT) break;
            setReceiverDeltaFromNow(receiver, perBlockPerProxyWeightDelta * weight, blockEnd);
        }
    }

    /// @notice Updates the delta of a single proxy on a given block number
    /// @param proxyDeltas The deltas of the per-cycle receiving rate
    /// @param blockNumber The block number from which the delta takes effect
    /// @param perBlockDelta Change of the per-block receiving rate
    function updateSingleProxyDelta(
        ProxyDeltas storage proxyDeltas,
        uint64 blockNumber,
        int128 perBlockDelta
    ) internal {
        // In order to set a delta on a specific block it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint64 thisCycle = blockNumber / cycleBlocks + 1;
        uint64 nextCycleBlocks = blockNumber % cycleBlocks;
        uint64 thisCycleBlocks = cycleBlocks - nextCycleBlocks;
        proxyDeltas.addToDelta(
            thisCycle,
            thisCycleBlocks * perBlockDelta,
            nextCycleBlocks * perBlockDelta
        );
    }

    /// @notice Sets deltas to a receiver from current block to `blockEnd`
    /// @param receiverAddr The address of the receiver
    /// @param perBlockDelta Change of the per-block receiving rate
    /// @param blockEnd The block number from which the delta stops taking effect
    function setReceiverDeltaFromNow(
        address receiverAddr,
        int128 perBlockDelta,
        uint64 blockEnd
    ) internal {
        uint64 blockNumber = uint64(block.number);
        Receiver storage receiver = receivers[receiverAddr];
        // The receiver was never used, initialize it.
        // The first usage of a receiver is always setting a positive delta to start sending.
        // If the delta is negative, the receiver must've been used before and now is being cleared.
        if (perBlockDelta > 0 && receiver.nextCollectedCycle == 0)
            receiver.nextCollectedCycle = blockNumber / cycleBlocks + 1;
        // Set delta in a block range from now to `blockEnd`
        setSingleDelta(receiver.amtDeltas, blockNumber, perBlockDelta);
        setSingleDelta(receiver.amtDeltas, blockEnd, -perBlockDelta);
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

    /// @notice Stops proxy of `msg.sender` for the duration of the modified function.
    /// This removes and then restores any effects of the proxy on all of its receivers' futures.
    /// It allows the function to safely modify any properties of the proxy
    /// without having to updating the state of its receivers.
    modifier suspendProxy {
        applyProxyDeltasOnReceivers(-1);
        _;
        applyProxyDeltasOnReceivers(1);
    }

    /// @notice Applies the effects of the proxy on all of its receivers' futures.
    /// Effects are applied as if the change was made on the beginning of the current cycle.
    /// @param multiplier The multiplier of the deltas applied on the receivers.
    /// `-1` to remove the effects of the proxy, `1` to reapply after removal.
    function applyProxyDeltasOnReceivers(int8 multiplier) internal {
        uint64 blockNumber = uint64(block.number);
        Proxy storage proxy = proxies[msg.sender];
        uint32 receiversCount = 0;
        // Create an in-memory copy of the receivers list to reduce storage access
        ReceiverWeight[] memory receiversList = new ReceiverWeight[](PROXY_WEIGHTS_COUNT_MAX);
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiverAddr = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 weight;
            (receiverAddr, weight, ) = proxy.receiverWeights.nextWeightPruning(receiverAddr);
            if (receiverAddr == ReceiverWeightsImpl.ADDR_ROOT) break;
            require(receiversCount < PROXY_WEIGHTS_COUNT_MAX, "Too many proxy receivers");
            receiversList[receiversCount++] = ReceiverWeight(receiverAddr, weight);
        }
        // The proxy doesn't exist
        if (receiversCount == 0) return;

        // Iterating over deltas, see `ProxyDeltas` for details
        uint64 cycle = ProxyDeltasImpl.CYCLE_ROOT;
        uint64 finishedCycle = blockNumber / cycleBlocks;
        uint64 currCycle = finishedCycle + 1;
        // The sum of all the future changes to the per-block amount the proxy receives.
        // This is also the per-block amount the proxy receives per weight in the current cycle,
        // but with its sign inverted.
        // Thus if `multiplier` is `1`, then this value is negative and if `-1`, it's positive.
        int128 totalDelta = 0;
        while (true) {
            int128 thisCycleDelta;
            int128 nextCycleDelta;
            (cycle, thisCycleDelta, nextCycleDelta) = proxy.amtPerWeightDeltas.nextDeltaPruning(
                cycle,
                finishedCycle
            );
            if (cycle == ProxyDeltasImpl.CYCLE_ROOT) break;
            // `thisCycleDelta` from the previously finished cycle is irrelevant
            if (cycle == finishedCycle) thisCycleDelta = 0;
            thisCycleDelta *= multiplier;
            nextCycleDelta *= multiplier;
            totalDelta += thisCycleDelta + nextCycleDelta;
            for (uint32 i = 0; i < receiversCount; i++) {
                Receiver storage receiver = receivers[receiversList[i].receiver];
                uint32 weight = receiversList[i].weight;
                receiver.amtDeltas[cycle].thisCycle += weight * thisCycleDelta;
                receiver.amtDeltas[cycle].nextCycle += weight * nextCycleDelta;
            }
        }
        // Set the delta for the current cycle, which balances all the applied deltas
        if (totalDelta != 0) {
            for (uint32 i = 0; i < receiversCount; i++) {
                Receiver storage receiver = receivers[receiversList[i].receiver];
                receiver.amtDeltas[currCycle].thisCycle -= totalDelta * receiversList[i].weight;
            }
        }
    }
}

/// @notice Funding pool contract for Ether.
/// See the base `Pool` contract docs for more details.
contract EthPool is Pool {
    /// @param cycleBlocks The length of cycleBlocks to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of Ether being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 cycleBlocks) Pool(cycleBlocks) {
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
    constructor(uint64 cycleBlocks, IERC20 _erc20) Pool(cycleBlocks) {
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
