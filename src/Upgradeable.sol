// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice A mix-in for contract UUPS-upgradeability and admin management.
/// It can't be used directly, only via a proxy. It uses the upgrade-safe ERC-1967 storage scheme.
///
/// Upgradeable uses the ERC-1967 admin slot to store the admin address.
/// All instances of the contracts are owned by address `0x00`.
/// While this contract is capable of updating the admin,
/// the proxy is expected to set up the initial value of the ERC-1967 admin.
abstract contract Upgradeable is UUPSUpgradeable {
    /// @notice Throws if called by any caller other than the admin.
    modifier onlyAdmin() {
        require(admin() == msg.sender, "Caller is not the admin");
        _;
    }

    /// @notice Calculates the ERC-1967 slot pointer.
    /// @param name The name of the slot, should be globally unique
    /// @return slot The slot pointer
    function erc1967Slot(string memory name) internal pure returns (bytes32 slot) {
        return bytes32(uint256(keccak256(bytes(name))) - 1);
    }

    /// @notice Authorizes the contract upgrade. See `UUPSUpgradeable` docs for more details.
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
}

/// @notice A generic proxy for Upgradeable contracts.
contract UpgradeableProxy is ERC1967Proxy {
    constructor(Upgradeable logic, address admin) ERC1967Proxy(address(logic), new bytes(0)) {
        _changeAdmin(admin);
    }
}
