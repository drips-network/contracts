// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {AddressDriver} from "./AddressDriver.sol";
import {Caller} from "./Caller.sol";
import {DripsHub} from "./DripsHub.sol";
import {Managed, ManagedProxy} from "./Managed.sol";
import {NFTDriver} from "./NFTDriver.sol";
import {ImmutableSplitsDriver} from "./ImmutableSplitsDriver.sol";

contract Deployer {
    // slither-disable-next-line immutable-states
    address public creator;

    DripsHub public dripsHub;
    bytes public dripsHubArgs;
    uint32 public dripsHubCycleSecs;
    DripsHub public dripsHubLogic;
    bytes public dripsHubLogicArgs;
    address public dripsHubAdmin;

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
        uint32 dripsHubCycleSecs_,
        address dripsHubAdmin_,
        address addressDriverAdmin_,
        address nftDriverAdmin_,
        address immutableSplitsDriverAdmin_
    ) {
        creator = msg.sender;
        _deployDripsHub(dripsHubCycleSecs_, dripsHubAdmin_);
        _deployCaller();
        _deployAddressDriver(addressDriverAdmin_);
        _deployNFTDriver(nftDriverAdmin_);
        _deployImmutableSplitsDriver(immutableSplitsDriverAdmin_);
    }

    function _deployDripsHub(uint32 dripsHubCycleSecs_, address dripsHubAdmin_) internal {
        // Deploy logic
        dripsHubCycleSecs = dripsHubCycleSecs_;
        dripsHubLogicArgs = abi.encode(dripsHubCycleSecs);
        dripsHubLogic = new DripsHub(dripsHubCycleSecs);
        // Deploy proxy
        dripsHubAdmin = dripsHubAdmin_;
        // slither-disable-next-line reentrancy-benign
        ManagedProxy proxy = new ManagedProxy(dripsHubLogic, dripsHubAdmin);
        dripsHub = DripsHub(address(proxy));
        dripsHubArgs = abi.encode(dripsHubLogic, dripsHubAdmin);
    }

    function _deployCaller() internal {
        caller = new Caller();
        callerArgs = abi.encode();
    }

    /// @dev Requires DripsHub and Caller to be deployed
    function _deployAddressDriver(address addressDriverAdmin_) internal {
        // Deploy logic
        address forwarder = address(caller);
        uint32 driverId = dripsHub.nextDriverId();
        addressDriverLogicArgs = abi.encode(dripsHub, forwarder, driverId);
        addressDriverLogic = new AddressDriver(dripsHub, forwarder, driverId);
        // Deploy proxy
        addressDriverAdmin = addressDriverAdmin_;
        // slither-disable-next-line reentrancy-benign
        ManagedProxy proxy = new ManagedProxy(addressDriverLogic, addressDriverAdmin);
        addressDriver = AddressDriver(address(proxy));
        addressDriverArgs = abi.encode(addressDriverLogic, addressDriverAdmin);
        // Register as a driver
        addressDriverId = dripsHub.registerDriver(address(addressDriver));
    }

    /// @dev Requires DripsHub and Caller to be deployed
    function _deployNFTDriver(address nftDriverAdmin_) internal {
        // Deploy logic
        address forwarder = address(caller);
        uint32 driverId = dripsHub.nextDriverId();
        nftDriverLogicArgs = abi.encode(dripsHub, forwarder, driverId);
        nftDriverLogic = new NFTDriver(dripsHub, forwarder, driverId);
        // Deploy proxy
        nftDriverAdmin = nftDriverAdmin_;
        // slither-disable-next-line reentrancy-benign
        ManagedProxy proxy = new ManagedProxy(nftDriverLogic, nftDriverAdmin);
        nftDriver = NFTDriver(address(proxy));
        nftDriverArgs = abi.encode(nftDriverLogic, nftDriverAdmin);
        // Register as a driver
        nftDriverId = dripsHub.registerDriver(address(nftDriver));
    }

    /// @dev Requires DripsHub to be deployed
    function _deployImmutableSplitsDriver(address immutableSplitsDriverAdmin_) internal {
        // Deploy logic
        uint32 driverId = dripsHub.nextDriverId();
        immutableSplitsDriverLogicArgs = abi.encode(dripsHub, driverId);
        immutableSplitsDriverLogic = new ImmutableSplitsDriver(dripsHub, driverId);
        // Deploy proxy
        immutableSplitsDriverAdmin = immutableSplitsDriverAdmin_;
        // slither-disable-next-line reentrancy-benign
        ManagedProxy proxy =
            new ManagedProxy(immutableSplitsDriverLogic, immutableSplitsDriverAdmin);
        immutableSplitsDriver = ImmutableSplitsDriver(address(proxy));
        immutableSplitsDriverArgs =
            abi.encode(immutableSplitsDriverLogic, immutableSplitsDriverAdmin);
        // Register as a driver
        immutableSplitsDriverId = dripsHub.registerDriver(address(immutableSplitsDriver));
    }
}
