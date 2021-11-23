// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {SplitsReceiver, DripsHub, Receiver} from "./DripsHub.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice Drips hub contract for any ERC-20 token.
/// See the base `DripsHub` contract docs for more details.
contract ERC20DripsHub is DripsHub {
    /// @notice The address of the ERC-20 contract which tokens the drips hub works with
    IERC20 public immutable erc20;

    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low values make funds more available by shortening the average duration of tokens being
    /// frozen between being taken from senders' balances and being collectable by the receiver.
    /// High values make collecting cheaper by making it process less cycles for a given time range.
    /// @param _erc20 The address of an ERC-20 contract which tokens the drips hub will work with.
    /// To guarantee safety the supply of the tokens must be lower than `2 ^ 127`.
    constructor(uint64 cycleSecs, IERC20 _erc20) DripsHub(cycleSecs) {
        erc20 = _erc20;
    }

    /// @notice Updates all the sender parameters of the sender of the message.
    /// Transfers funds to or from the sender to fulfill the update of the balance.
    /// The sender must first grant the contract a sufficient allowance.
    /// @param lastUpdate The timestamp of the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param lastBalance The balance after the last update of the sender.
    /// If this is the first update of the sender, pass zero.
    /// @param currReceivers The list of receivers set in the last update of the sender.
    /// If this is the first update of the sender, pass an empty array.
    /// @param balanceDelta The sender balance change to be applied.
    /// Positive to add funds to the sender balance, negative to remove them.
    /// @param newReceivers The new list of the sender's receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new sender balance.
    /// Pass it as `lastBalance` when updating the user for the next time.
    /// @return realBalanceDelta The actually applied balance change.
    function updateSender(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public returns (uint128 newBalance, int128 realBalanceDelta) {
        return
            _updateSender(
                _userOrAccount(msg.sender),
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    /// @notice Updates all the parameters of an account of the sender of the message.
    /// See `updateSender` for more details
    /// @param account The sender's account
    function updateSender(
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public payable returns (uint128 newBalance, int128 realBalanceDelta) {
        return
            _updateSender(
                _userOrAccount(msg.sender, account),
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    /// @notice Gives funds from the sender of the message to the receiver.
    /// The receiver can collect them immediately.
    /// @param receiver The receiver
    /// @param amt The sent amount
    function give(address receiver, uint128 amt) public {
        _give(_userOrAccount(msg.sender), receiver, amt);
    }

    /// @notice Gives funds from the account of the sender of the message to the receiver.
    /// The receiver can collect them immediately.
    /// @param account The user's account
    /// @param receiver The receiver
    /// @param amt The given amount
    function give(
        uint256 account,
        address receiver,
        uint128 amt
    ) public {
        _give(_userOrAccount(msg.sender, account), receiver, amt);
    }

    /// @notice Collects funds received by the sender of the message and sets their splits.
    /// The collected funds are split according to `currReceivers`.
    /// @param currReceivers The list of the user's splits receivers which is currently in use.
    /// If this function is called for the first time for the user, should be an empty array.
    /// @param newReceivers The new list of the user's splits receivers.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    /// @return collected The collected amount
    /// @return split The amount split to the user's splits receivers
    function setSplits(
        SplitsReceiver[] calldata currReceivers,
        SplitsReceiver[] calldata newReceivers
    ) public returns (uint128 collected, uint128 split) {
        return _setSplits(msg.sender, currReceivers, newReceivers);
    }

    function _transfer(address user, int128 amt) internal override {
        if (amt > 0) erc20.transfer(user, uint128(amt));
        else if (amt < 0) erc20.transferFrom(user, address(this), uint128(-amt));
    }
}
