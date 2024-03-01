// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import "./IDrips.sol";

/// @notice A Drips driver implementing immutable splits configurations.
/// Anybody can create a new account ID and configure its splits configuration,
/// but nobody can update its configuration afterwards, it's immutable.
/// This driver doesn't allow collecting funds for account IDs it manages, but anybody
/// can receive streams and split for them on Drips, which is enough because the splits
/// configurations always give away 100% funds, so there's never anything left to collect.
interface IImmutableSplitsDriver {
    /// @notice The Drips address used by this driver.
    /// @return drips_ The Drips address.
    function drips() external view returns (IDrips drips_);

    /// @notice The driver ID which this driver uses when calling Drips.
    /// @return driverId_ The driver ID.
    function driverId() external view returns (uint32 driverId_);

    /// @notice Emitted when an immutable splits configuration is created.
    /// @param accountId The account ID.
    /// @param receiversHash The splits receivers list hash
    event CreatedSplits(uint256 indexed accountId, bytes32 indexed receiversHash);

    /// @notice The ID of the next account to be created.
    /// Every account ID is a 256-bit integer constructed by concatenating:
    /// `driverId (32 bits) | accountIdsCounter (224 bits)`.
    /// @return accountId The account ID.
    function nextAccountId() external view returns (uint256 accountId);

    /// @notice Creates a new account ID, configures its
    /// splits configuration and emits its metadata.
    /// The configuration is immutable and nobody can control the account ID after its creation.
    /// Calling this function is the only way and the only chance to emit metadata for that account.
    /// @param receivers The list of the account's splits receivers to be set.
    /// Must be sorted by the account IDs, without duplicate account IDs and without 0 weights.
    /// Each splits receiver will be getting `weight / DripsLib.TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the account.
    /// Fractions of tokens are always rounded either up or down depending on the amount
    /// being split, the receiver's position on the list and the other receivers' weights.
    /// The sum of the receivers' weights must be equal to `DripsLib.TOTAL_SPLITS_WEIGHT`,
    /// or in other words the configuration must be splitting 100% of received funds.
    /// @param accountMetadata The list of account metadata to emit for the created account.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return accountId The new account ID with `receivers` configured.
    function createSplits(
        SplitsReceiver[] calldata receivers,
        AccountMetadata[] calldata accountMetadata
    ) external returns (uint256 accountId);
}
