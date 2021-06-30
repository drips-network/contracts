// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/ProxyDeltas.sol";
import "./libraries/ReceiverWeights.sol";
import "./TestDai.sol";

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
/// 2. Total amount sent to the receivers every second must be set to a non-zero value.
///    This is done with `setAmtPerSec`.
/// 3. A set of receivers and proxies must be non-empty.
///    Receivers can be added, removed and updated with `setReceiver`, proxies with `setProxy`.
///    Each receiver or proxy has a weight,
///    which is used to calculate how the total sent amount is split.
///
/// Each of these functions can be called in any order and at any time, they have immediate effects.
/// When all of these conditions are fulfilled, every second the configured amount is being sent.
/// It's extracted from the `withdraw`able balance and transferred to the receivers.
/// The process continues automatically until the sender's balance is empty.
///
/// A receiver has an account, from which he can `collect` funds sent by the senders.
/// The available amount is updated every `cycleSecs` seconds,
/// so recently sent funds may not be `collect`able immediately.
/// `cycleSecs` is a constant configured when the pool is deployed.
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
/// The concept of something happening periodically, e.g. every second or every `cycleSecs` are
/// only high-level abstractions for the user, Ethereum isn't really capable of scheduling work.
/// The actual implementation emulates that behavior by calculating the results of the scheduled
/// events based on how many seconds have passed and only when a user needs their outcomes.
///
/// The contract assumes that all amounts in the system can be stored in signed 128-bit integers.
/// It's guaranteed to be safe only when working with assets with supply lower than `2 ^ 127`.
abstract contract Pool {
    using ReceiverWeightsImpl for ReceiverWeights;
    using ProxyDeltasImpl for ProxyDeltas;

    /// @notice On every timestamp `T`, which is a multiple of `cycleSecs`, the receivers
    /// gain access to funds collected during `T - cycleSecs` to `T - 1`.
    uint64 public immutable cycleSecs;
    /// @dev Timestamp at which all funding periods must be finished
    uint64 internal constant MAX_TIMESTAMP = type(uint64).max - 2;
    /// @notice Maximum sum of all receiver weights of a single sender.
    /// Limits loss of per-second funding accuracy, they are always multiples of weights sum.
    uint32 public constant SENDER_WEIGHTS_SUM_MAX = 10000;
    /// @notice Maximum number of receivers of a single sender.
    /// Limits costs of changes in sender's configuration.
    uint32 public constant SENDER_WEIGHTS_COUNT_MAX = 100;
    /// @notice The sum of all receiver weights of a single proxy.
    /// It must remain constant throughout the whole life of a proxy.
    /// A sender's weight of a proxy must always be a multiple of this value.
    /// Limits loss of per-second funding accuracy.
    uint32 public constant PROXY_WEIGHTS_SUM = 100;
    /// @notice Maximum number of receivers of a single proxy.
    /// Whenever a proxy is added to a sender, this number is added to its `weightCount`.
    /// Limits costs of changes in sender's or proxy's configuration.
    uint32 public constant PROXY_WEIGHTS_COUNT_MAX = 10;
    /// @notice The amount passed as the withdraw amount to withdraw all the funds
    uint128 public constant WITHDRAW_ALL = type(uint128).max;
    /// @notice The amount passed as the amount per second to keep the parameter unchanged
    uint128 public constant AMT_PER_SEC_UNCHANGED = type(uint128).max;

    /// @notice Emitted when a direct stream of funds between a sender and a receiver is updated.
    /// This is caused by a sender updating their parameters.
    /// Funds are being sent on every second between the event block's timestamp (inclusively) and
    /// `endTime` (exclusively) or until the timestamp of the next stream update (exclusively).
    /// @param sender The sender of the updated stream
    /// @param receiver The receiver of the updated stream
    /// @param amtPerSec The new amount per second sent from the sender to the receiver
    /// or 0 if sending is stopped
    /// @param endTime The timestamp when the funds stop being sent,
    /// always larger than the block timestamp or equal to it if sending is stopped
    event SenderToReceiverUpdated(
        address indexed sender,
        address indexed receiver,
        uint128 amtPerSec,
        uint64 endTime
    );

    /// @notice Emitted when a stream of funds between a sender and a proxy is updated.
    /// This is caused by a sender updating their parameters.
    /// Funds are being sent on every second between the event block's timestamp (inclusively) and
    /// `endTime` (exclusively) or until the timestamp of the next stream update (exclusively).
    /// @param sender The sender of the updated stream
    /// @param proxy The proxy receiver of the updated stream
    /// @param amtPerSec The new amount per second sent from the sender to the proxy
    /// or 0 if sending is stopped
    /// @param endTime The timestamp when the funds stop being sent,
    /// always larger than the block timestamp or equal to it if sending is stopped
    event SenderToProxyUpdated(
        address indexed sender,
        address indexed proxy,
        uint128 amtPerSec,
        uint64 endTime
    );

    /// @notice Emitted when a stream of funds between a proxy and a sender is updated.
    /// This is caused by a proxy updating the receiver's weight.
    /// Funds are being sent between the event block's timestamp (exclusively) and
    /// the timestamp of the next stream update (inclusively).
    /// During the sending period on every timestamp `T` which is a multiple of `cycleSecs`
    /// the receiver gets a share of all funds sent to the proxy
    /// during timestamps from `T - cycleSecs` (inclusively) to `T` (exclusively).
    /// @param proxy The sender proxy of the updated stream
    /// @param receiver The receiver of the updated stream
    /// @param weight The weight of the receiver or 0 if sending is stopped.
    /// The receiver will be getting `weight / PROXY_WEIGHTS_SUM` of funds sent to the proxy.
    event ProxyToReceiverUpdated(address indexed proxy, address indexed receiver, uint32 weight);

    /// @notice Emitted when a sender is updated
    /// @param sender The updated sender
    /// @param balance The sender's balance since the event block's timestamp
    /// @param amtPerSec The target amount sent per second after the update.
    /// Takes effect on the event block's timestamp (inclusively).
    event SenderUpdated(address indexed sender, uint128 balance, uint128 amtPerSec);

    /// @notice Emitted when a receiver collects funds
    /// @param receiver The collecting receiver
    /// @param amt The collected amount
    event Collected(address indexed receiver, uint128 amt);

    struct Sender {
        // Timestamp at which the funding period has started
        uint64 startTime;
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
        // The target amount sent per second.
        // The actual amount is rounded down to the closes multiple of `weightSum`.
        uint128 amtPerSec;
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
        // The keys are cycles, each cycle `C` becomes collectable on timestamp `C * cycleSecs`.
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

    /// @param _cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of funds being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 _cycleSecs) {
        cycleSecs = _cycleSecs;
    }

    /// @notice Returns amount of received funds available for collection
    /// by the sender of the message
    /// @return collected The available amount
    function collectable() public view returns (uint128) {
        Receiver storage receiver = receivers[msg.sender];
        uint64 collectedCycle = receiver.nextCollectedCycle;
        if (collectedCycle == 0) return 0;
        uint64 currFinishedCycle = currTimestamp() / cycleSecs;
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
    /// by the sender of the message and sends them to that sender
    function collect() public {
        uint128 collected = collectInternal();
        if (collected > 0) {
            transferToSender(collected);
        }
        emit Collected(msg.sender, collected);
    }

    /// @notice Removes from the history and returns the amount of received
    /// funds available for collection by the sender of the message
    /// @return collected The collected amount
    function collectInternal() internal returns (uint128 collected) {
        Receiver storage receiver = receivers[msg.sender];
        uint64 collectedCycle = receiver.nextCollectedCycle;
        if (collectedCycle == 0) return 0;
        uint64 currFinishedCycle = currTimestamp() / cycleSecs;
        if (collectedCycle > currFinishedCycle) return 0;
        int128 lastFundsPerCycle = receiver.lastFundsPerCycle;
        for (; collectedCycle <= currFinishedCycle; collectedCycle++) {
            lastFundsPerCycle += receiver.amtDeltas[collectedCycle - 1].nextCycle;
            lastFundsPerCycle += receiver.amtDeltas[collectedCycle].thisCycle;
            collected += uint128(lastFundsPerCycle);
            delete receiver.amtDeltas[collectedCycle - 1];
        }
        receiver.lastFundsPerCycle = lastFundsPerCycle;
        receiver.nextCollectedCycle = collectedCycle;
    }

    /// @notice Updates all the sender parameters of the sender of the message.
    ///
    /// Tops up and withdraws unsent funds from the balance of the sender.
    ///
    /// Sets the target amount sent every second from the sender of the message.
    /// Every second this amount is rounded down to the closest multiple of the sum of the weights
    /// of the receivers and proxies and split between them proportionally to their weights.
    /// Each receiver and proxy then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    ///
    /// Sets the weight of the provided receivers and proxies of the sender of the message.
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new receiver or
    /// a new proxy adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a receiver or a proxy
    /// removes it from the list of the sender's receivers.
    /// @param topUpAmt The topped up amount
    /// @param withdrawAmt The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param amtPerSec The target amount to be sent every second.
    /// Can be `AMT_PER_SEC_UNCHANGED` to keep the amount unchanged.
    /// @param updatedReceivers The list of the updated receivers and their new weights
    /// @param updatedProxies The list of the updated proxies and their new weights
    /// @return withdrawn The withdrawn amount which should be sent to the sender of the message.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` is used.
    function updateSenderInternal(
        uint128 topUpAmt,
        uint128 withdrawAmt,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers,
        ReceiverWeight[] calldata updatedProxies
    ) internal returns (uint128 withdrawn) {
        stopSending();
        topUp(topUpAmt);
        withdrawn = withdraw(withdrawAmt);
        setAmtPerSec(amtPerSec);
        for (uint256 i = 0; i < updatedReceivers.length; i++) {
            setReceiver(updatedReceivers[i].receiver, updatedReceivers[i].weight);
        }
        for (uint256 i = 0; i < updatedProxies.length; i++) {
            setProxy(updatedProxies[i].receiver, updatedProxies[i].weight);
        }
        Sender storage sender = senders[msg.sender];
        emit SenderUpdated(msg.sender, sender.startBalance, sender.amtPerSec);
        startSending();
    }

    /// @notice Adds the given amount to the senders pool balance
    /// @param amt The topped up amount
    function topUp(uint128 amt) internal {
        if (amt != 0) senders[msg.sender].startBalance += amt;
    }

    /// @notice Returns amount of unsent funds available for withdrawal by the sender of the message
    /// @return balance The available balance
    function withdrawable() public view returns (uint128) {
        Sender storage sender = senders[msg.sender];
        // Hasn't been sending anything
        if (sender.weightSum == 0 || sender.amtPerSec < sender.weightSum) {
            return sender.startBalance;
        }
        uint128 amtPerSec = sender.amtPerSec - (sender.amtPerSec % sender.weightSum);
        uint192 alreadySent = (currTimestamp() - sender.startTime) * amtPerSec;
        if (alreadySent > sender.startBalance) {
            return sender.startBalance % amtPerSec;
        }
        return sender.startBalance - uint128(alreadySent);
    }

    /// @notice Withdraws unsent funds of the sender of the message
    /// @param amt The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @return withdrawn The actually withdrawn amount.
    /// Equal to `amt` unless `WITHDRAW_ALL` is used.
    function withdraw(uint128 amt) internal returns (uint128 withdrawn) {
        if (amt == 0) return 0;
        uint128 startBalance = senders[msg.sender].startBalance;
        if (amt == WITHDRAW_ALL) amt = startBalance;
        if (amt == 0) return 0;
        require(amt <= startBalance, "Not enough funds in the sender account");
        senders[msg.sender].startBalance = startBalance - amt;
        return amt;
    }

    /// @notice Sets the target amount sent every second from the sender of the message.
    /// Every second this amount is rounded down to the closest multiple of the sum of the weights
    /// of the receivers and proxies and split between them proportionally to their weights.
    /// Each receiver and proxy then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    /// @param amtPerSec The target amount to be sent every second
    function setAmtPerSec(uint128 amtPerSec) internal {
        if (amtPerSec != AMT_PER_SEC_UNCHANGED) senders[msg.sender].amtPerSec = amtPerSec;
    }

    /// @notice Gets the target amount sent every second from the sender of the message.
    /// The actual amount sent every second may differ from the target value.
    /// It's rounded down to the closest multiple of the sum of the weights of
    /// the sender's receivers and proxies and split between them proportionally to their weights.
    /// Each receiver and proxy then receives their part from the sender's balance.
    /// If zero, funding is stopped.
    /// @return amt The target amount to be sent every second
    function getAmtPerSec() public view returns (uint128 amt) {
        return senders[msg.sender].amtPerSec;
    }

    /// @notice Sets the weight of the provided receiver of the sender of the message.
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new receiver adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a receiver removes it from the list of the sender's receivers.
    /// @param receiver The address of the receiver
    /// @param weight The weight of the receiver
    function setReceiver(address receiver, uint32 weight) internal {
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
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new proxy adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a proxy removes it from the list of the sender's receivers.
    /// @param proxy The address of the proxy
    /// @param weight The weight of the proxy, must be a multiple of `PROXY_WEIGHTS_SUM`
    function setProxy(address proxy, uint32 weight) internal {
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
    /// being sent every second in relation to other sender's receivers and proxies.
    /// @return weights The list of receiver and proxy addresses and their weights.
    /// Each entry has at least one non-zero weight.
    function getAllReceivers() public view returns (ReceiverProxyWeight[] memory weights) {
        Sender storage sender = senders[msg.sender];
        ReceiverProxyWeight[] memory weightsSparse = new ReceiverProxyWeight[](sender.weightCount);
        uint32 weightsCount = 0;
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        address hint = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 receiverWeight;
            uint32 proxyWeight;
            (receiver, hint, receiverWeight, proxyWeight) = sender.receiverWeights.nextWeight(
                receiver,
                hint
            );
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
    /// The weight regulates the share of the amount being sent every second in relation to
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
                receivers[receiverAddr].nextCollectedCycle = currTimestamp() / cycleSecs + 1;
            }
            emit ProxyToReceiverUpdated(msg.sender, receiverAddr, weight);
        }
        require(weightSum == PROXY_WEIGHTS_SUM, "Proxy doesn't have the constant weight sum");
    }

    /// @notice Gets the receivers to whom the proxy of the sender of the message passes funds.
    /// Each entry contains weights, which regulate the share of the amount
    /// being sent every second in relation to other proxy's receivers.
    /// @return weights The list of receiver addresses and their non-zero weights.
    function getProxyWeights() public view returns (ReceiverWeight[] memory weights) {
        Proxy storage proxy = proxies[msg.sender];
        ReceiverWeight[] memory weightsSparse = new ReceiverWeight[](PROXY_WEIGHTS_COUNT_MAX);
        uint32 weightsCount = 0;
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        address hint = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 weight;
            (receiver, hint, weight, ) = proxy.receiverWeights.nextWeight(receiver, hint);
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
    /// @param amt The transferred amount
    function transferToSender(uint128 amt) internal virtual;

    /// @notice Makes `msg.sender` stop sending funds.
    /// It removes any effects of the sender from all of its receivers.
    /// It doesn't modify the sender.
    /// It allows the properties of the sender to be safely modified
    /// without having to update the state of its receivers.
    function stopSending() internal {
        Sender storage sender = senders[msg.sender];
        // Hasn't been sending anything
        if (sender.weightSum == 0 || sender.amtPerSec < sender.weightSum) return;
        uint128 amtPerWeight = sender.amtPerSec / sender.weightSum;
        uint128 amtPerSec = amtPerWeight * sender.weightSum;
        uint256 endTimeUncapped = sender.startTime + uint256(sender.startBalance / amtPerSec);
        uint64 endTime = endTimeUncapped > MAX_TIMESTAMP ? MAX_TIMESTAMP : uint64(endTimeUncapped);
        // The funding period has run out
        if (endTime <= currTimestamp()) {
            sender.startBalance %= amtPerSec;
            return;
        }
        sender.startBalance -= (currTimestamp() - sender.startTime) * amtPerSec;
        setDeltasFromNow(-int128(amtPerWeight), endTime);
    }

    /// @notice Makes `msg.sender` start sending funds.
    /// It applies effects of the sender on all of its receivers.
    /// It doesn't modify the sender.
    function startSending() internal {
        Sender storage sender = senders[msg.sender];
        // Won't be sending anything
        if (sender.weightSum == 0 || sender.amtPerSec < sender.weightSum) return;
        uint128 amtPerWeight = sender.amtPerSec / sender.weightSum;
        uint128 amtPerSec = amtPerWeight * sender.weightSum;
        // Won't be sending anything
        if (sender.startBalance < amtPerSec) return;
        sender.startTime = currTimestamp();
        uint256 endTimeUncapped = currTimestamp() + uint256(sender.startBalance / amtPerSec);
        uint64 endTime = endTimeUncapped > MAX_TIMESTAMP ? MAX_TIMESTAMP : uint64(endTimeUncapped);
        setDeltasFromNow(int128(amtPerWeight), endTime);
    }

    /// @notice Sets deltas to all sender's receivers and proxies from now to `timeEnd`
    /// proportionally to their weights.
    /// Effects are applied as if the change was made on the beginning of the current cycle.
    /// @param amtPerWeightPerSecDelta Amount of per-second delta applied per receiver weight
    /// @param timeEnd The timestamp from which the delta stops taking effect
    function setDeltasFromNow(int128 amtPerWeightPerSecDelta, uint64 timeEnd) internal {
        Sender storage sender = senders[msg.sender];
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiverAddr = ReceiverWeightsImpl.ADDR_ROOT;
        address hint = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 receiverWeight;
            uint32 proxyWeight;
            (receiverAddr, hint, receiverWeight, proxyWeight) = sender
                .receiverWeights
                .nextWeightPruning(receiverAddr, hint);
            if (receiverAddr == ReceiverWeightsImpl.ADDR_ROOT) break;
            if (receiverWeight != 0) {
                int128 amtPerSecDelta = receiverWeight * amtPerWeightPerSecDelta;
                setReceiverDeltaFromNow(receiverAddr, amtPerSecDelta, timeEnd);
                if (amtPerSecDelta > 0) {
                    // Sending is starting
                    uint128 amtPerSec = uint128(amtPerSecDelta);
                    emit SenderToReceiverUpdated(msg.sender, receiverAddr, amtPerSec, timeEnd);
                } else {
                    // Sending is stopping
                    emit SenderToReceiverUpdated(msg.sender, receiverAddr, 0, currTimestamp());
                }
            }
            if (proxyWeight != 0) {
                int128 amtPerSecDelta = proxyWeight * amtPerWeightPerSecDelta;
                updateProxyReceiversDeltaFromNow(receiverAddr, amtPerSecDelta, timeEnd);
                if (amtPerSecDelta > 0) {
                    // Sending is starting
                    uint128 amtPerSec = uint128(amtPerSecDelta);
                    emit SenderToProxyUpdated(msg.sender, receiverAddr, amtPerSec, timeEnd);
                } else {
                    // Sending is stopping
                    emit SenderToProxyUpdated(msg.sender, receiverAddr, 0, currTimestamp());
                }
            }
        }
    }

    /// @notice Updates deltas of a proxy from now to `timeEnd`.
    /// It updates deltas of both the proxy itself and all of its receivers.
    /// Effects are applied as if the change was made on the beginning of the current cycle.
    /// @param proxyAddr The address of the proxy
    /// @param amtPerSecDelta Change of the per-second receiving rate of the proxy
    /// @param timeEnd The timestamp from which the delta stops taking effect
    function updateProxyReceiversDeltaFromNow(
        address proxyAddr,
        int128 amtPerSecDelta,
        uint64 timeEnd
    ) internal {
        int128 amtPerSecPerProxyWeightDelta = amtPerSecDelta / PROXY_WEIGHTS_SUM;
        Proxy storage proxy = proxies[proxyAddr];
        updateSingleProxyDelta(
            proxy.amtPerWeightDeltas,
            currTimestamp(),
            amtPerSecPerProxyWeightDelta
        );
        updateSingleProxyDelta(proxy.amtPerWeightDeltas, timeEnd, -amtPerSecPerProxyWeightDelta);
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        address hint = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 weight;
            (receiver, hint, weight, ) = proxy.receiverWeights.nextWeightPruning(receiver, hint);
            if (receiver == ReceiverWeightsImpl.ADDR_ROOT) break;
            setReceiverDeltaFromNow(receiver, amtPerSecPerProxyWeightDelta * weight, timeEnd);
        }
    }

    /// @notice Updates the delta of a single proxy on a given timestamp
    /// @param proxyDeltas The deltas of the per-cycle receiving rate
    /// @param timestamp The timestamp from which the delta takes effect
    /// @param amtPerSecDelta Change of the per-second receiving rate
    function updateSingleProxyDelta(
        ProxyDeltas storage proxyDeltas,
        uint64 timestamp,
        int128 amtPerSecDelta
    ) internal {
        // In order to set a delta on a specific timestamp it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint64 thisCycle = timestamp / cycleSecs + 1;
        uint64 nextCycleSecs = timestamp % cycleSecs;
        uint64 thisCycleSecs = cycleSecs - nextCycleSecs;
        proxyDeltas.addToDelta(
            thisCycle,
            thisCycleSecs * amtPerSecDelta,
            nextCycleSecs * amtPerSecDelta
        );
    }

    /// @notice Sets deltas to a receiver from now to `timeEnd`
    /// @param receiverAddr The address of the receiver
    /// @param amtPerSecDelta Change of the per-second receiving rate
    /// @param timeEnd The timestamp from which the delta stops taking effect
    function setReceiverDeltaFromNow(
        address receiverAddr,
        int128 amtPerSecDelta,
        uint64 timeEnd
    ) internal {
        Receiver storage receiver = receivers[receiverAddr];
        // The receiver was never used, initialize it.
        // The first usage of a receiver is always setting a positive delta to start sending.
        // If the delta is negative, the receiver must've been used before and now is being cleared.
        if (amtPerSecDelta > 0 && receiver.nextCollectedCycle == 0)
            receiver.nextCollectedCycle = currTimestamp() / cycleSecs + 1;
        // Set delta in a time range from now to `timeEnd`
        setSingleDelta(receiver.amtDeltas, currTimestamp(), amtPerSecDelta);
        setSingleDelta(receiver.amtDeltas, timeEnd, -amtPerSecDelta);
    }

    /// @notice Sets delta of a single receiver on a given timestamp
    /// @param amtDeltas The deltas of the per-cycle receiving rate
    /// @param timestamp The timestamp from which the delta takes effect
    /// @param amtPerSecDelta Change of the per-second receiving rate
    function setSingleDelta(
        mapping(uint64 => AmtDelta) storage amtDeltas,
        uint64 timestamp,
        int128 amtPerSecDelta
    ) internal {
        // In order to set a delta on a specific timestamp it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint64 thisCycle = timestamp / cycleSecs + 1;
        uint64 nextCycleSecs = timestamp % cycleSecs;
        uint64 thisCycleSecs = cycleSecs - nextCycleSecs;
        amtDeltas[thisCycle].thisCycle += thisCycleSecs * amtPerSecDelta;
        amtDeltas[thisCycle].nextCycle += nextCycleSecs * amtPerSecDelta;
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
        Proxy storage proxy = proxies[msg.sender];
        uint32 receiversCount = 0;
        // Create an in-memory copy of the receivers list to reduce storage access
        ReceiverWeight[] memory receiversList = new ReceiverWeight[](PROXY_WEIGHTS_COUNT_MAX);
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiverAddr = ReceiverWeightsImpl.ADDR_ROOT;
        address receiverHint = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 weight;
            (receiverAddr, receiverHint, weight, ) = proxy.receiverWeights.nextWeightPruning(
                receiverAddr,
                receiverHint
            );
            if (receiverAddr == ReceiverWeightsImpl.ADDR_ROOT) break;
            require(receiversCount < PROXY_WEIGHTS_COUNT_MAX, "Too many proxy receivers");
            receiversList[receiversCount++] = ReceiverWeight(receiverAddr, weight);
        }
        // The proxy doesn't exist
        if (receiversCount == 0) return;

        // Iterating over deltas, see `ProxyDeltas` for details
        uint64 cycle = ProxyDeltasImpl.CYCLE_ROOT;
        uint64 cycleHint = ProxyDeltasImpl.CYCLE_ROOT;
        uint64 finishedCycle = currTimestamp() / cycleSecs;
        uint64 currCycle = finishedCycle + 1;
        // The sum of all the future changes to the per-second amount the proxy receives.
        // This is also the per-second amount the proxy receives per weight in the current cycle,
        // but with its sign inverted.
        // Thus if `multiplier` is `1`, then this value is negative and if `-1`, it's positive.
        int128 totalDelta = 0;
        while (true) {
            int128 thisCycleDelta;
            int128 nextCycleDelta;
            (cycle, cycleHint, thisCycleDelta, nextCycleDelta) = proxy
                .amtPerWeightDeltas
                .nextDeltaPruning(cycle, cycleHint, finishedCycle);
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

    function currTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp);
    }
}

/// @notice Funding pool contract for Ether.
/// See the base `Pool` contract docs for more details.
contract EthPool is Pool {
    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of Ether being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 cycleSecs) Pool(cycleSecs) {
        return;
    }

    /// @notice Updates all the sender parameters of the sender of the message.
    ///
    /// Tops up and withdraws unsent funds from the balance of the sender.
    /// Tops up with the amount in the message.
    /// Sends the withdrawn funds to the sender of the message.
    ///
    /// Sets the target amount sent every second from the sender of the message.
    /// Every second this amount is rounded down to the closest multiple of the sum of the weights
    /// of the receivers and proxies and split between them proportionally to their weights.
    /// Each receiver and proxy then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    ///
    /// Sets the weight of the provided receivers and proxies of the sender of the message.
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new receiver or
    /// a new proxy adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a receiver or a proxy
    /// removes it from the list of the sender's receivers.
    /// @param withdraw The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param amtPerSec The target amount to be sent every second.
    /// Can be `AMT_PER_SEC_UNCHANGED` to keep the amount unchanged.
    /// @param updatedReceivers The list of the updated receivers and their new weights
    /// @param updatedProxies The list of the updated proxies and their new weights
    function updateSender(
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers,
        ReceiverWeight[] calldata updatedProxies
    ) public payable {
        uint128 withdrawn =
            updateSenderInternal(
                uint128(msg.value),
                withdraw,
                amtPerSec,
                updatedReceivers,
                updatedProxies
            );
        transferToSender(withdrawn);
    }

    function transferToSender(uint128 amt) internal override {
        if (amt != 0) msg.sender.transfer(amt);
    }
}

/// @notice Funding pool contract for any ERC-20 token.
/// See the base `Pool` contract docs for more details.
contract Erc20Pool is Pool {
    /// @notice The address of the ERC-20 contract which tokens the pool works with
    IERC20 public immutable erc20;

    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of tokens being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    /// @param _erc20 The address of an ERC-20 contract which tokens the pool will work with.
    /// To guarantee safety the supply of the tokens must be lower than `2 ^ 127`.
    constructor(uint64 cycleSecs, IERC20 _erc20) Pool(cycleSecs) {
        erc20 = _erc20;
    }

    /// @notice Updates all the sender parameters of the sender of the message.
    ///
    /// Tops up and withdraws unsent funds from the balance of the sender.
    /// The sender must first grant the contract a sufficient allowance to top up.
    /// Sends the withdrawn funds to the sender of the message.
    ///
    /// Sets the target amount sent every second from the sender of the message.
    /// Every second this amount is rounded down to the closest multiple of the sum of the weights
    /// of the receivers and proxies and split between them proportionally to their weights.
    /// Each receiver and proxy then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    ///
    /// Sets the weight of the provided receivers and proxies of the sender of the message.
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers and proxies get.
    /// Setting a non-zero weight for a new receiver or
    /// a new proxy adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a receiver or a proxy
    /// removes it from the list of the sender's receivers.
    /// @param topUpAmt The topped up amount
    /// @param withdraw The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param amtPerSec The target amount to be sent every second.
    /// Can be `AMT_PER_SEC_UNCHANGED` to keep the amount unchanged.
    /// @param updatedReceivers The list of the updated receivers and their new weights
    /// @param updatedProxies The list of the updated proxies and their new weights
    function updateSender(
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers,
        ReceiverWeight[] calldata updatedProxies
    ) public {
        transferToContract(topUpAmt);
        uint128 withdrawn =
            updateSenderInternal(topUpAmt, withdraw, amtPerSec, updatedReceivers, updatedProxies);
        transferToSender(withdrawn);
    }

    function transferToContract(uint128 amt) internal {
        if (amt != 0) erc20.transferFrom(msg.sender, address(this), amt);
    }

    function transferToSender(uint128 amt) internal override {
        if (amt != 0) erc20.transfer(msg.sender, amt);
    }
}

/// @notice Funding pool contract for DAI token.
/// See the base `Pool` contract docs for more details.
contract DaiPool is Erc20Pool {
    // solhint-disable no-empty-blocks
    /// @notice See `Erc20Pool` constructor documentation for more details.
    constructor(uint64 cycleSecs, Dai dai) Erc20Pool(cycleSecs, dai) {}

    /// @notice Updates all the sender parameters of the sender of the message
    /// and permits spending sender's Dai by the pool.
    /// This function is an extension of `updateSender`, see its documentation for more details.
    ///
    /// The sender must sign a Dai permission document allowing the pool to spend their funds.
    /// The document's `nonce` and `expiry` must be passed here along the parts of its signature.
    /// These parameters will be passed to the Dai contract by this function.
    function updateSenderAndPermit(
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers,
        ReceiverWeight[] calldata updatedProxies,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        Dai dai = Dai(address(erc20));
        dai.permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
        updateSender(topUpAmt, withdraw, amtPerSec, updatedReceivers, updatedProxies);
    }
}
