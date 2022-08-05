// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {DripsHub, DripsReceiver, IERC20, SplitsReceiver} from "./DripsHub.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice A DripsHub app implementing address-based user identification.
/// Each address can use `AddressApp` to control a user ID equal to that address.
/// No registration is required, an `AddressApp`-based user ID for each address is know upfront.
///
/// This app allows calling `collect` for any other address,
/// e.g. address `0x...A` can call `collect` for address `0x...B` and `0x...B`
/// will receive a transfer with funds dripped or split to `0x...B`'s user ID.
contract AddressApp {
    using SafeERC20 for IERC20;

    DripsHub public immutable dripsHub;
    address public immutable reserve;
    uint32 public immutable appId;

    /// @param _dripsHub The drips hub to use
    constructor(DripsHub _dripsHub) {
        dripsHub = _dripsHub;
        reserve = address(_dripsHub.reserve());
        appId = _dripsHub.registerApp(address(this));
    }

    /// @notice Calculates the user ID for an address
    /// @param userAddr The user address
    /// @return userId The user ID
    function calcUserId(address userAddr) public view returns (uint256 userId) {
        return (uint256(appId) << 224) | uint160(userAddr);
    }

    /// @notice Collects all received funds available for the user
    /// and transfers them out of the drips hub contract to that user.
    /// @param erc20 The token to use
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectedAmt The collected amount
    /// @return splitAmt The amount split to the user's splits receivers
    function collectAll(
        address user,
        IERC20 erc20,
        SplitsReceiver[] calldata currReceivers
    ) public returns (uint128 collectedAmt, uint128 splitAmt) {
        (collectedAmt, splitAmt) = dripsHub.collectAll(calcUserId(user), erc20, currReceivers);
        erc20.safeTransfer(user, collectedAmt);
    }

    /// @notice Collects the user's received already split funds
    /// and transfers them out of the drips hub contract to that user.
    /// @param erc20 The token to use
    /// @return amt The collected amount
    function collect(address user, IERC20 erc20) public returns (uint128 amt) {
        amt = dripsHub.collect(calcUserId(user), erc20);
        erc20.safeTransfer(user, amt);
    }

    /// @notice Gives funds from the msg.sender to the receiver.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the msg.sender's wallet to the drips hub contract.
    /// @param receiver The receiver
    /// @param erc20 The token to use
    /// @param amt The given amount
    function give(
        uint256 receiver,
        IERC20 erc20,
        uint128 amt
    ) public {
        _transferFromCaller(erc20, amt);
        dripsHub.give(calcUserId(msg.sender), receiver, erc20, amt);
    }

    /// @notice Sets the msg.sender's drips configuration.
    /// Transfers funds between the msg.sender's wallet and the drips hub contract
    /// to fulfill the change of the drips balance.
    /// @param erc20 The token to use
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the sender.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the sender to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the sender.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        IERC20 erc20,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) _transferFromCaller(erc20, uint128(balanceDelta));
        (newBalance, realBalanceDelta) = dripsHub.setDrips(
            calcUserId(msg.sender),
            erc20,
            currReceivers,
            balanceDelta,
            newReceivers
        );
        if (realBalanceDelta < 0) erc20.safeTransfer(msg.sender, uint128(-realBalanceDelta));
    }

    /// @notice Sets msg.sender's splits configuration.
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    function setSplits(SplitsReceiver[] calldata receivers) public {
        dripsHub.setSplits(calcUserId(msg.sender), receivers);
    }

    function _transferFromCaller(IERC20 erc20, uint128 amt) internal {
        erc20.safeTransferFrom(msg.sender, address(this), amt);
        if (erc20.allowance(address(this), reserve) < amt) {
            erc20.approve(reserve, type(uint256).max);
        }
    }
}
