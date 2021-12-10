// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Upgrade} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";
import {DripsHub, SplitsReceiver} from "./DripsHub.sol";
import {ERC1967Pausable} from "./ERC1967Pausable.sol";

/// @notice The DripsHub which is UUPS-upgradable, pausable and has an owner.
/// It can't be used directly, only via a proxy.
///
/// ManagedDripsHub uses the ERC-1967 admin slot to store the owner address.
/// While this contract is capable of updating the owner,
/// the proxy is expected to set up the initial value of the ERC-1967 admin.
abstract contract ManagedDripsHub is DripsHub, UUPSUpgradeable, ERC1967Pausable {
    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being collectable by their receivers.
    /// High value makes collecting cheaper by making it process less cycles for a given time range.
    // solhint-disable-next-line no-empty-blocks
    constructor(uint64 cycleSecs) DripsHub(cycleSecs) {}

    /// @notice Collects all received funds available for the user
    /// and transfers them out of the drips hub contract to that user's wallet.
    /// @param user The user
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collected The collected amount
    /// @return split The amount split to the user's splits receivers
    function collect(address user, SplitsReceiver[] memory currReceivers)
        public
        override
        whenNotPaused
        returns (uint128 collected, uint128 split)
    {
        return super.collect(user, currReceivers);
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
    /// @param maxCycles The maximum number of flushed cycles.
    /// If too low, flushing will be cheap, but will cut little gas from the next collection.
    /// If too high, flushing may become too expensive to fit in a single transaction.
    /// @return flushable The number of cycles which can be flushed
    function flushCycles(address user, uint64 maxCycles)
        public
        override
        whenNotPaused
        returns (uint64 flushable)
    {
        return super.flushCycles(user, maxCycles);
    }

    /// @notice Authorizes UUPSUpgradable upgrades
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        newImplementation;
    }

    /// @notice Triggers stopped state.
    function pause() public override whenNotPaused onlyOwner {
        _setPaused(true);
        emit Paused(msg.sender);
    }

    /// @notice Returns to normal state.
    function unpause() public override whenPaused onlyOwner {
        _setPaused(false);
        emit Unpaused(msg.sender);
    }

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

/// @notice A generic ManagedDripsHub proxy.
contract ManagedDripsHubProxy is ERC1967Proxy {
    constructor(ManagedDripsHub hubLogic, address owner)
        ERC1967Proxy(address(hubLogic), new bytes(0))
    {
        _changeAdmin(owner);
    }
}
