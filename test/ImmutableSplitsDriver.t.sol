// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {ImmutableSplitsDriver} from "src/ImmutableSplitsDriver.sol";
import {AccountMetadata, Drips, SplitsReceiver} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";

contract ImmutableSplitsDriverTest is Test {
    Drips internal drips;
    ImmutableSplitsDriver internal driver;
    uint256 internal totalSplitsWeight;

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this))));

        // Make the driver ID non-0 to test if it's respected by the driver
        drips.registerDriver(address(1));
        drips.registerDriver(address(1));
        uint32 driverId = drips.registerDriver(address(this));
        ImmutableSplitsDriver driverLogic = new ImmutableSplitsDriver(drips, driverId);
        driver = ImmutableSplitsDriver(address(new ManagedProxy(driverLogic, address(1))));
        drips.updateDriverAddress(driverId, address(driver));
        totalSplitsWeight = driver.totalSplitsWeight();
    }

    function splitsReceivers(uint256 weight1, uint256 weight2)
        internal
        pure
        returns (SplitsReceiver[] memory list)
    {
        list = new SplitsReceiver[](2);
        list[0] = SplitsReceiver(1, weight1);
        list[1] = SplitsReceiver(2, weight2);
    }

    function testCreateSplits() public {
        SplitsReceiver[] memory receivers = splitsReceivers(totalSplitsWeight - 1, 1);
        uint256 nextAccountId = driver.nextAccountId();
        AccountMetadata[] memory metadata = new AccountMetadata[](1);
        metadata[0] = AccountMetadata("key", "value");

        uint256 accountId = driver.createSplits(receivers, metadata);

        assertEq(accountId, nextAccountId, "Invalid account ID");
        assertEq(driver.nextAccountId(), accountId + 1, "Invalid next account ID");
        bytes32 actual = drips.splitsHash(accountId);
        bytes32 expected = drips.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testCreateSplitsRevertsWhenWeightsSumTooLow() public {
        SplitsReceiver[] memory receivers = splitsReceivers(totalSplitsWeight - 2, 1);
        vm.expectRevert("Invalid total receivers weight");
        driver.createSplits(receivers, new AccountMetadata[](0));
    }

    function testCreateSplitsRevertsWhenWeightsSumTooHigh() public {
        SplitsReceiver[] memory receivers = splitsReceivers(totalSplitsWeight - 1, 2);
        vm.expectRevert("Invalid total receivers weight");
        driver.createSplits(receivers, new AccountMetadata[](0));
    }

    function testCreateSplitsRevertsWhenWeightsSumOverflows() public {
        SplitsReceiver[] memory receivers =
            splitsReceivers(totalSplitsWeight + 1, type(uint256).max);
        vm.expectRevert("Invalid total receivers weight");
        driver.createSplits(receivers, new AccountMetadata[](0));
    }

    function notDelegatedReverts() internal returns (ImmutableSplitsDriver driver_) {
        driver_ = ImmutableSplitsDriver(driver.implementation());
        vm.expectRevert("Function must be called through delegatecall");
    }

    function testNextAccountIdMustBeDelegated() public {
        notDelegatedReverts().nextAccountId();
    }

    function testCreateSplitsMustBeDelegated() public {
        notDelegatedReverts().createSplits(new SplitsReceiver[](0), new AccountMetadata[](0));
    }
}
