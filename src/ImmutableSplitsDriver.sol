// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {DripsHub, SplitsReceiver, UserMetadata} from "./DripsHub.sol";
import {Managed} from "./Managed.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";

/// @notice A DripsHub driver implementing immutable splits configurations.
/// Anybody can create a new user ID and configure its splits configuration,
/// but nobody can update its configuration afterwards, it's immutable.
/// This driver doesn't allow collecting funds for user IDs it manages, but anybody
/// can receive drips and split for them on DripsHub, which is enough because the splits
/// configurations always give away 100% funds, so there's never anything left to collect.
contract ImmutableSplitsDriver is Managed {
    /// @notice The DripsHub address used by this driver.
    DripsHub public immutable dripsHub;
    /// @notice The driver ID which this driver uses when calling DripsHub.
    uint32 public immutable driverId;
    /// @notice The required total splits weight of each splits configuration
    uint32 public immutable totalSplitsWeight;
    /// @notice The ERC-1967 storage slot holding a single `uint256` counter of created identities.
    bytes32 private immutable _counterSlot = _erc1967Slot("eip1967.immutableSplitsDriver.storage");

    /// @notice Emitted when an immutable splits configuration is created.
    /// @param userId The user ID
    /// @param receiversHash The splits receivers list hash
    event CreatedSplits(uint256 indexed userId, bytes32 indexed receiversHash);

    /// @param _dripsHub The drips hub to use.
    /// @param _driverId The driver ID to use when calling DripsHub.
    constructor(DripsHub _dripsHub, uint32 _driverId) {
        dripsHub = _dripsHub;
        driverId = _driverId;
        totalSplitsWeight = _dripsHub.TOTAL_SPLITS_WEIGHT();
    }

    /// @notice The ID of the next user to be created.
    /// Every user ID is a 256-bit integer constructed by concatenating:
    /// `driverId (32 bits) | userIdsCounter (224 bits)`.
    /// @return userId The user ID.
    function nextUserId() public view returns (uint256 userId) {
        // By assignment we get `userId` value:
        // `zeros (224 bits) | driverId (32 bits)`
        userId = driverId;
        // By bit shifting we get `userId` value:
        // `driverId (32 bits) | zeros (224 bits)`
        // By bit masking we get `userId` value:
        // `driverId (32 bits) | userIdsCounter (224 bits)`
        // We can treat that the counter is a 224 bit value without explicit casting
        // because there will never be 2^224 user IDs registered.
        userId = (userId << 224) | StorageSlot.getUint256Slot(_counterSlot).value;
    }

    /// @notice Creates a new user ID, configures its splits configuration and emits its metadata.
    /// The configuration is immutable and nobody can control the user ID after its creation.
    /// Calling this function is the only way and the only chance to emit metadata for that user.
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / totalSplitsWeight`
    /// share of the funds collected by the user.
    /// The sum of the receivers' weights must be equal to `totalSplitsWeight`,
    /// or in other words the configuration must be splitting 100% of received funds.
    /// @param userMetadata The list of user metadata to emit for the created user.
    /// The keys and the values are not standardized by the protocol, it's up to the user
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return userId The new user ID with `receivers` configured.
    function createSplits(SplitsReceiver[] calldata receivers, UserMetadata[] calldata userMetadata)
        public
        whenNotPaused
        returns (uint256 userId)
    {
        userId = nextUserId();
        StorageSlot.getUint256Slot(_counterSlot).value++;
        uint256 weightSum = 0;
        unchecked {
            for (uint256 i = 0; i < receivers.length; i++) {
                weightSum += receivers[i].weight;
            }
        }
        require(weightSum == totalSplitsWeight, "Invalid total receivers weight");
        emit CreatedSplits(userId, dripsHub.hashSplits(receivers));
        dripsHub.setSplits(userId, receivers);
        if (userMetadata.length > 0) dripsHub.emitUserMetadata(userId, userMetadata);
    }
}
