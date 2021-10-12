// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {Pool, Receiver} from "./Pool.sol";

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
    /// @param withdraw The amount to be withdrawn, must not be higher than available funds.
    /// Can be `WITHDRAW_ALL` to withdraw everything.
    /// @param dripsFraction The fraction of received funds to be dripped.
    /// Must be a value from 0 to `MAX_DRIPS_FRACTION` inclusively,
    /// where 0 means no dripping and `MAX_DRIPS_FRACTION` dripping everything.
    /// @param currReceivers The list of the user's receivers which is currently in use.
    /// If this function is called for the first time for the user, should be an empty array.
    /// @param newReceivers The new list of the user's receivers.
    /// @return withdrawn The actually withdrawn amount.
    /// Equal to `withdrawAmt` unless `WITHDRAW_ALL` is used.
    /// @return collected The collected amount
    /// @return dripped The amount dripped to the user's receivers
    function updateSender(
        uint128 withdraw,
        uint32 dripsFraction,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
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
                dripsFraction,
                currReceivers,
                newReceivers
            );
    }

    /// @notice Updates all the parameters of a sub-sender of the sender of the message.
    /// See `updateSender` for more details
    /// @param subSenderId The id of the sender's sub-sender
    function updateSubSender(
        uint256 subSenderId,
        uint128 withdraw,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) public payable returns (uint128 withdrawn) {
        return
            _updateSubSenderInternal(
                msg.sender,
                subSenderId,
                uint128(msg.value),
                withdraw,
                currReceivers,
                newReceivers
            );
    }

    /// @notice Gives funds from the sender of the message to the receiver.
    /// The receiver can collect them immediately.
    /// @param receiver The receiver
    function give(address receiver) public payable {
        _giveInternal(msg.sender, receiver, uint128(msg.value));
    }

    /// @notice Gives funds from the sub-sender of the sender of the message to the receiver.
    /// The receiver can collect them immediately.
    /// @param subSenderId The id of the giver's sub-sender
    /// @param receiver The receiver
    function giveFromSubSender(uint256 subSenderId, address receiver) public payable {
        _giveFromSubSenderInternal(msg.sender, subSenderId, receiver, uint128(msg.value));
    }

    function _transfer(address userAddr, int128 amt) internal override {
        // Take into account the amount already transferred into the pool
        amt += int128(uint128(msg.value));
        if (amt == 0) return;
        require(amt > 0, "Sending a negative ether amount");
        payable(userAddr).transfer(uint128(amt));
    }
}
