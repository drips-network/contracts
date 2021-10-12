// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {Pool, Receiver} from "./Pool.sol";
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

    /// @notice Collects received funds and updates all the sender parameters
    //// of the sender of the message.
    ///
    /// Tops up and withdraws unsent funds from the balance of the sender.
    /// The sender must first grant the contract a sufficient allowance to top up.
    /// Sends the withdrawn funds to the sender of the message.
    /// @param topUpAmt The topped up amount
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
        uint128 topUpAmt,
        uint128 withdraw,
        uint32 dripsFraction,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    )
        public
        returns (
            uint128 withdrawn,
            uint128 collected,
            uint128 dripped
        )
    {
        return
            _updateSenderInternal(
                msg.sender,
                topUpAmt,
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
        uint128 topUpAmt,
        uint128 withdraw,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) public payable returns (uint128 withdrawn) {
        return
            _updateSubSenderInternal(
                msg.sender,
                subSenderId,
                topUpAmt,
                withdraw,
                currReceivers,
                newReceivers
            );
    }

    /// @notice Gives funds from the sender of the message to the receiver.
    /// The receiver can collect them immediately.
    /// @param receiver The receiver
    /// @param amt The sent amount
    function give(address receiver, uint128 amt) public {
        _giveInternal(msg.sender, receiver, amt);
    }

    /// @notice Gives funds from the sub-sender of the sender of the message to the receiver.
    /// The receiver can collect them immediately.
    /// @param subSenderId The ID of the sub-sender
    /// @param receiver The receiver
    /// @param amt The given amount
    function giveFromSubSender(
        uint256 subSenderId,
        address receiver,
        uint128 amt
    ) public {
        _giveFromSubSenderInternal(msg.sender, subSenderId, receiver, amt);
    }

    function _transfer(address userAddr, int128 amt) internal override {
        if (amt > 0) erc20.transfer(userAddr, uint128(amt));
        else if (amt < 0) erc20.transferFrom(userAddr, address(this), uint128(-amt));
    }
}
