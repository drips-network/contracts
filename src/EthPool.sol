// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {Pool, ReceiverWeight} from "./Pool.sol";

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
    ) public payable virtual returns (uint128 withdrawn) {
        withdrawn = _updateSenderInternal(
            msg.sender,
            uint128(msg.value),
            withdraw,
            amtPerSec,
            updatedReceivers
        );
        _transfer(msg.sender, withdrawn);
    }

    function _transfer(address to, uint128 amt) internal override {
        if (amt != 0) payable(to).transfer(amt);
    }
}
