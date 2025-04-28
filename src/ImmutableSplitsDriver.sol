// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {AccountMetadata, Drips, IERC20, SplitsReceiver} from "./Drips.sol";
import {Managed} from "./Managed.sol";

/// @notice A Drips driver implementing immutable splits configurations.
/// Anybody can create a new account ID and configure its splits configuration,
/// but nobody can update its configuration afterwards, it's immutable.
/// This driver doesn't allow collecting funds for account IDs it manages, but anybody
/// can receive streams and split for them on Drips, which is enough because the splits
/// configurations always give away 100% funds, so there's never anything left to collect.
contract ImmutableSplitsDriver is Managed {
    /// @notice The Drips address used by this driver.
    Drips public immutable drips;
    /// @notice The driver ID which this driver uses when calling Drips.
    uint32 public immutable driverId;
    /// @notice The required total splits weight of each splits configuration
    uint32 public immutable totalSplitsWeight;

    /// @notice Emitted when an immutable splits configuration is created.
    /// @param accountId The account ID.
    /// @param receiversHash The splits receivers list hash
    event CreatedSplits(uint256 indexed accountId, bytes32 indexed receiversHash);

    /// @param _drips The Drips contract to use.
    /// @param _driverId The driver ID to use when calling Drips.
    constructor(Drips _drips, uint32 _driverId) {
        drips = _drips;
        driverId = _driverId;
        totalSplitsWeight = _drips.TOTAL_SPLITS_WEIGHT();
    }

    /// @notice Calculates the account ID.
    /// Every account ID is a 256-bit integer constructed by concatenating:
    /// `driverId (32 bits) | hash (224 bits)`.
    /// `hash` is the lower 28 bytes of the hash
    /// of the abi-encoded `receivers` and `accountMetadata`.
    /// @param receivers The list of the account's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / totalSplitsWeight`
    /// share of the funds collected by the account.
    /// The sum of the receivers' weights must be equal to `totalSplitsWeight`,
    /// or in other words the configuration must be splitting 100% of received funds.
    /// @param accountMetadata The list of account metadata to emit for the created account.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return accountId The account ID.
    function calcAccountId(
        SplitsReceiver[] calldata receivers,
        AccountMetadata[] calldata accountMetadata
    ) public view returns (uint256 accountId) {
        uint224 hash = uint224(uint256(keccak256(abi.encode(receivers, accountMetadata))));
        // By bit shifting we get `accountId` value:
        // `driverId (32 bits) | zeros (224 bits)`
        // By bit masking we get `accountId` value:
        // `driverId (32 bits) | hash (224 bits)`
        accountId = (uint256(driverId) << 224) | hash;
    }

    /// @notice Creates a new account ID, configures its
    /// splits configuration and emits its metadata.
    /// The configuration is immutable and nobody can control the account ID after its creation.
    /// Calling this function is the only way and the only chance to emit metadata for that account.
    /// @param receivers The list of the account's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / totalSplitsWeight`
    /// share of the funds collected by the account.
    /// The sum of the receivers' weights must be equal to `totalSplitsWeight`,
    /// or in other words the configuration must be splitting 100% of received funds.
    /// @param accountMetadata The list of account metadata to emit for the created account.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return accountId The new account ID with `receivers` configured.
    function createSplits(
        SplitsReceiver[] calldata receivers,
        AccountMetadata[] calldata accountMetadata
    ) public whenNotPaused returns (uint256 accountId) {
        accountId = calcAccountId(receivers, accountMetadata);
        if (drips.splitsHash(accountId) != 0) return accountId;
        uint256 weightSum = 0;
        unchecked {
            for (uint256 i = 0; i < receivers.length; i++) {
                weightSum += receivers[i].weight;
            }
        }
        require(weightSum == totalSplitsWeight, "Invalid total receivers weight");
        emit CreatedSplits(accountId, drips.hashSplits(receivers));
        drips.setSplits(accountId, receivers);
        if (accountMetadata.length > 0) drips.emitAccountMetadata(accountId, accountMetadata);
    }

    /// @notice Collects all funds collectible by the account and gives them to the account itself.
    /// This is only needed if there are funds that have been split
    /// for the account before `createSplits` set the account's splits receivers.
    /// In such case funds haven't been split according to the account's
    /// immutable split list, but instead they have been made collectible.
    /// Calling this function makes such funds splittable again.
    /// @param accountId The account ID.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @return amt The collected and given amount.
    function collectAndGiveToSelf(uint256 accountId, IERC20 erc20)
        public
        whenNotPaused
        returns (uint128 amt)
    {
        if (drips.collectable(accountId, erc20) == 0) return 0;
        amt = drips.collect(accountId, erc20);
        drips.give(accountId, accountId, erc20, amt);
    }
}
