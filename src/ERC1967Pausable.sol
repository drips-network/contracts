// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";

/// @notice The proxy-safe pausability mix-in.
/// Only the owner can pause or unpause the contract.
/// It's supposed to be used only in contracts behind a proxy.
///
/// This contract uses a custom ERC-1967 slot to store its state.
/// All instances of `ERC1967Pausable` contracts are paused and can't be unpaused.
/// When a proxy uses such contract via delegation, it's initially unpaused.
abstract contract ERC1967Pausable {
    /// @notice The ERC-1967 storage slot for the contract.
    /// It holds a single boolean indicating if the contract is paused.
    bytes32 private constant SLOT = bytes32(uint256(keccak256("eip1967.erc1967Pausable")) - 1);

    /// @notice Emitted when the pause is triggered.
    /// @param account The account which triggered the change.
    event Paused(address account);

    /// @notice Emitted when the pause is lifted.
    /// @param account The account which triggered the change.
    event Unpaused(address account);

    /// @notice Initializes the contract in paused state.
    constructor() {
        _setPaused(true);
    }

    /// @notice Returns true if the contract is paused, and false otherwise.
    function paused() public view returns (bool isPaused) {
        return pausedSlot().value;
    }

    /// @notice Modifier to make a function callable only when the contract is not paused.
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /// @notice Modifier to make a function callable only when the contract is paused.
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /// @notice Triggers stopped state.
    function pause() public virtual whenNotPaused {
        _setPaused(true);
        emit Paused(msg.sender);
    }

    /// @notice Returns to normal state.
    function unpause() public virtual whenPaused {
        _setPaused(false);
        emit Unpaused(msg.sender);
    }

    /// @notice Gets the storage slot holding the paused flag.
    function pausedSlot() private pure returns (StorageSlot.BooleanSlot storage) {
        return StorageSlot.getBooleanSlot(SLOT);
    }

    function _setPaused(bool isPaused) internal {
        pausedSlot().value = isPaused;
    }
}
