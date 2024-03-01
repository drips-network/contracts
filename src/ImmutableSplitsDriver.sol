// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {DripsLib} from "./DripsLib.sol";
import "./IImmutableSplitsDriver.sol";
import {Managed, StorageSlot} from "./Managed.sol";

/// @notice The implementation of `IImmutableSplitsDriver`, see its documentation for more details.
contract ImmutableSplitsDriver is IImmutableSplitsDriver, Managed {
    /// @inheritdoc IImmutableSplitsDriver
    IDrips public immutable drips;
    /// @inheritdoc IImmutableSplitsDriver
    uint32 public immutable driverId;
    /// @notice The ERC-1967 storage slot holding a single `uint256` counter of created identities.
    bytes32 private immutable _counterSlot = _erc1967Slot("eip1967.immutableSplitsDriver.storage");

    /// @param _drips The Drips contract to use.
    /// @param _driverId The driver ID to use when calling Drips.
    constructor(IDrips _drips, uint32 _driverId) {
        drips = _drips;
        driverId = _driverId;
    }

    /// @inheritdoc IImmutableSplitsDriver
    function nextAccountId() public view onlyProxy returns (uint256 accountId) {
        // By assignment we get `accountId` value:
        // `zeros (224 bits) | driverId (32 bits)`
        accountId = driverId;
        // By bit shifting we get `accountId` value:
        // `driverId (32 bits) | zeros (224 bits)`
        // By bit masking we get `accountId` value:
        // `driverId (32 bits) | accountIdsCounter (224 bits)`
        // We can treat that the counter is a 224 bit value without explicit casting
        // because there will never be 2^224 account IDs registered.
        accountId = (accountId << 224) | StorageSlot.getUint256Slot(_counterSlot).value;
    }

    /// @inheritdoc IImmutableSplitsDriver
    function createSplits(
        SplitsReceiver[] calldata receivers,
        AccountMetadata[] calldata accountMetadata
    ) public onlyProxy returns (uint256 accountId) {
        accountId = nextAccountId();
        StorageSlot.getUint256Slot(_counterSlot).value++;
        uint256 weightSumTarget = DripsLib.TOTAL_SPLITS_WEIGHT;
        uint256 weightSum = 0;
        unchecked {
            for (uint256 i = 0; i < receivers.length; i++) {
                uint256 weight = receivers[i].weight;
                if (weight > weightSumTarget) weight = weightSumTarget + 1;
                weightSum += weight;
            }
        }
        require(weightSum == weightSumTarget, "Invalid total receivers weight");
        emit CreatedSplits(accountId, drips.hashSplits(receivers));
        drips.setSplits(accountId, receivers);
        if (accountMetadata.length != 0) drips.emitAccountMetadata(accountId, accountMetadata);
    }
}
