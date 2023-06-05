// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {ImmutableSplitsDriver} from "src/ImmutableSplitsDriver.sol";
import {Drips, SplitsReceiver, UserMetadata} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";

contract ImmutableSplitsDriverTest is Test {
    Drips internal drips;
    ImmutableSplitsDriver internal driver;
    uint32 internal totalSplitsWeight;
    address internal admin = address(1);

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this))));

        // Make the driver ID non-0 to test if it's respected by the driver
        drips.registerDriver(address(1));
        drips.registerDriver(address(1));
        uint32 driverId = drips.registerDriver(address(this));
        ImmutableSplitsDriver driverLogic = new ImmutableSplitsDriver(drips, driverId);
        driver = ImmutableSplitsDriver(address(new ManagedProxy(driverLogic, admin)));
        drips.updateDriverAddress(driverId, address(driver));
        totalSplitsWeight = driver.totalSplitsWeight();
    }

    function testCreateSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](2);
        receivers[0] = SplitsReceiver({userId: 1, weight: totalSplitsWeight - 1});
        receivers[1] = SplitsReceiver({userId: 2, weight: 1});
        uint256 nextUserId = driver.nextUserId();
        UserMetadata[] memory metadata = new UserMetadata[](1);
        metadata[0] = UserMetadata("key", "value");

        uint256 userId = driver.createSplits(receivers, metadata);

        assertEq(userId, nextUserId, "Invalid user ID");
        assertEq(driver.nextUserId(), userId + 1, "Invalid next user ID");
        bytes32 actual = drips.splitsHash(userId);
        bytes32 expected = drips.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testCreateSplitsRevertsWhenWeightsSumTooLow() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](2);
        receivers[0] = SplitsReceiver({userId: 1, weight: totalSplitsWeight - 2});
        receivers[1] = SplitsReceiver({userId: 2, weight: 1});

        vm.expectRevert("Invalid total receivers weight");
        driver.createSplits(receivers, new UserMetadata[](0));
    }

    function testSetSplitsCanBePaused() public {
        vm.prank(admin);
        driver.pause();
        vm.expectRevert("Contract paused");
        driver.createSplits(new SplitsReceiver[](0), new UserMetadata[](0));
    }
}
