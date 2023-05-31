// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {ERC2771Context} from "openzeppelin-contracts/metatx/ERC2771Context.sol";
import {
    AddressDriver,
    Caller,
    Deployer,
    Managed,
    NFTDriver,
    ImmutableSplitsDriver
} from "src/Deployer.sol";
import {Drips, SplitsReceiver, UserMetadata} from "src/Drips.sol";

interface DriverMeta {
    function drips() external view returns (Drips);
    function driverId() external view returns (uint32);
}

contract DeployerTest is Test {
    function testDeployment() public {
        // Deployment parameters
        uint32 cycleSecs = 7 days;
        address dripsAdmin = address(1);
        address addressDriverAdmin = address(2);
        address nftDriverAdmin = address(3);
        address immutableSplitsDriverAdmin = address(4);

        // Deployment
        Deployer deployer = new Deployer(cycleSecs,
            dripsAdmin,
            addressDriverAdmin,
            nftDriverAdmin,
            immutableSplitsDriverAdmin);

        // Deployed contracts
        Drips drips = deployer.drips();
        Caller caller = deployer.caller();
        AddressDriver addressDriver = deployer.addressDriver();
        NFTDriver nftDriver = deployer.nftDriver();
        ImmutableSplitsDriver immutableSplitsDriver = deployer.immutableSplitsDriver();

        // Check deployment addresses being deterministic
        assertEq(deployer.creator(), address(this), "Invalid creator");
        assertAddress(deployer, 1, address(drips.implementation()));
        assertAddress(deployer, 2, address(drips));
        assertAddress(deployer, 3, address(caller));
        assertAddress(deployer, 4, address(addressDriver.implementation()));
        assertAddress(deployer, 5, address(addressDriver));
        assertAddress(deployer, 6, address(nftDriver.implementation()));
        assertAddress(deployer, 7, address(nftDriver));
        assertAddress(deployer, 8, address(immutableSplitsDriver.implementation()));
        assertAddress(deployer, 9, address(immutableSplitsDriver));

        // Check implementation addresses
        assertImplementation(drips, deployer.dripsLogic());
        assertImplementation(addressDriver, deployer.addressDriverLogic());
        assertImplementation(nftDriver, deployer.nftDriverLogic());
        assertImplementation(immutableSplitsDriver, deployer.immutableSplitsDriverLogic());

        // Check admins
        assertAdmin(drips, deployer.dripsAdmin(), dripsAdmin);
        assertAdmin(addressDriver, deployer.addressDriverAdmin(), addressDriverAdmin);
        assertAdmin(nftDriver, deployer.nftDriverAdmin(), nftDriverAdmin);
        assertAdmin(
            immutableSplitsDriver, deployer.immutableSplitsDriverAdmin(), immutableSplitsDriverAdmin
        );

        // Check Drips cycle length
        assertEq(deployer.dripsCycleSecs(), cycleSecs, "Invalid deployer cycle length");
        assertEq(drips.cycleSecs(), cycleSecs, "Invalid cycle length");

        // Check Drips being set
        assertDrips(DriverMeta(address(addressDriver)), drips);
        assertDrips(DriverMeta(address(nftDriver)), drips);
        assertDrips(DriverMeta(address(immutableSplitsDriver)), drips);

        // Check Caller being a forwarder
        assertForwarder(addressDriver, caller);
        assertForwarder(nftDriver, caller);

        // Check driver IDs registration
        assertDriverId(0, DriverMeta(address(addressDriver)));
        assertDriverId(1, DriverMeta(address(nftDriver)));
        assertDriverId(2, DriverMeta(address(immutableSplitsDriver)));
        assertEq(drips.nextDriverId(), 3, "Invalid next driver ID");

        // Implementations smoke test
        UserMetadata[] memory metadata = new UserMetadata[](1);
        metadata[0] = UserMetadata("key", "value");
        addressDriver.emitUserMetadata(metadata);
        nftDriver.mint(address(this), metadata);
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(123, immutableSplitsDriver.totalSplitsWeight());
        immutableSplitsDriver.createSplits(receivers, metadata);
    }

    function assertAddress(Deployer deployer, uint256 nonce, address actual) internal {
        address expected = computeCreateAddress(address(deployer), nonce);
        assertEq(actual, expected, "Invalid deployment address");
    }

    function assertImplementation(Managed proxy, Managed logic) internal {
        assertEq(address(proxy.implementation()), address(logic), "Invalid implementation address");
    }

    function assertAdmin(Managed proxy, address deployerAdmin, address expected) internal {
        assertEq(proxy.admin(), expected, "Invalid admin");
        assertEq(deployerAdmin, expected, "Invalid admin in deployer");
    }

    function assertDrips(DriverMeta driver, Drips drips) internal {
        assertEq(address(driver.drips()), address(drips), "Invalid Drips address");
    }

    function assertForwarder(ERC2771Context trusting, Caller caller) internal {
        assertTrue(trusting.isTrustedForwarder(address(caller)), "Caller not a trusted forwarder");
    }

    function assertDriverId(uint32 driverId, DriverMeta driver) internal {
        assertEq(driver.driverId(), driverId, "Invalid driver ID");
        address registeredDriver = driver.drips().driverAddress(driverId);
        assertEq(registeredDriver, address(driver), "Invalid registered driver address");
    }
}
