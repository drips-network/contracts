////// SPDX-License-Identifier-FLATTEN-SUPPRESS-WARNING: GPL-3.0-only
pragma solidity ^0.8.15;

abstract contract Managed {
    /// @notice The pointer to the storage slot with the boolean holding the paused state.
    bytes32 internal immutable pausedSlot = erc1967Slot("eip1967.managed.paused");

    /// @notice Initializes the contract in paused state and with no admin.
    /// The contract instance can be used only as a call delegation target for a proxy.
    constructor() {
        StorageSlot.getBooleanSlot(pausedSlot).value = true;
    }

    /// @notice Calculates the ERC-1967 slot pointer.
    /// @param name The name of the slot, should be globally unique
    /// @return slot The slot pointer
    function erc1967Slot(string memory name) internal pure returns (bytes32 slot) {
        return bytes32(uint256(keccak256(bytes(name))) - 1);
    }

    /// @notice Returns true if the contract is paused, and false otherwise.
    function paused() public view returns (bool isPaused) {
        return _pausedSlot().value;
    }

    /// @notice Triggers stopped state.
    function pause() public whenNotPaused {
        _pausedSlot().value = true;
    }

    /// @notice Returns to normal state.
    function unpause() public whenPaused {
        _pausedSlot().value = false;
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

    function _pausedSlot() private view returns (StorageSlot.BooleanSlot storage slot) {
        return StorageSlot.getBooleanSlot(pausedSlot);
    }
}


interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}


/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * _Available since v4.1 for `address`, `bool`, `bytes32`, and `uint256`._
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }
}


contract SlotTester is Managed {
    /// @notice The ERC-1967 storage slot holding a single `DripsHubStorage` structure.
    bytes32 internal immutable _storageSlot = erc1967Slot("eip1967.dripsHub.storage");

    function get_storageSlot() public view returns (bytes32) {
        return _storageSlot;
    }

    function getPausedSlot() public view returns (bytes32) {
        return pausedSlot;
    }

    struct DripsHubStorage {
        /// @notice The next app ID that will be used when registering.
        uint32 nextAppId;
        /// @notice App addresses. The key is the app ID, the value is the app address.
        mapping(uint32 => address) appAddrs;
        /// @notice The total amount currently stored in DripsHub of each token.
        mapping(IERC20 => uint256) totalBalances;
    }


    /// @notice Registers an app.
    /// The app is assigned a unique ID and a range of user IDs it can control.
    /// That range consists of all 2^224 user IDs with highest 32 bits equal to the app ID.
    /// Multiple apps can have the same address, it can then control all of them.
    /// @return appId The registered app ID.
    function registerApp(address appAddr) public whenNotPaused returns (uint32 appId) {
        DripsHubStorage storage dripsHubStorage = _dripsHubStorage();
        appId = dripsHubStorage.nextAppId++;
        dripsHubStorage.appAddrs[appId] = appAddr;
    }

    /// @notice Returns the app address.
    /// @param appId The app ID to look up.
    /// @return appAddr The address of the app.
    /// If the app hasn't been registered yet, returns address 0.
    function appAddress(uint32 appId) public view returns (address appAddr) {
        return _dripsHubStorage().appAddrs[appId];
    }

    /// @notice Returns the total amount currently stored in DripsHub of the given token.
    /// @param erc20 The ERC-20 token
    /// @return balance The balance of the token.
    function totalBalance(IERC20 erc20) public view returns (uint256 balance) {
        return _dripsHubStorage().totalBalances[erc20];
    }

    /// @notice Returns the DripsHub storage.
    /// @return storageRef The storage.
    function _dripsHubStorage() internal view returns (DripsHubStorage storage storageRef) {
        bytes32 slot = _storageSlot;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            storageRef.slot := slot
        }
    }

}

