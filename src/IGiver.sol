// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {IAddressDriver, IERC20} from "./IAddressDriver.sol";

/// @notice Each Drips account ID has a single `Giver` contract assigned to it,
/// and each `Giver` has a single account ID assigned.
/// Any ERC-20 tokens or native tokens sent to `Giver` will
/// eventually be `give`n to the account assigned to it.
/// This contract should never be called directly, it can only be called by its owner.
/// For most practical purposes the address of a `Giver` should be treated like an EOA address.
interface IGiver {
    /// @notice The owner of this contract, allowed to call it.
    /// @return owner_ The owner.
    function owner() external view returns (address owner_);
}

/// @notice This contract deploys and calls `Giver` contracts.
/// Each Drips account ID has a single `Giver` contract assigned to it,
/// and each `Giver` has a single account ID assigned.
/// Any ERC-20 tokens or native tokens sent to `Giver` will
/// eventually be `give`n to the account assigned to it.
/// Giving will be performed with `AddressDriver` using the address of the `Giver`.
interface IGiversRegistry {
    /// @notice The ERC-20 contract used to wrap the native tokens before `give`ing.
    /// @return  nativeTokenWrapper_ The ERC-20 contract.
    function nativeTokenWrapper() external view returns (IERC20 nativeTokenWrapper_);

    /// @notice The AddressDriver to used to `give`.
    /// @return addressDriver_ The AddressDriver.
    function addressDriver() external view returns (IAddressDriver addressDriver_);

    /// @notice Calculate the address of the `Giver` assigned to the account ID.
    /// The `Giver` may not be deployed yet, but the tokens sent
    /// to its address will be `give`n when `give` is called.
    /// @param accountId The ID of the account to which the `Giver` is assigned.
    /// @return giver_ The address of the `Giver`.
    function giver(uint256 accountId) external view returns (address giver_);

    /// @notice `give` to the account all the tokens held by the `Giver` assigned to that account.
    /// @param accountId The ID of the account to `give` tokens to.
    /// @param erc20 The token to `give` to the account.
    /// If it's the zero address, `Giver` wraps all the native tokens it holds using
    /// `nativeTokenWrapper`, and then `give`s to the account all the wrapped tokens it holds.
    /// @param amt The amount of tokens that were `give`n.
    function give(uint256 accountId, IERC20 erc20) external returns (uint256 amt);
}
