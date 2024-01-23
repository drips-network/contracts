// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";

/// @notice A mix-in for contract upgrading and admin management.
/// It can't be used directly, only via a proxy. It uses the upgrade-safe ERC-1967 storage scheme.
///
/// Managed uses the ERC-1967 admin slot to store the admin address.
/// All instances of the contracts have admin address `0x00`.
abstract contract Managed is UUPSUpgradeable {
    /// @notice The pointer to the storage slot holding the proposed admin.
    bytes32 private immutable _proposedAdminStorageSlot =
        _erc1967Slot("eip1967.managed.proposedAdmin");

    /// @notice Emitted when a new admin of the contract is proposed.
    /// The proposed admin must call `acceptAdmin` to finalize the change.
    /// @param currentAdmin The current admin address.
    /// @param newAdmin The proposed admin address.
    event NewAdminProposed(address indexed currentAdmin, address indexed newAdmin);

    /// @notice Throws if called by any caller other than the admin.
    modifier onlyAdmin() {
        require(admin() == msg.sender, "Caller not the admin");
        _;
    }

    /// @notice Returns the current implementation address.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Returns the address of the current admin.
    function admin() public view returns (address) {
        return _getAdmin();
    }

    /// @notice Returns the proposed address to change the admin to.
    function proposedAdmin() public view returns (address) {
        return _proposedAdmin().value;
    }

    /// @notice Proposes a change of the admin of the contract.
    /// The proposed new admin must call `acceptAdmin` to finalize the change.
    /// To cancel a proposal propose a different address, e.g. the zero address.
    /// Can only be called by the current admin.
    /// @param newAdmin The proposed admin address.
    function proposeNewAdmin(address newAdmin) public onlyAdmin {
        emit NewAdminProposed(msg.sender, newAdmin);
        _proposedAdmin().value = newAdmin;
    }

    /// @notice Applies a proposed change of the admin of the contract.
    /// Sets the proposed admin to the zero address.
    /// Can only be called by the proposed admin.
    function acceptAdmin() public {
        require(proposedAdmin() == msg.sender, "Caller not the proposed admin");
        _updateAdmin(msg.sender);
    }

    /// @notice Changes the admin of the contract to address zero.
    /// It's no longer possible to change the admin or upgrade the contract afterwards.
    /// Can only be called by the current admin.
    function renounceAdmin() public onlyAdmin {
        _updateAdmin(address(0));
    }

    /// @notice Sets the current admin of the contract and clears the proposed admin.
    /// @param newAdmin The admin address being set. Can be the zero address.
    function _updateAdmin(address newAdmin) internal {
        _proposedAdmin().value = address(0);
        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
        emit AdminChanged(admin(), newAdmin);
    }

    function _proposedAdmin() private view returns (StorageSlot.AddressSlot storage) {
        return StorageSlot.getAddressSlot(_proposedAdminStorageSlot);
    }

    /// @notice Calculates the quasi ERC-1967 slot pointer.
    /// @param name The name of the slot, should be globally unique
    /// @return slot The slot pointer
    function _erc1967Slot(string memory name) internal pure returns (bytes32 slot) {
        // The original ERC-1967 subtracts 1 from the hash to get 1 storage slot
        // under an index without a known hash preimage which is enough to store a single address.
        // This implementation subtracts 1024 to get 1024 slots without a known preimage
        // allowing securely storing much larger structures.
        return bytes32(uint256(keccak256(bytes(name))) - 1024);
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
