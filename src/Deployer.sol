// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {AddressDriver} from "./AddressDriver.sol";
import {Caller} from "./Caller.sol";
import {Drips} from "./Drips.sol";
import {Managed, ManagedProxy} from "./Managed.sol";
import {NFTDriver} from "./NFTDriver.sol";
import {ImmutableSplitsDriver} from "./ImmutableSplitsDriver.sol";

contract Deployer {
    // slither-disable-next-line immutable-states
    address public creator;

    Drips public drips;
    bytes public dripsArgs;
    uint32 public dripsCycleSecs;
    Drips public dripsLogic;
    bytes public dripsLogicArgs;
    address public dripsAdmin;

    Caller public caller;
    bytes public callerArgs;

    AddressDriver public addressDriver;
    bytes public addressDriverArgs;
    AddressDriver public addressDriverLogic;
    bytes public addressDriverLogicArgs;
    address public addressDriverAdmin;
    uint32 public addressDriverId;

    NFTDriver public nftDriver;
    bytes public nftDriverArgs;
    NFTDriver public nftDriverLogic;
    bytes public nftDriverLogicArgs;
    address public nftDriverAdmin;
    uint32 public nftDriverId;

    ImmutableSplitsDriver public immutableSplitsDriver;
    bytes public immutableSplitsDriverArgs;
    ImmutableSplitsDriver public immutableSplitsDriverLogic;
    bytes public immutableSplitsDriverLogicArgs;
    address public immutableSplitsDriverAdmin;
    uint32 public immutableSplitsDriverId;

    constructor(
        uint32 dripsCycleSecs_,
        address dripsAdmin_,
        address addressDriverAdmin_,
        address nftDriverAdmin_,
        address immutableSplitsDriverAdmin_
    ) {
        creator = msg.sender;
        _deployDrips(dripsCycleSecs_, dripsAdmin_);
        _deployCaller();
        _deployAddressDriver(addressDriverAdmin_);
        _deployNFTDriver(nftDriverAdmin_);
        _deployImmutableSplitsDriver(immutableSplitsDriverAdmin_);
    }

    function _deployDrips(uint32 dripsCycleSecs_, address dripsAdmin_) internal {
        // Deploy logic
        dripsCycleSecs = dripsCycleSecs_;
        dripsLogicArgs = abi.encode(dripsCycleSecs);
        dripsLogic = new Drips(dripsCycleSecs);
        // Deploy proxy
        dripsAdmin = dripsAdmin_;
        // slither-disable-next-line reentrancy-benign
        ManagedProxy proxy = new ManagedProxy(dripsLogic, dripsAdmin);
        drips = Drips(address(proxy));
        dripsArgs = abi.encode(dripsLogic, dripsAdmin);
    }

    function _deployCaller() internal {
        caller = new Caller();
        callerArgs = abi.encode();
    }

    /// @dev Requires Drips and Caller to be deployed
    function _deployAddressDriver(address addressDriverAdmin_) internal {
        // Deploy logic
        address forwarder = address(caller);
        uint32 driverId = drips.nextDriverId();
        addressDriverLogicArgs = abi.encode(drips, forwarder, driverId);
        addressDriverLogic = new AddressDriver(drips, forwarder, driverId);
        // Deploy proxy
        addressDriverAdmin = addressDriverAdmin_;
        // slither-disable-next-line reentrancy-benign
        ManagedProxy proxy = new ManagedProxy(addressDriverLogic, addressDriverAdmin);
        addressDriver = AddressDriver(address(proxy));
        addressDriverArgs = abi.encode(addressDriverLogic, addressDriverAdmin);
        // Register as a driver
        addressDriverId = drips.registerDriver(address(addressDriver));
    }

    /// @dev Requires Drips and Caller to be deployed
    function _deployNFTDriver(address nftDriverAdmin_) internal {
        // Deploy logic
        address forwarder = address(caller);
        uint32 driverId = drips.nextDriverId();
        nftDriverLogicArgs = abi.encode(drips, forwarder, driverId);
        nftDriverLogic = new NFTDriver(drips, forwarder, driverId);
        // Deploy proxy
        nftDriverAdmin = nftDriverAdmin_;
        // slither-disable-next-line reentrancy-benign
        ManagedProxy proxy = new ManagedProxy(nftDriverLogic, nftDriverAdmin);
        nftDriver = NFTDriver(address(proxy));
        nftDriverArgs = abi.encode(nftDriverLogic, nftDriverAdmin);
        // Register as a driver
        nftDriverId = drips.registerDriver(address(nftDriver));
    }

    /// @dev Requires Drips to be deployed
    function _deployImmutableSplitsDriver(address immutableSplitsDriverAdmin_) internal {
        // Deploy logic
        uint32 driverId = drips.nextDriverId();
        immutableSplitsDriverLogicArgs = abi.encode(drips, driverId);
        immutableSplitsDriverLogic = new ImmutableSplitsDriver(drips, driverId);
        // Deploy proxy
        immutableSplitsDriverAdmin = immutableSplitsDriverAdmin_;
        // slither-disable-next-line reentrancy-benign
        ManagedProxy proxy =
            new ManagedProxy(immutableSplitsDriverLogic, immutableSplitsDriverAdmin);
        immutableSplitsDriver = ImmutableSplitsDriver(address(proxy));
        immutableSplitsDriverArgs =
            abi.encode(immutableSplitsDriverLogic, immutableSplitsDriverAdmin);
        // Register as a driver
        immutableSplitsDriverId = drips.registerDriver(address(immutableSplitsDriver));
    }
}
