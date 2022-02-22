// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {SplitsReceiver, DripsReceiver} from "./DripsHub.sol";
import {ManagedDripsHub} from "./ManagedDripsHub.sol";

/// @notice Drips hub contract for Ether. Must be used via a proxy.
/// See the base `DripsHub` contract docs for more details.
contract EthDripsHub is ManagedDripsHub {
    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being collectable by their receivers.
    /// High value makes collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 cycleSecs) ManagedDripsHub(cycleSecs) {
        return;
    }

    /// @notice Sets the drips configuration of the `msg.sender`.
    /// Increases the drips balance with the value of the message.
    /// Transfers the reduced drips balance to the `msg.sender`.
    /// @param lastUpdate The timestamp of the last drips update of the `msg.sender`.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update of the `msg.sender`.
    /// If this is the first update, pass zero.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the `msg.sender`.
    /// If this is the first update, pass an empty array.
    /// @param reduceBalance The drips balance reduction to be applied.
    /// If more than 0, the message value must be 0.
    /// @param newReceivers The list of the drips receivers of the `msg.sender` to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the `msg.sender`.
    /// Pass it as `lastBalance` when updating that user or the account for the next time.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        uint128 reduceBalance,
        DripsReceiver[] memory newReceivers
    ) public payable whenNotPaused returns (uint128 newBalance, int128 realBalanceDelta) {
        return
            _setDrips(
                _userOrAccount(msg.sender),
                lastUpdate,
                lastBalance,
                currReceivers,
                _balanceDelta(reduceBalance),
                newReceivers
            );
    }

    /// @notice Sets the drips configuration of an account of the `msg.sender`.
    /// See `setDrips` for more details
    /// @param account The account
    function setDrips(
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        uint128 reduceBalance,
        DripsReceiver[] memory newReceivers
    ) public payable whenNotPaused returns (uint128 newBalance, int128 realBalanceDelta) {
        return
            _setDrips(
                _userOrAccount(msg.sender, account),
                lastUpdate,
                lastBalance,
                currReceivers,
                _balanceDelta(reduceBalance),
                newReceivers
            );
    }

    /// @notice Calculates the balance delta from the reduced balance and msg.value.
    /// Reverts if both
    function _balanceDelta(uint128 reduceBalance) internal view returns (int128 balanceDelta) {
        if (reduceBalance == 0) return int128(int256(msg.value));
        require(msg.value == 0, "Both message value and balance reduction non-zero");
        if (reduceBalance > uint128(type(int128).max)) return type(int128).min;
        return -int128(reduceBalance);
    }

    /// @notice Gives funds from the `msg.sender` to the receiver.
    /// The receiver can collect them immediately.
    /// The funds to be given must be the value of the message.
    /// @param receiver The receiver
    function give(address receiver) public payable whenNotPaused {
        _give(_userOrAccount(msg.sender), receiver, uint128(msg.value));
    }

    /// @notice Gives funds from the account of the `msg.sender` to the receiver.
    /// The receiver can collect them immediately.
    /// The funds to be given must be the value of the message.
    /// @param account The user's account
    /// @param receiver The receiver
    function give(uint256 account, address receiver) public payable whenNotPaused {
        _give(_userOrAccount(msg.sender, account), receiver, uint128(msg.value));
    }

    /// @notice Sets user splits configuration.
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    function setSplits(SplitsReceiver[] memory receivers) public whenNotPaused {
        _setSplits(msg.sender, receivers);
    }

    function _transfer(address user, int128 amt) internal override {
        // Take into account the amount already transferred into the drips hub
        amt += int128(uint128(msg.value));
        if (amt == 0) return;
        require(amt > 0, "Transferring a negative ether amount");
        payable(user).transfer(uint128(amt));
    }
}
