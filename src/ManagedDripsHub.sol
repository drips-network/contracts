// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";
import {DripsHub, SplitsReceiver} from "./DripsHub.sol";

/// @notice The DripsHub which is UUPS-upgradable, pausable and has an admin.
/// It can't be used directly, only via a proxy.
///
/// ManagedDripsHub uses the ERC-1967 admin slot to store the admin address.
/// All instances of the contracts are owned by address `0x00`.
/// While this contract is capable of updating the admin,
/// the proxy is expected to set up the initial value of the ERC-1967 admin.
///
/// All instances of the contracts are paused and can't be unpaused.
/// When a proxy uses such contract via delegation, it's initially unpaused.
abstract contract ManagedDripsHub is DripsHub, UUPSUpgradeable {
    /// @notice The ERC-1967 storage slot for the contract.
    /// It holds a single `ManagedDripsHubStorage` structure.
    bytes32 private constant STORAGE_SLOT =
        bytes32(uint256(keccak256("eip1967.managedDripsHub.storage")) - 1);

    /// @notice Emitted when the pause is triggered.
    /// @param account The account which triggered the change.
    event Paused(address account);

    /// @notice Emitted when the pause is lifted.
    /// @param account The account which triggered the change.
    event Unpaused(address account);

    struct ManagedDripsHubStorage {
        DripsHubStorage dripsHubStorage;
        bool paused;
    }

    /// @notice Initializes the contract in paused state and with no admin.
    /// The contract instance can be used only as a call delegation target for a proxy.
    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being collectable by their receivers.
    /// High value makes collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 cycleSecs) DripsHub(cycleSecs) {
        _managedDripsHubStorage().paused = true;
    }

    /// @notice Collects all received funds available for the user
    /// and transfers them out of the drips hub contract to that user's wallet.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collected The collected amount
    /// @return split The amount split to the user's splits receivers
    function collectAll(
        address user,
        uint256 assetId,
        SplitsReceiver[] memory currReceivers
    ) public override whenNotPaused returns (uint128 collected, uint128 split) {
        return super.collectAll(user, assetId, currReceivers);
    }

    /// @notice Flushes uncollected cycles of the user.
    /// Flushed cycles won't need to be analyzed when the user collects from them.
    /// Calling this function does not collect and does not affect the collectable amount.
    ///
    /// This function is needed when collecting funds received over a period so long, that the gas
    /// needed for analyzing all the uncollected cycles can't fit in a single transaction.
    /// Calling this function allows spreading the analysis cost over multiple transactions.
    /// A cycle is never flushed more than once, even if this function is called many times.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of flushed cycles.
    /// If too low, flushing will be cheap, but will cut little gas from the next collection.
    /// If too high, flushing may become too expensive to fit in a single transaction.
    /// @return flushable The number of cycles which can be flushed
    function flushCycles(
        address user,
        uint256 assetId,
        uint64 maxCycles
    ) public override whenNotPaused returns (uint64 flushable) {
        return super.flushCycles(user, assetId, maxCycles);
    }

    /// @notice Authorizes the contract upgrade. See `UUPSUpgradable` docs for more details.
    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        newImplementation;
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

    /// @notice Throws if called by any account other than the admin.
    modifier onlyAdmin() {
        require(admin() == msg.sender, "Caller is not the admin");
        _;
    }

    /// @notice Returns true if the contract is paused, and false otherwise.
    function paused() public view returns (bool isPaused) {
        return _managedDripsHubStorage().paused;
    }

    /// @notice Triggers stopped state.
    function pause() public onlyAdmin whenNotPaused {
        _managedDripsHubStorage().paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Returns to normal state.
    function unpause() public onlyAdmin whenPaused {
        _managedDripsHubStorage().paused = false;
        emit Unpaused(msg.sender);
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

    /// @notice Returns the DripsHub storage.
    /// @return storageRef The storage.
    function _dripsHubStorage()
        internal
        view
        override
        returns (DripsHubStorage storage storageRef)
    {
        return _managedDripsHubStorage().dripsHubStorage;
    }

    /// @notice Returns the ManagedDripsHub contract storage.
    /// @return storageRef The storage.
    function _managedDripsHubStorage()
        internal
        pure
        returns (ManagedDripsHubStorage storage storageRef)
    {
        bytes32 slot = STORAGE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Based on OpenZeppelin's StorageSlot
            storageRef.slot := slot
        }
    }
}

/// @notice A generic ManagedDripsHub proxy.
contract ManagedDripsHubProxy is ERC1967Proxy {
    constructor(ManagedDripsHub hubLogic, address admin)
        ERC1967Proxy(address(hubLogic), new bytes(0))
    {
        _changeAdmin(admin);
    }
}
