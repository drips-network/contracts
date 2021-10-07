// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {Pool, ReceiverWeight} from "./Pool.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice Funding pool contract for any ERC-20 token.
/// See the base `Pool` contract docs for more details.
contract ERC20Pool is Pool {
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
    /// @param dripsFraction The fraction of received funds to be dripped.
    /// Must be a value from 0 to `DRIPS_FRACTION_MAX` inclusively,
    /// where 0 means no dripping and `DRIPS_FRACTION_MAX` dripping everything.
    /// @param updatedReceivers The list of the updated receivers and their new weights
    /// @return withdrawn The actually withdrawn amount.
    function updateSender(
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        uint32 dripsFraction,
        ReceiverWeight[] calldata updatedReceivers
    ) public virtual returns (uint128 withdrawn) {
        _transferToContract(msg.sender, topUpAmt);
        withdrawn = _updateSenderInternal(
            msg.sender,
            topUpAmt,
            withdraw,
            amtPerSec,
            dripsFraction,
            updatedReceivers
        );
        _transfer(msg.sender, withdrawn);
    }

    /// @notice Updates all the parameters of a sub-sender of the sender of the message.
    /// See `updateSender` for more details
    /// @param subSenderId The id of the sender's sub-sender
    function updateSubSender(
        uint256 subSenderId,
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public payable virtual returns (uint128 withdrawn) {
        _transferToContract(msg.sender, topUpAmt);
        withdrawn = _updateSubSenderInternal(
            msg.sender,
            subSenderId,
            topUpAmt,
            withdraw,
            amtPerSec,
            updatedReceivers
        );
        _transfer(msg.sender, withdrawn);
    }

    function _transferToContract(address from, uint128 amt) internal {
        if (amt != 0) erc20.transferFrom(from, address(this), amt);
    }

    function _transfer(address to, uint128 amt) internal override {
        if (amt != 0) erc20.transfer(to, amt);
    }
}
