// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {ERC1967Upgrade} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Upgrade.sol";

/// @notice The proxy-safe ownability mix-in.
/// It's supposed to be used only in contracts behind a proxy.
///
/// This contract uses the ERC-1967 admin slot to store the owner address.
/// While this contract is capable of updating the owner,
/// the proxy is expected to set up the initial value of the ERC-1967 admin.
/// All instances of `ERC1967Ownable` contracts have owner set and locked to `0x00`.
abstract contract ERC1967Ownable is ERC1967Upgrade {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Throws if called by any account other than the owner.
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /// @notice Returns the address of the current owner.
    function owner() public view returns (address) {
        return _getAdmin();
    }

    /// @notice Transfers ownership of the contract to a new account (`newOwner`).
    /// Can only be called by the current owner.
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        address oldOwner = owner();
        _changeAdmin(newOwner);
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
