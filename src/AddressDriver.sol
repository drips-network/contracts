// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import "./IAddressDriver.sol";
import {Managed} from "./Managed.sol";
import {DriverTransferUtils} from "./DriverTransferUtils.sol";

/// @notice The implementation of `IAddressDriver`, see its documentation for more details.
contract AddressDriver is IAddressDriver, DriverTransferUtils, Managed {
    /// @inheritdoc IAddressDriver
    IDrips public immutable drips;
    /// @inheritdoc IAddressDriver
    uint32 public immutable driverId;

    /// @param drips_ The Drips contract to use.
    /// @param forwarder The ERC-2771 forwarder to trust. May be the zero address.
    /// @param driverId_ The driver ID to use when calling Drips.
    constructor(IDrips drips_, address forwarder, uint32 driverId_)
        DriverTransferUtils(forwarder)
    {
        drips = drips_;
        driverId = driverId_;
    }

    /// @inheritdoc IAddressDriver
    function calcAccountId(address addr) public view onlyProxy returns (uint256 accountId) {
        // By assignment we get `accountId` value:
        // `zeros (224 bits) | driverId (32 bits)`
        accountId = driverId;
        // By bit shifting we get `accountId` value:
        // `driverId (32 bits) | zeros (224 bits)`
        // By bit masking we get `accountId` value:
        // `driverId (32 bits) | zeros (64 bits) | addr (160 bits)`
        accountId = (accountId << 224) | uint160(addr);
    }

    /// @notice Calculates the account ID for the message sender
    /// @return accountId The account ID
    function _callerAccountId() internal view returns (uint256 accountId) {
        return calcAccountId(_msgSender());
    }

    /// @inheritdoc IAddressDriver
    function collect(IERC20 erc20, address transferTo) public onlyProxy returns (uint128 amt) {
        return _collectAndTransfer(drips, _callerAccountId(), erc20, transferTo);
    }

    /// @inheritdoc IAddressDriver
    function give(uint256 receiver, IERC20 erc20, uint128 amt) public onlyProxy {
        _giveAndTransfer(drips, _callerAccountId(), receiver, erc20, amt);
    }

    /// @inheritdoc IAddressDriver
    function setStreams(
        IERC20 erc20,
        StreamReceiver[] calldata currReceivers,
        int128 balanceDelta,
        StreamReceiver[] calldata newReceivers,
        MaxEndHints maxEndHints,
        address transferTo
    ) public onlyProxy returns (int128 realBalanceDelta) {
        return _setStreamsAndTransfer(
            drips,
            _callerAccountId(),
            erc20,
            currReceivers,
            balanceDelta,
            newReceivers,
            maxEndHints,
            transferTo
        );
    }

    /// @inheritdoc IAddressDriver
    function setSplits(SplitsReceiver[] calldata receivers) public onlyProxy {
        drips.setSplits(_callerAccountId(), receivers);
    }

    /// @inheritdoc IAddressDriver
    function emitAccountMetadata(AccountMetadata[] calldata accountMetadata) public onlyProxy {
        if (accountMetadata.length != 0) {
            drips.emitAccountMetadata(_callerAccountId(), accountMetadata);
        }
    }
}
