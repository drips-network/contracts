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

    /// @notice Collects received funds and updates all the sender parameters
    //// of the sender of the message.
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
    /// @param dripsFraction The fraction of received funds to be dripped.
    /// Must be a value from 0 to `DRIPS_FRACTION_MAX` inclusively,
    /// where 0 means no dripping and `DRIPS_FRACTION_MAX` dripping everything.
    /// @param newReceivers The list of the user's receivers and their weights,
    /// which shall be in use after this function is called.
    /// @return withdrawn The actually withdrawn amount.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` is used.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the user's receivers
    function updateSender(
        uint128 withdraw,
        uint128 amtPerSec,
        uint32 dripsFraction,
        ReceiverWeight[] calldata newReceivers
    )
        public
        payable
        returns (
            uint128 withdrawn,
            uint128 collected,
            uint128 dripped
        )
    {
        return
            _updateSenderInternal(
                msg.sender,
                uint128(msg.value),
                withdraw,
                amtPerSec,
                dripsFraction,
                newReceivers
            );
    }

    /// @notice Updates all the parameters of a sub-sender of the sender of the message.
    /// See `updateSender` for more details
    /// @param subSenderId The id of the sender's sub-sender
    function updateSubSender(
        uint256 subSenderId,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata newReceivers
    ) public payable returns (uint128 withdrawn) {
        return
            _updateSubSenderInternal(
                msg.sender,
                subSenderId,
                uint128(msg.value),
                withdraw,
                amtPerSec,
                newReceivers
            );
    }

    function _transfer(address to, uint128 amt) internal override {
        if (amt != 0) payable(to).transfer(amt);
    }
}
