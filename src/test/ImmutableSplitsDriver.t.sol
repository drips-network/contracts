// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {ImmutableSplitsDriver} from "../ImmutableSplitsDriver.sol";
import {DripsHub, SplitsReceiver} from "../DripsHub.sol";
import {Reserve} from "../Reserve.sol";
import {Proxy} from "../Upgradeable.sol";
import {Test} from "forge-std/Test.sol";

contract ImmutableSplitsDriverTest is Test {
    DripsHub internal dripsHub;
    ImmutableSplitsDriver internal driver;
    uint32 internal totalSplitsWeight;

    function setUp() public {
        Reserve reserve = new Reserve(address(this));
        DripsHub hubLogic = new DripsHub(10, reserve);
        dripsHub = DripsHub(address(new Proxy(hubLogic, address(this))));
        reserve.addUser(address(dripsHub));

        // Make the driver ID non-0 to test if it's respected by the driver
        dripsHub.registerDriver(address(0));
        dripsHub.registerDriver(address(0));
        uint32 driverId = dripsHub.registerDriver(address(this));
        ImmutableSplitsDriver driverLogic = new ImmutableSplitsDriver(dripsHub, driverId);
        driver = ImmutableSplitsDriver(address(new Proxy(driverLogic, address(0xDEAD))));
        dripsHub.updateDriverAddress(driverId, address(driver));
        totalSplitsWeight = driver.totalSplitsWeight();
    }

    function testCreateSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](2);
        receivers[0] = SplitsReceiver({userId: 1, weight: totalSplitsWeight - 1});
        receivers[1] = SplitsReceiver({userId: 2, weight: 1});
        uint256 nextUserId = driver.nextUserId();

        uint256 userId = driver.createSplits(receivers);

        assertEq(userId, nextUserId, "Invalid user ID");
        assertEq(driver.nextUserId(), userId + 1, "Invalid next user ID");
        bytes32 actual = dripsHub.splitsHash(userId);
        bytes32 expected = dripsHub.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testCreateSplitsRevertsWhenWeightsSumTooLow() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](2);
        receivers[0] = SplitsReceiver({userId: 1, weight: totalSplitsWeight - 2});
        receivers[1] = SplitsReceiver({userId: 2, weight: 1});

        vm.expectRevert("Invalid total receivers weight");
        driver.createSplits(receivers);
    }
}
