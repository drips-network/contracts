// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {SplitsReceiver, DripsReceiver} from "./DripsHub.sol";
import {ManagedDripsHub} from "./ManagedDripsHub.sol";
import {IERC20Reserve} from "./ERC20Reserve.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice Drips hub contract for any ERC-20 token. Must be used via a proxy.
/// See the base `DripsHub` and `ManagedDripsHub` contract docs for more details.
contract ERC20DripsHub is ManagedDripsHub {
    /// @notice The address of the ERC-20 contract which tokens the drips hub works with
    IERC20 public immutable erc20;
    /// @notice The address of the reserve to store funds
    IERC20Reserve public reserve;

    /// @notice Emitted when the reserve address is set
    event ReserveSet(IERC20Reserve oldReserve, IERC20Reserve newReserve);

    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being collectable by their receivers.
    /// High value makes collecting cheaper by making it process less cycles for a given time range.
    /// @param _erc20 The address of an ERC-20 contract which tokens the drips hub will work with.
    constructor(uint64 cycleSecs, IERC20 _erc20) ManagedDripsHub(cycleSecs) {
        erc20 = _erc20;
    }

    /// @notice Sets the drips configuration of the `msg.sender`.
    /// Transfers funds to or from the sender to fulfill the update of the drips balance.
    /// The sender must first grant the contract a sufficient allowance.
    /// @param lastUpdate The timestamp of the last drips update of the `msg.sender`.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update of the `msg.sender`.
    /// If this is the first update, pass zero.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the `msg.sender`.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the `msg.sender` to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the `msg.sender`.
    /// Pass it as `lastBalance` when updating that user or the account for the next time.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) public whenNotPaused returns (uint128 newBalance, int128 realBalanceDelta) {
        return
            _setDrips(
                _userOrAccount(msg.sender),
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
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
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) public whenNotPaused returns (uint128 newBalance, int128 realBalanceDelta) {
        return
            _setDrips(
                _userOrAccount(msg.sender, account),
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    /// @notice Gives funds from the `msg.sender` to the receiver.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the sender's wallet to the drips hub contract.
    /// @param receiver The receiver
    /// @param amt The given amount
    function give(address receiver, uint128 amt) public whenNotPaused {
        _give(_userOrAccount(msg.sender), receiver, amt);
    }

    /// @notice Gives funds from the account of the `msg.sender` to the receiver.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the sender's wallet to the drips hub contract.
    /// @param account The account
    /// @param receiver The receiver
    /// @param amt The given amount
    function give(
        uint256 account,
        address receiver,
        uint128 amt
    ) public whenNotPaused {
        _give(_userOrAccount(msg.sender, account), receiver, amt);
    }

    /// @notice Collects funds received by the `msg.sender` and sets their splits.
    /// The collected funds are split according to `currReceivers`.
    /// @param currReceivers The list of the user's splits receivers which is currently in use.
    /// If this function is called for the first time for the user, should be an empty array.
    /// @param newReceivers The new list of the user's splits receivers.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    /// @return collected The collected amount
    /// @return split The amount split to the user's splits receivers
    function setSplits(SplitsReceiver[] memory currReceivers, SplitsReceiver[] memory newReceivers)
        public
        whenNotPaused
        returns (uint128 collected, uint128 split)
    {
        return _setSplits(msg.sender, currReceivers, newReceivers);
    }

    /// @notice Set the new reserve address.
    /// @param newReserve The new reserve.
    function setReserve(IERC20Reserve newReserve) public onlyAdmin {
        require(newReserve.erc20() == erc20, "Invalid reserve ERC-20 address");
        IERC20Reserve oldReserve = reserve;
        if (address(oldReserve) != address(0)) erc20.approve(address(oldReserve), 0);
        reserve = newReserve;
        erc20.approve(address(newReserve), type(uint256).max);
        emit ReserveSet(oldReserve, newReserve);
    }

    function _transfer(address user, int128 amt) internal override {
        if (amt > 0) {
            uint256 withdraw = uint128(amt);
            reserve.withdraw(withdraw);
            erc20.transfer(user, withdraw);
        } else if (amt < 0) {
            uint256 deposit = uint128(-amt);
            erc20.transferFrom(user, address(this), deposit);
            reserve.deposit(deposit);
        }
    }
}
