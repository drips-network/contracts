// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Upgradeable} from "./Upgradeable.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

using EnumerableSet for EnumerableSet.AddressSet;

/// @notice A mix-in for contract pauseability and upgradeability.
/// It can't be used directly, only via a proxy. It uses the upgrade-safe ERC-1967 storage scheme.
///
/// All instances of the contracts are paused and can't be unpaused.
/// When a proxy uses such contract via delegation, it's initially unpaused.
abstract contract Managed is Upgradeable {
    /// @notice The pointer to the storage slot holding a single `ManagedStorage` structure.
    bytes32 private immutable _storageSlot = erc1967Slot("eip1967.managed.storage");

    /// @notice Emitted when the pauses role is granted.
    /// @param pauser The address that the pauser role was granted to.
    /// @param admin The address of the admin that triggered the change.
    event PauserGranted(address indexed pauser, address admin);

    /// @notice Emitted when the pauses role is revoked.
    /// @param pauser The address that the pauser role was revoked from.
    /// @param admin The address of the admin that triggered the change.
    event PauserRevoked(address indexed pauser, address admin);

    /// @notice Emitted when the pause is triggered.
    /// @param pauser The address that triggered the change.
    event Paused(address pauser);

    /// @notice Emitted when the pause is lifted.
    /// @param pauser The address that triggered the change.
    event Unpaused(address pauser);

    struct ManagedStorage {
        bool isPaused;
        EnumerableSet.AddressSet pausers;
    }

    /// @notice Throws if called by any caller other than the admin or a pauser.
    modifier onlyAdminOrPauser() {
        require(
            admin() == msg.sender || isPauser(msg.sender), "Caller is not the admin or a pauser"
        );
        _;
    }

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
        _managedStorage().isPaused = true;
    }

    /// @notice Grants the pauser role to an address. Callable only by the admin.
    /// @param pauser The granted address.
    function grantPauser(address pauser) public onlyAdmin {
        require(_managedStorage().pausers.add(pauser), "Address already is a pauser");
        emit PauserGranted(pauser, msg.sender);
    }

    /// @notice Revokes the pauser role from an address. Callable only by the admin.
    /// @param pauser The revoked address.
    function revokePauser(address pauser) public onlyAdmin {
        require(_managedStorage().pausers.remove(pauser), "Address is not a pauser");
        emit PauserRevoked(pauser, msg.sender);
    }

    /// @notice Checks if an address is a pauser.
    /// @param pauser The checked address.
    /// @return isAddrPauser True if the address is a pauser.
    function isPauser(address pauser) public view returns (bool isAddrPauser) {
        return _managedStorage().pausers.contains(pauser);
    }

    /// @notice Returns all the addresses with the pauser role.
    /// @return pausersList The list of all the pausers, ordered arbitrarily.
    /// The list's order may change after granting or revoking the pauser role.
    function allPausers() public view returns (address[] memory pausersList) {
        return _managedStorage().pausers.values();
    }

    /// @notice Returns true if the contract is paused, and false otherwise.
    function paused() public view returns (bool isPaused) {
        return _managedStorage().isPaused;
    }

    /// @notice Triggers stopped state. Callable only by the admin or a pauser.
    function pause() public onlyAdminOrPauser whenNotPaused {
        _managedStorage().isPaused = true;
        emit Paused(msg.sender);
    }

    /// @notice Returns to normal state. Callable only by the admin or a pauser.
    function unpause() public onlyAdminOrPauser whenPaused {
        _managedStorage().isPaused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Returns the Managed storage.
    /// @return storageRef The storage.
    function _managedStorage() internal view returns (ManagedStorage storage storageRef) {
        bytes32 slot = _storageSlot;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            storageRef.slot := slot
        }
    }
}
