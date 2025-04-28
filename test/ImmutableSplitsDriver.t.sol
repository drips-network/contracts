// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20, ImmutableSplitsDriver} from "src/ImmutableSplitsDriver.sol";
import {AccountMetadata, Drips, SplitsReceiver} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20PresetFixedSupply} from
    "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ImmutableSplitsDriverTest is Test {
    Drips internal drips;
    ImmutableSplitsDriver internal driver;
    address internal admin = address(bytes20("admin"));

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this), "")));

        // Register self as driver `0` and having control of account ID `0`.
        drips.registerDriver(address(this));

        // Make the driver ID non-0 to test if it's respected by the driver
        drips.registerDriver(address(1));
        drips.registerDriver(address(1));
        uint32 driverId = drips.registerDriver(address(this));
        ImmutableSplitsDriver driverLogic = new ImmutableSplitsDriver(drips, driverId);
        driver = ImmutableSplitsDriver(address(new ManagedProxy(driverLogic, admin, "")));
        drips.updateDriverAddress(driverId, address(driver));
    }

    function splitsReceivers() internal view returns (SplitsReceiver[] memory receivers) {
        receivers = new SplitsReceiver[](2);
        receivers[0] = SplitsReceiver({accountId: 1, weight: driver.totalSplitsWeight() - 1});
        receivers[1] = SplitsReceiver({accountId: 2, weight: 1});
    }

    function accountMetadata() internal pure returns (AccountMetadata[] memory metadata) {
        metadata = new AccountMetadata[](1);
        metadata[0] = AccountMetadata("key", "value");
    }

    function testCreateSplits() public {
        SplitsReceiver[] memory receivers = splitsReceivers();
        AccountMetadata[] memory metadata = accountMetadata();

        uint256 accountId = driver.createSplits(receivers, metadata);

        assertEq(accountId, driver.calcAccountId(receivers, metadata), "Invalid account ID");
        assertEq(drips.splitsHash(accountId), drips.hashSplits(receivers), "Invalid splits hash");
    }

    function testCreatingSplitsForTheSecondTimeDoesNothing() public {
        SplitsReceiver[] memory receivers = splitsReceivers();
        AccountMetadata[] memory metadata = accountMetadata();

        driver.createSplits(receivers, metadata);
        uint256 accountId = driver.createSplits(receivers, metadata);

        assertEq(accountId, driver.calcAccountId(receivers, metadata), "Invalid account ID");
        assertEq(drips.splitsHash(accountId), drips.hashSplits(receivers), "Invalid splits hash");
    }

    function testCreateSplitsRevertsWhenWeightsSumTooLow() public {
        SplitsReceiver[] memory receivers = splitsReceivers();
        receivers[0].weight--;
        vm.expectRevert("Invalid total receivers weight");
        driver.createSplits(receivers, accountMetadata());
    }

    function testCollectAndGiveToSelf() public {
        uint256 accountId = driver.calcAccountId(splitsReceivers(), accountMetadata());
        uint128 amount = 100;
        IERC20 erc20 = new ERC20PresetFixedSupply("test", "test", amount, address(drips));
        drips.give(0, accountId, erc20, amount);
        drips.split(accountId, erc20, new SplitsReceiver[](0));
        assertEq(drips.collectable(accountId, erc20), amount, "Invalid collectable before giving");
        assertEq(drips.splittable(accountId, erc20), 0, "Invalid splittable before giving");

        uint128 given = driver.collectAndGiveToSelf(accountId, erc20);

        assertEq(given, amount, "Invalid given amount");
        assertEq(drips.collectable(accountId, erc20), 0, "Invalid collectable before giving");
        assertEq(drips.splittable(accountId, erc20), amount, "Invalid splittable before giving");
    }

    function testSetSplitsCanBePaused() public {
        vm.prank(admin);
        driver.pause();
        vm.expectRevert("Contract paused");
        driver.createSplits(new SplitsReceiver[](0), new AccountMetadata[](0));
    }
}
