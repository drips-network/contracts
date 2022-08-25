// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {DripsHub, DripsReceiver, SplitsReceiver} from "./DripsHub.sol";
import {Upgradeable} from "./Upgradeable.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Permit as IERC20Permit_} from
    "openzeppelin-contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

interface IERC20Permit is IERC20, IERC20Permit_ {}

/// @notice A DripsHub app implementing address-based user identification.
/// Each address can use `AddressApp` to control a user ID equal to that address.
/// No registration is required, an `AddressApp`-based user ID for each address is know upfront.
///
/// This app allows calling `collect` for any other address,
/// e.g. address `0x...A` can call `collect` for address `0x...B` and `0x...B`
/// will receive a transfer with funds dripped or split to `0x...B`'s user ID.
contract AddressApp is Upgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Permit;

    DripsHub public immutable dripsHub;
    uint32 public immutable appId;

    /// @param _dripsHub The drips hub to use
    constructor(DripsHub _dripsHub, uint32 _appId) {
        dripsHub = _dripsHub;
        appId = _appId;
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
    function collectAll(address user, IERC20 erc20, SplitsReceiver[] calldata currReceivers)
        public
        returns (uint128 collectedAmt, uint128 splitAmt)
    {
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
    function give(uint256 receiver, IERC20 erc20, uint128 amt) public {
        _transferFrom(msg.sender, erc20, amt);
        dripsHub.give(calcUserId(msg.sender), receiver, erc20, amt);
    }

    /// @notice Gives funds from the user to the receiver with an eip-2612 permit signature.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the msg.sender's wallet to the drips hub contract.
    /// @param receiver The receiver.
    /// @param erc20 The token to use.
    /// @param amt The given amount.
    /// @param user The user address.
    /// @param deadline A deadline for the permit.
    /// @param v secp256k1 signature
    /// @param r secp256k1 signature
    /// @param s secp256k1 signature
    function give(
        uint256 receiver,
        IERC20Permit erc20,
        uint128 amt,
        address user,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
    {
        _transferFromPermit(user, erc20, amt, deadline, v, r, s);
        dripsHub.give(calcUserId(msg.sender), receiver, erc20, amt);
    }

    /// @notice Sets the msg.sender's drips configuration.
    /// Transfers funds between the msg.sender's wallet and the drips hub contract
    /// to fulfill the change of the drips balance.
    /// @param erc20 The token to use.
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
    )
        public
        returns (uint128 newBalance, int128 realBalanceDelta)
    {
        if (balanceDelta > 0) {
            _transferFrom(msg.sender, erc20, uint128(balanceDelta));
        }
        (newBalance, realBalanceDelta) =
            dripsHub.setDrips(calcUserId(msg.sender), erc20, currReceivers, balanceDelta, newReceivers);
        if (realBalanceDelta < 0) {
            erc20.safeTransfer(msg.sender, uint128(-realBalanceDelta));
        }
    }

    /// @notice Sets the user's drips configuration with an eip-2612 permit signature.
    /// Transfers funds between the msg.sender's wallet and the drips hub contract
    /// to fulfill the change of the drips balance.
    /// @param erc20 The token to use.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the sender.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the sender to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @param user The user address.
    /// @param deadline A deadline for the permit.
    /// @param v secp256k1 signature
    /// @param r secp256k1 signature
    /// @param s secp256k1 signature
    /// @return newBalance The new drips balance of the sender.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        IERC20Permit erc20,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers,
        address user,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        returns (uint128 newBalance, int128 realBalanceDelta)
    {
        if (balanceDelta > 0) {
            _transferFromPermit(user, erc20, uint128(balanceDelta), deadline, v, r, s);
        }
        (newBalance, realBalanceDelta) =
            dripsHub.setDrips(calcUserId(msg.sender), erc20, currReceivers, balanceDelta, newReceivers);
        if (realBalanceDelta < 0) {
            erc20.safeTransfer(msg.sender, uint128(-realBalanceDelta));
        }
    }
    /// @notice Sets msg.sender's splits configuration.
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.

    function setSplits(SplitsReceiver[] calldata receivers) public {
        dripsHub.setSplits(calcUserId(msg.sender), receivers);
    }

    function _transferFromPermit(
        address user,
        IERC20Permit erc20,
        uint128 amt,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        internal
    {
        erc20.safePermit(user, address(this), uint256(amt), deadline, v, r, s);
        _transferFrom(user, erc20, amt);
    }

    function _transferFrom(address user, IERC20 erc20, uint128 amt) internal {
        erc20.safeTransferFrom(user, address(this), amt);
        address reserve = address(dripsHub.reserve());
        // Approval is done only on the first usage of the ERC-20 token in the reserve by the app
        if (erc20.allowance(address(this), reserve) == 0) {
            erc20.approve(reserve, type(uint256).max);
        }
    }
}
