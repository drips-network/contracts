// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./libraries/ReceiverWeights.sol";

struct ReceiverWeight {
    address receiver;
    uint32 weight;
}

interface IDai is IERC20 {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @notice Funding pool contract. Automatically sends funds to a configurable set of receivers.
///
/// The contract has 2 types of users: the senders and the receivers.
///
/// A sender has some funds and a set of addresses of receivers, to whom he wants to send funds.
/// In order to send there are 3 conditions, which must be fulfilled:
///
/// 1. There must be funds on his account in this contract.
///    They can be added with `topUp` and removed with `withdraw`.
/// 2. Total amount sent to the receivers every second must be set to a non-zero value.
///    This is done with `setAmtPerSec`.
/// 3. A set of receivers must be non-empty.
///    Receivers can be added, removed and updated with `setReceiver`.
///    Each receiver has a weight, which is used to calculate how the total sent amount is split.
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
/// A single address can be used as a sender and as a receiver, even at the same time.
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

    struct AmtDelta {
        // Amount delta applied on this cycle
        int128 thisCycle;
        // Amount delta applied on the next cycle
        int128 nextCycle;
    }

    /// @dev Details about all the senders, the key is the owner's address
    mapping(address => Sender) internal senders;
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
        uint64 currFinishedCycle = _currTimestamp() / cycleSecs;
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
    function collect() public virtual {
        uint128 collected = _collectInternal(msg.sender);
        if (collected > 0) {
            _transferToSender(msg.sender, collected);
        }
        emit Collected(msg.sender, collected);
    }

    /// @notice Removes from the history and returns the amount of received
    /// funds available for collection by the sender of the message
    /// @return collected The collected amount
    function _collectInternal(address id) internal returns (uint128 collected) {
        Receiver storage receiver = receivers[id];
        uint64 collectedCycle = receiver.nextCollectedCycle;
        if (collectedCycle == 0) return 0;
        uint64 currFinishedCycle = _currTimestamp() / cycleSecs;
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
    /// of the receivers and split between them proportionally to their weights.
    /// Each receiver then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    ///
    /// Sets the weight of the provided receivers of the sender of the message.
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers get.
    /// Setting a non-zero weight for a new receiver adds it to the set of the sender's receivers.
    /// Setting zero as the weight for a receiver removes it from the set of the sender's receivers.
    /// @param topUpAmt The topped up amount
    /// @param withdrawAmt The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param amtPerSec The target amount to be sent every second.
    /// Can be `AMT_PER_SEC_UNCHANGED` to keep the amount unchanged.
    /// @param updatedReceivers The list of the updated receivers and their new weights
    /// @return withdrawn The withdrawn amount which should be sent to the sender of the message.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` is used.
    function _updateSenderInternal(
        address id,
        uint128 topUpAmt,
        uint128 withdrawAmt,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) internal returns (uint128 withdrawn) {
        _stopSending(id);
        _topUp(id, topUpAmt);
        withdrawn = _withdraw(id, withdrawAmt);
        _setAmtPerSec(id, amtPerSec);
        for (uint256 i = 0; i < updatedReceivers.length; i++) {
            _setReceiver(id, updatedReceivers[i].receiver, updatedReceivers[i].weight);
        }
        Sender storage sender = senders[id];
        emit SenderUpdated(id, sender.startBalance, sender.amtPerSec);
        _startSending(id);
    }

    /// @notice Adds the given amount to the senders pool balance
    /// @param amt The topped up amount
    function _topUp(address id, uint128 amt) internal {
        if (amt != 0) senders[id].startBalance += amt;
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
        uint192 alreadySent = (_currTimestamp() - sender.startTime) * amtPerSec;
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
    function _withdraw(address id, uint128 amt) internal returns (uint128 withdrawn) {
        if (amt == 0) return 0;
        uint128 startBalance = senders[id].startBalance;
        if (amt == WITHDRAW_ALL) amt = startBalance;
        if (amt == 0) return 0;
        require(amt <= startBalance, "Not enough funds in the sender account");
        senders[id].startBalance = startBalance - amt;
        return amt;
    }

    /// @notice Sets the target amount sent every second from the sender of the message.
    /// Every second this amount is rounded down to the closest multiple of the sum of the weights
    /// of the receivers and split between them proportionally to their weights.
    /// Each receiver then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    /// @param amtPerSec The target amount to be sent every second
    function _setAmtPerSec(address id, uint128 amtPerSec) internal {
        if (amtPerSec != AMT_PER_SEC_UNCHANGED) senders[id].amtPerSec = amtPerSec;
    }

    /// @notice Gets the target amount sent every second from the sender of the message.
    /// The actual amount sent every second may differ from the target value.
    /// It's rounded down to the closest multiple of the sum of the weights of
    /// the sender's receivers and split between them proportionally to their weights.
    /// Each receiver then receives their part from the sender's balance.
    /// If zero, funding is stopped.
    /// @return amt The target amount to be sent every second
    function getAmtPerSec() public view returns (uint128 amt) {
        return senders[msg.sender].amtPerSec;
    }

    /// @notice Sets the weight of the provided receiver of the sender of the message.
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers gets.
    /// Setting a non-zero weight for a new receiver adds it to the list of the sender's receivers.
    /// Setting zero as the weight for a receiver removes it from the list of the sender's receivers.
    /// @param receiver The address of the receiver
    /// @param weight The weight of the receiver
    function _setReceiver(address id, address receiver, uint32 weight) internal {
        Sender storage sender = senders[id];
        uint64 senderWeightSum = sender.weightSum;
        uint32 oldWeight = sender.receiverWeights.setWeight(receiver, weight);
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

    /// @notice Gets the receivers to whom the sender of the message sends funds.
    /// Each entry contains a weight, which regulates the share of the amount
    /// being sent every second in relation to other sender's receivers.
    /// @return weights The list of receiver addresses and their weights.
    /// The weights are never zero.
    function getAllReceivers() public view returns (ReceiverWeight[] memory weights) {
        Sender storage sender = senders[msg.sender];
        weights = new ReceiverWeight[](sender.weightCount);
        uint32 weightsCount = 0;
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        address hint = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 receiverWeight;
            (receiver, hint, receiverWeight) = sender.receiverWeights.nextWeight(receiver, hint);
            if (receiver == ReceiverWeightsImpl.ADDR_ROOT) break;
            weights[weightsCount++] = ReceiverWeight(receiver, receiverWeight);
        }
    }

    /// @notice Called when funds need to be transferred out of the pool to the message sender
    /// @param amt The transferred amount
    function _transferToSender(address usr, uint128 amt) internal virtual;

    /// @notice Makes `msg.sender` stop sending funds.
    /// It removes any effects of the sender from all of its receivers.
    /// It doesn't modify the sender.
    /// It allows the properties of the sender to be safely modified
    /// without having to update the state of its receivers.
    function _stopSending(address id) internal {
        Sender storage sender = senders[id];
        // Hasn't been sending anything
        if (sender.weightSum == 0 || sender.amtPerSec < sender.weightSum) return;
        uint128 amtPerWeight = sender.amtPerSec / sender.weightSum;
        uint128 amtPerSec = amtPerWeight * sender.weightSum;
        uint256 endTimeUncapped = sender.startTime + uint256(sender.startBalance / amtPerSec);
        uint64 endTime = endTimeUncapped > MAX_TIMESTAMP ? MAX_TIMESTAMP : uint64(endTimeUncapped);
        // The funding period has run out
        if (endTime <= _currTimestamp()) {
            sender.startBalance %= amtPerSec;
            return;
        }
        sender.startBalance -= (_currTimestamp() - sender.startTime) * amtPerSec;
        _setDeltasFromNow(id, -int128(amtPerWeight), endTime);
    }

    /// @notice Makes `msg.sender` start sending funds.
    /// It applies effects of the sender on all of its receivers.
    /// It doesn't modify the sender.
    function _startSending(address id) internal {
        Sender storage sender = senders[id];
        // Won't be sending anything
        if (sender.weightSum == 0 || sender.amtPerSec < sender.weightSum) return;
        uint128 amtPerWeight = sender.amtPerSec / sender.weightSum;
        uint128 amtPerSec = amtPerWeight * sender.weightSum;
        // Won't be sending anything
        if (sender.startBalance < amtPerSec) return;
        sender.startTime = _currTimestamp();
        uint256 endTimeUncapped = _currTimestamp() + uint256(sender.startBalance / amtPerSec);
        uint64 endTime = endTimeUncapped > MAX_TIMESTAMP ? MAX_TIMESTAMP : uint64(endTimeUncapped);
        _setDeltasFromNow(id, int128(amtPerWeight), endTime);
    }

    /// @notice Sets deltas to all sender's receivers from now to `timeEnd`
    /// proportionally to their weights.
    /// Effects are applied as if the change was made on the beginning of the current cycle.
    /// @param amtPerWeightPerSecDelta Amount of per-second delta applied per receiver weight
    /// @param timeEnd The timestamp from which the delta stops taking effect
    function _setDeltasFromNow(address id, int128 amtPerWeightPerSecDelta, uint64 timeEnd) internal {
        Sender storage sender = senders[id];
        // Iterating over receivers, see `ReceiverWeights` for details
        address receiverAddr = ReceiverWeightsImpl.ADDR_ROOT;
        address hint = ReceiverWeightsImpl.ADDR_ROOT;
        while (true) {
            uint32 weight;
            (receiverAddr, hint, weight) = sender.receiverWeights.nextWeightPruning(
                receiverAddr,
                hint
            );
            if (receiverAddr == ReceiverWeightsImpl.ADDR_ROOT) break;
            int128 amtPerSecDelta = int128(uint128(weight)) * amtPerWeightPerSecDelta;
            _setReceiverDeltaFromNow(receiverAddr, amtPerSecDelta, timeEnd);
            if (amtPerSecDelta > 0) {
                // Sending is starting
                uint128 amtPerSec = uint128(amtPerSecDelta);
                emit SenderToReceiverUpdated(id, receiverAddr, amtPerSec, timeEnd);
            } else {
                // Sending is stopping
                emit SenderToReceiverUpdated(id, receiverAddr, 0, _currTimestamp());
            }
        }
    }

    /// @notice Sets deltas to a receiver from now to `timeEnd`
    /// @param receiverAddr The address of the receiver
    /// @param amtPerSecDelta Change of the per-second receiving rate
    /// @param timeEnd The timestamp from which the delta stops taking effect
    function _setReceiverDeltaFromNow(
        address receiverAddr,
        int128 amtPerSecDelta,
        uint64 timeEnd
    ) internal {
        Receiver storage receiver = receivers[receiverAddr];
        // The receiver was never used, initialize it.
        // The first usage of a receiver is always setting a positive delta to start sending.
        // If the delta is negative, the receiver must've been used before and now is being cleared.
        if (amtPerSecDelta > 0 && receiver.nextCollectedCycle == 0)
            receiver.nextCollectedCycle = _currTimestamp() / cycleSecs + 1;
        // Set delta in a time range from now to `timeEnd`
        _setSingleDelta(receiver.amtDeltas, _currTimestamp(), amtPerSecDelta);
        _setSingleDelta(receiver.amtDeltas, timeEnd, -amtPerSecDelta);
    }

    /// @notice Sets delta of a single receiver on a given timestamp
    /// @param amtDeltas The deltas of the per-cycle receiving rate
    /// @param timestamp The timestamp from which the delta takes effect
    /// @param amtPerSecDelta Change of the per-second receiving rate
    function _setSingleDelta(
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
        amtDeltas[thisCycle].thisCycle += int128(uint128(thisCycleSecs)) * amtPerSecDelta;
        amtDeltas[thisCycle].nextCycle += int128(uint128(nextCycleSecs)) * amtPerSecDelta;
    }

    function _currTimestamp() internal view returns (uint64) {
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
    /// of the receivers and split between them proportionally to their weights.
    /// Each receiver then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    ///
    /// Sets the weight of the provided receivers of the sender of the message.
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers get.
    /// Setting a non-zero weight for a new receiver adds it to the set of the sender's receivers.
    /// Setting zero as the weight for a receiver removes it from the set of the sender's receivers.
    /// @param withdraw The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param amtPerSec The target amount to be sent every second.
    /// Can be `AMT_PER_SEC_UNCHANGED` to keep the amount unchanged.
    /// @param updatedReceivers The list of the updated receivers and their new weights
    /// @return withdrawn The actually withdrawn amount.
    function updateSender(
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public virtual payable returns(uint128 withdrawn) {
        withdrawn =
            _updateSenderInternal(
                msg.sender,
                uint128(msg.value),
                withdraw,
                amtPerSec,
                updatedReceivers
            );
        _transferToSender(msg.sender, withdrawn);
    }

    function _transferToSender(address usr, uint128 amt) internal override {
        if (amt != 0) payable(usr).transfer(amt);
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
    /// of the receivers and split between them proportionally to their weights.
    /// Each receiver then receives their part from the sender's balance.
    /// If set to zero, stops funding.
    ///
    /// Sets the weight of the provided receivers of the sender of the message.
    /// The weight regulates the share of the amount sent every second
    /// that each of the sender's receivers get.
    /// Setting a non-zero weight for a new receiver adds it to the set of the sender's receivers.
    /// Setting zero as the weight for a receiver removes it from the set of the sender's receivers.
    /// @param topUpAmt The topped up amount
    /// @param withdraw The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param amtPerSec The target amount to be sent every second.
    /// Can be `AMT_PER_SEC_UNCHANGED` to keep the amount unchanged.
    /// @param updatedReceivers The list of the updated receivers and their new weights
    /// @return withdrawn The actually withdrawn amount.
    function updateSender(
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public virtual returns(uint128 withdrawn) {
        _transferToContract(msg.sender, topUpAmt);
        withdrawn =
            _updateSenderInternal(msg.sender, topUpAmt, withdraw, amtPerSec, updatedReceivers);
        _transferToSender(msg.sender, withdrawn);
    }

    function _transferToContract(address usr, uint128 amt) internal {
        if (amt != 0) erc20.transferFrom(usr, address(this), amt);
    }

    function _transferToSender(address usr, uint128 amt) internal override {
        if (amt != 0) erc20.transfer(usr, amt);
    }
}

/// @notice Funding pool contract for DAI token.
/// See the base `Pool` contract docs for more details.
contract DaiPool is Erc20Pool {
    // solhint-disable no-empty-blocks
    /// @notice See `Erc20Pool` constructor documentation for more details.
    constructor(uint64 cycleSecs, IDai dai) Erc20Pool(cycleSecs, dai) {}

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
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual returns(uint128 withdrawn) {
        IDai(address(erc20)).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
        return updateSender(topUpAmt, withdraw, amtPerSec, updatedReceivers);
    }
}
