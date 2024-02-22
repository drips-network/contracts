// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AddressDriver} from "src/AddressDriver.sol";
import {Drips, DripsLib, IERC20, MaxEndHintsImpl, StreamReceiver} from "src/Drips.sol";
import {Address, Giver, GiversRegistry} from "src/Giver.sol";
import {ManagedProxy} from "src/Managed.sol";
import {
    ERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract NativeTokenWrapper is ERC20("Native token wrapper", "NTW") {
    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract Logic {
    function fun(uint256 arg) external payable returns (address, uint256, uint256) {
        return (address(this), arg, msg.value);
    }
}

contract GiverTest is Test {
    Giver internal giver = new Giver();
    address internal logic = address(new Logic());

    function testDelegate() public {
        uint256 arg = 1234;
        uint256 value = 5678;

        bytes memory returned = giver.delegate{value: value}(logic, abi.encodeCall(Logic.fun, arg));

        (address thisAddr, uint256 receivedArg, uint256 receivedValue) =
            abi.decode(returned, (address, uint256, uint256));
        assertEq(thisAddr, address(giver), "Invalid delegation context");
        assertEq(receivedArg, arg, "Invalid argument");
        assertEq(receivedValue, value, "Invalid value");
    }

    function testDelegateRevertsForNonOwner() public {
        vm.prank(address(1234));
        vm.expectRevert("Caller is not the owner");
        giver.delegate(logic, "");
    }

    function testTransferToGiver() public {
        uint256 amt = 123;
        payable(address(giver)).transfer(amt);
        assertEq(address(giver).balance, amt, "Invalid balance");
    }
}

contract GiversRegistryTest is Test {
    Drips internal drips;
    AddressDriver internal addressDriver;
    IERC20 internal erc20;
    IERC20 internal nativeTokenWrapper;
    GiversRegistry internal giversRegistry;
    uint256 internal accountId;
    address payable internal giver;

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(1))));
        drips.registerDriver(address(1));
        AddressDriver addressDriverLogic =
            new AddressDriver(drips, address(0), drips.nextDriverId());
        addressDriver = AddressDriver(address(new ManagedProxy(addressDriverLogic, address(1))));
        drips.registerDriver(address(addressDriver));

        GiversRegistry giversRegistryLogic = new GiversRegistry(addressDriver);
        giversRegistry = GiversRegistry(address(new ManagedProxy(giversRegistryLogic, address(1))));
        giversRegistry.initialize();
        nativeTokenWrapper = giversRegistry.nativeTokenWrapper();
        vm.etch(address(nativeTokenWrapper), address(new NativeTokenWrapper()).code);
        accountId = 1234;
        giver = payable(giversRegistry.giver(accountId));
        emit log_named_address("GIVER", giver);

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(addressDriver), type(uint256).max);
    }

    function give(uint256 amt) internal {
        give(amt, amt);
    }

    function give(uint256 amt, uint256 expectedGiven) internal {
        erc20.transfer(giver, amt);
        uint256 balanceBefore = erc20.balanceOf(giver);
        uint256 amtBefore = drips.splittable(accountId, erc20);

        giversRegistry.give(accountId, erc20);

        uint256 balanceAfter = erc20.balanceOf(giver);
        uint256 amtAfter = drips.splittable(accountId, erc20);
        assertEq(balanceAfter, balanceBefore - expectedGiven, "Invalid giver balance");
        assertEq(amtAfter, amtBefore + expectedGiven, "Invalid given amount");
    }

    function giveNative(uint256 amtNative, uint256 amtWrapped) internal {
        Address.sendValue(giver, amtNative);
        Address.sendValue(payable(address(nativeTokenWrapper)), amtWrapped);
        nativeTokenWrapper.transfer(giver, amtWrapped);

        uint256 balanceBefore = giver.balance + nativeTokenWrapper.balanceOf(giver);
        uint256 amtBefore = drips.splittable(accountId, nativeTokenWrapper);

        giversRegistry.give(accountId, IERC20(address(0)));

        uint256 balanceAfter = nativeTokenWrapper.balanceOf(giver);
        uint256 amtAfter = drips.splittable(accountId, nativeTokenWrapper);
        assertEq(giver.balance, 0, "Invalid giver native token balance");
        uint256 expectedGiven = amtNative + amtWrapped;
        assertEq(balanceAfter, balanceBefore - expectedGiven, "Invalid giver balance");
        assertEq(amtAfter, amtBefore + expectedGiven, "Invalid given amount");
    }

    function testGive() public {
        give(5);
    }

    function testGiveZero() public {
        give(0);
    }

    function testGiveUsingDeployedGiver() public {
        give(1);
        give(5);
    }

    function testGiveMaxBalance() public {
        give(DripsLib.MAX_TOTAL_BALANCE);
        give(1, 0);
    }

    function testGiveOverMaxBalance() public {
        erc20.approve(address(addressDriver), 15);
        addressDriver.setStreams(
            erc20,
            new StreamReceiver[](0),
            10,
            new StreamReceiver[](0),
            MaxEndHintsImpl.create(),
            address(this)
        );
        addressDriver.give(0, erc20, 5);
        give(DripsLib.MAX_TOTAL_BALANCE, DripsLib.MAX_TOTAL_BALANCE - 15);
    }

    function testGiveNative() public {
        giveNative(10, 0);
    }

    function testGiveWrapped() public {
        giveNative(0, 5);
    }

    function testGiveNativeAndWrapped() public {
        giveNative(10, 5);
    }

    function testGiveZeroWrapped() public {
        giveNative(0, 0);
    }

    function testGiveImplReverts() public {
        vm.expectRevert("Caller is not GiversRegistry");
        giversRegistry.giveImpl(accountId, erc20);
    }

    function notDelegatedReverts() internal returns (GiversRegistry giversRegistry_) {
        giversRegistry_ = GiversRegistry(giversRegistry.implementation());
        vm.expectRevert("Function must be called through delegatecall");
    }

    function testInitializeMustBeDelegated() public {
        notDelegatedReverts().initialize();
    }

    function testGiverMustBeDelegated() public {
        notDelegatedReverts().giver(accountId);
    }

    function testGiveMustBeDelegated() public {
        notDelegatedReverts().give(accountId, erc20);
    }
}
