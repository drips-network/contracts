// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Upgradeable} from "./Upgradeable.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";

/// @notice A mix-in for contract pauseability and upgradeability.
/// It can't be used directly, only via a proxy. It uses the upgrade-safe ERC-1967 storage scheme.
///
/// All instances of the contracts are paused and can't be unpaused.
/// When a proxy uses such contract via delegation, it's initially unpaused.
abstract contract Managed is Upgradeable {
    /// @notice The pointer to the storage slot with the boolean holding the paused state.
    bytes32 private immutable pausedSlot = erc1967Slot("eip1967.managed.paused");

    /// @notice Emitted when the pause is triggered.
    /// @param caller The caller who triggered the change.
    event Paused(address caller);

    /// @notice Emitted when the pause is lifted.
    /// @param caller The caller who triggered the change.
    event Unpaused(address caller);

    /// @notice Modifier to make a function callable only when the contract is not paused.
    modifier whenNotPaused() {
        require(!paused(), "Contract paused");
        _;
    }

    /// @notice Modifier to make a function callable only when the contract is paused.
    modifier whenPaused() {
        require(paused(), "Contract not paused");
        _;
    }

    /// @notice Initializes the contract in paused state and with no admin.
    /// The contract instance can be used only as a call delegation target for a proxy.
    constructor() {
        _pausedSlot().value = true;
    }

    /// @notice Returns true if the contract is paused, and false otherwise.
    function paused() public view returns (bool isPaused) {
        return _pausedSlot().value;
    }

    /// @notice Triggers stopped state.
    function pause() public onlyAdmin whenNotPaused {
        _pausedSlot().value = true;
        emit Paused(msg.sender);
    }

    /// @notice Returns to normal state.
    function unpause() public onlyAdmin whenPaused {
        _pausedSlot().value = false;
        emit Unpaused(msg.sender);
    }

    function _pausedSlot() private view returns (StorageSlot.BooleanSlot storage slot) {
        return StorageSlot.getBooleanSlot(pausedSlot);
    }
}
