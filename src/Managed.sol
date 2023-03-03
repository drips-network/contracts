// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

using EnumerableSet for EnumerableSet.AddressSet;

/// @notice A mix-in for contract pausing, upgrading and admin management.
/// It can't be used directly, only via a proxy. It uses the upgrade-safe ERC-1967 storage scheme.
///
/// Managed uses the ERC-1967 admin slot to store the admin address.
/// All instances of the contracts have admin address `0x00` and are forever paused.
/// When a proxy uses such contract via delegation, the proxy should define
/// the initial admin address and the contract is initially unpaused.
abstract contract Managed is UUPSUpgradeable {
    /// @notice The pointer to the storage slot holding a single `ManagedStorage` structure.
    bytes32 private immutable _managedStorageSlot = _erc1967Slot("eip1967.managed.storage");

    /// @notice Emitted when the pauses role is granted.
    /// @param pauser The address that the pauser role was granted to.
    /// @param admin The address of the admin that triggered the change.
    event PauserGranted(address indexed pauser, address indexed admin);

    /// @notice Emitted when the pauses role is revoked.
    /// @param pauser The address that the pauser role was revoked from.
    /// @param admin The address of the admin that triggered the change.
    event PauserRevoked(address indexed pauser, address indexed admin);

    /// @notice Emitted when the pause is triggered.
    /// @param pauser The address that triggered the change.
    event Paused(address indexed pauser);

    /// @notice Emitted when the pause is lifted.
    /// @param pauser The address that triggered the change.
    event Unpaused(address indexed pauser);

    struct ManagedStorage {
        bool isPaused;
        EnumerableSet.AddressSet pausers;
    }

    /// @notice Throws if called by any caller other than the admin.
    modifier onlyAdmin() {
        require(admin() == msg.sender, "Caller not the admin");
        _;
    }

    /// @notice Throws if called by any caller other than the admin or a pauser.
    modifier onlyAdminOrPauser() {
        require(admin() == msg.sender || isPauser(msg.sender), "Caller not the admin or a pauser");
        _;
    }

    /// @notice Modifier to make a function callable only when the contract is not paused.
    modifier whenNotPaused() {
        require(!isPaused(), "Contract paused");
        _;
    }

    /// @notice Modifier to make a function callable only when the contract is paused.
    modifier whenPaused() {
        require(isPaused(), "Contract not paused");
        _;
    }

    /// @notice Initializes the contract in paused state and with no admin.
    /// The contract instance can be used only as a call delegation target for a proxy.
    constructor() {
        _managedStorage().isPaused = true;
    }

    /// @notice Returns the address of the current admin.
    function admin() public view returns (address) {
        return _getAdmin();
    }

    /// @notice Changes the admin of the contract.
    /// Can only be called by the current admin.
    function changeAdmin(address newAdmin) public onlyAdmin {
        _changeAdmin(newAdmin);
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
    function isPaused() public view returns (bool) {
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

    /// @notice Calculates the ERC-1967 slot pointer.
    /// @param name The name of the slot, should be globally unique
    /// @return slot The slot pointer
    function _erc1967Slot(string memory name) internal pure returns (bytes32 slot) {
        return bytes32(uint256(keccak256(bytes(name))) - 1);
    }

    /// @notice Returns the Managed storage.
    /// @return storageRef The storage.
    function _managedStorage() internal view returns (ManagedStorage storage storageRef) {
        bytes32 slot = _managedStorageSlot;
        // slither-disable-next-line assembly
        assembly {
            storageRef.slot := slot
        }
    }

    /// @notice Authorizes the contract upgrade. See `UUPSUpgradeable` docs for more details.
    function _authorizeUpgrade(address /* newImplementation */ ) internal view override onlyAdmin {
        return;
    }
}

/// @notice A generic proxy for contracts implementing `Managed`.
contract ManagedProxy is ERC1967Proxy {
    constructor(Managed logic, address admin) ERC1967Proxy(address(logic), new bytes(0)) {
        _changeAdmin(admin);
    }
}
