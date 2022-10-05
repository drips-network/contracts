// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Caller} from "../Caller.sol";
import {AddressDriver} from "../AddressDriver.sol";
import {
    DripsConfigImpl, DripsHub, DripsHistory, DripsReceiver, SplitsReceiver
} from "../DripsHub.sol";
import {Reserve} from "../Reserve.sol";
import {Proxy} from "../Upgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract AddressDriverTest is Test {
    DripsHub internal dripsHub;
    Caller internal caller;
    AddressDriver internal driver;
    IERC20 internal erc20;

    uint256 internal thisId;
    address internal user;
    uint256 internal userId;

    function setUp() public {
        Reserve reserve = new Reserve(address(this));
        DripsHub hubLogic = new DripsHub(10, reserve);
        dripsHub = DripsHub(address(new Proxy(hubLogic, address(this))));
        reserve.addUser(address(dripsHub));

        caller = new Caller();

        // Make AddressDriver's driver ID non-0 to test if it's respected by AddressDriver
        dripsHub.registerDriver(address(0));
        dripsHub.registerDriver(address(0));
        uint32 nftDriverId = dripsHub.registerDriver(address(this));
        AddressDriver driverLogic = new AddressDriver(dripsHub, address(caller), nftDriverId);
        driver = AddressDriver(address(new Proxy(driverLogic, address(0xDEAD))));
        dripsHub.updateDriverAddress(nftDriverId, address(driver));

        thisId = driver.calcUserId(address(this));
        user = address(1);
        userId = driver.calcUserId(user);

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(driver), type(uint256).max);
        erc20.transfer(user, erc20.totalSupply() / 100);
        vm.prank(user);
        erc20.approve(address(driver), type(uint256).max);
    }

    function testCollect() public {
        uint128 amt = 5;
        vm.prank(user);
        driver.give(thisId, erc20, amt);
        dripsHub.split(thisId, erc20, new SplitsReceiver[](0));
        uint256 balance = erc20.balanceOf(address(this));

        uint128 collected = driver.collect(erc20, address(this));

        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(address(this)), balance + amt, "Invalid balance");
    }

    function testCollectTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        vm.prank(user);
        driver.give(thisId, erc20, amt);
        dripsHub.split(thisId, erc20, new SplitsReceiver[](0));
        address transferTo = address(1234);

        uint128 collected = driver.collect(erc20, transferTo);

        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
    }

    function testGive() public {
        uint128 amt = 5;
        uint256 balance = erc20.balanceOf(address(this));

        driver.give(userId, erc20, amt);

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(dripsHub.splittable(userId, erc20), amt, "Invalid received amount");
    }

    function testSetDrips() public {
        uint128 amt = 5;

        // Top-up

        DripsReceiver[] memory receivers = new DripsReceiver[](1);
        receivers[0] = DripsReceiver(userId, DripsConfigImpl.create(1, 0, 0));
        uint256 balance = erc20.balanceOf(address(this));

        (uint128 newBalance, int128 realBalanceDelta) =
            driver.setDrips(erc20, new DripsReceiver[](0), int128(amt), receivers, address(this));

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(newBalance, amt, "Invalid drips balance after top-up");
        assertEq(realBalanceDelta, int128(amt), "Invalid drips balance delta after top-up");
        (bytes32 dripsHash,,,,) = dripsHub.dripsState(thisId, erc20);
        assertEq(dripsHash, dripsHub.hashDrips(receivers), "Invalid drips hash after top-up");

        // Withdraw
        balance = erc20.balanceOf(address(user));

        (newBalance, realBalanceDelta) =
            driver.setDrips(erc20, receivers, -int128(amt), receivers, address(user));

        assertEq(erc20.balanceOf(address(user)), balance + amt, "Invalid balance after withdrawal");
        assertEq(newBalance, 0, "Invalid drips balance after withdrawal");
        assertEq(realBalanceDelta, -int128(amt), "Invalid drips balance delta after withdrawal");
    }

    function testSetDripsDecreasingBalanceTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        DripsReceiver[] memory receivers = new DripsReceiver[](0);
        driver.setDrips(erc20, receivers, int128(amt), receivers, address(this));
        address transferTo = address(1234);

        (uint128 newBalance, int128 realBalanceDelta) =
            driver.setDrips(erc20, receivers, -int128(amt), receivers, transferTo);

        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
        assertEq(newBalance, 0, "Invalid drips balance");
        assertEq(realBalanceDelta, -int128(amt), "Invalid drips balance delta");
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(userId, 1);

        driver.setSplits(receivers);

        bytes32 actual = dripsHub.splitsHash(thisId);
        bytes32 expected = dripsHub.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testEmitUserMetadata() public {
        driver.emitUserMetadata(1, "value");
    }

    function testForwarderIsTrusted() public {
        vm.prank(user);
        caller.authorize(address(this));
        assertEq(dripsHub.splittable(userId, erc20), 0, "Invalid splittable before give");
        uint128 amt = 10;

        bytes memory giveData = abi.encodeWithSelector(driver.give.selector, userId, erc20, amt);
        caller.callAs(user, address(driver), giveData);

        assertEq(dripsHub.splittable(userId, erc20), amt, "Invalid splittable after give");
    }
}
