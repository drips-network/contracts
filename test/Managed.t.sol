// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Managed, ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";

contract Logic is Managed {
    uint256 public immutable instanceId;

    constructor(uint256 instanceId_) {
        instanceId = instanceId_;
    }

    function erc1967Slot(string memory name) public pure returns (bytes32 slot) {
        return _erc1967Slot(name);
    }
}

contract ManagedTest is Test {
    Logic internal logic;
    Logic internal proxy;

    address internal admin = address(1);
    address internal pauser = address(2);
    address internal user = address(3);

    bytes internal constant ERROR_NOT_ADMIN = "Caller is not the admin";
    bytes internal constant ERROR_NOT_ADMIN_OR_PAUSER = "Caller is not the admin or a pauser";

    function setUp() public {
        logic = new Logic(0);
        proxy = Logic(address(new ManagedProxy(logic, admin)));
        vm.prank(admin);
        proxy.grantPauser(pauser);
    }

    function pause() internal {
        vm.prank(pauser);
        proxy.pause();
    }

    function testLogicContractIsPausedForever() public {
        assertTrue(logic.paused(), "Not paused");
        assertEq(logic.admin(), address(0), "Admin not zero");
        assertEq(logic.allPausers(), new address[](0), "Pausers not empty");
    }

    function testAdminCanChangeAdmin() public {
        assertEq(proxy.admin(), admin);
        vm.prank(admin);
        proxy.changeAdmin(user);
        assertEq(proxy.admin(), user);
    }

    function testPauserCanNotChangeAdmin() public {
        vm.prank(pauser);
        vm.expectRevert(ERROR_NOT_ADMIN);
        proxy.changeAdmin(user);
    }

    function testArbitraryUserCanNotChangeAdmin() public {
        vm.expectRevert(ERROR_NOT_ADMIN);
        proxy.changeAdmin(user);
    }

    function testAdminCanUpgradeContract() public {
        uint256 newInstanceId = proxy.instanceId() + 1;
        Logic newLogic = new Logic(newInstanceId);
        vm.prank(admin);
        proxy.upgradeTo(address(newLogic));
        assertEq(proxy.instanceId(), newInstanceId, "Invalid new instance ID");
    }

    function testPauserCanNotUpgradeContract() public {
        Logic newLogic = new Logic(0);
        vm.prank(pauser);
        vm.expectRevert(ERROR_NOT_ADMIN);
        proxy.upgradeTo(address(newLogic));
    }

    function testArbitraryUserCanNotUpgradeContract() public {
        Logic newLogic = new Logic(0);
        vm.expectRevert(ERROR_NOT_ADMIN);
        proxy.upgradeTo(address(newLogic));
    }

    function testAdminCanGrantPauser() public {
        vm.prank(admin);
        proxy.grantPauser(user);
        assertTrue(proxy.isPauser(user), "Pauser not granted");
        address[] memory allPausers = new address[](2);
        allPausers[0] = pauser;
        allPausers[1] = user;
        assertEq(proxy.allPausers(), allPausers, "Invalid pausers");
    }

    function testPauserCanNotGrantPauser() public {
        vm.prank(pauser);
        vm.expectRevert(ERROR_NOT_ADMIN);
        proxy.grantPauser(user);
    }

    function testArbitraryUserCanNotGrantPauser() public {
        vm.expectRevert(ERROR_NOT_ADMIN);
        proxy.grantPauser(user);
    }

    function testAdminCanRevokePauser() public {
        vm.prank(admin);
        proxy.revokePauser(pauser);
        assertFalse(proxy.isPauser(pauser), "Pauser not revoked");
        assertEq(proxy.allPausers(), new address[](0), "Invalid pausers");
    }

    function testPauserCanNotRevokePauser() public {
        vm.prank(pauser);
        vm.expectRevert(ERROR_NOT_ADMIN);
        proxy.revokePauser(pauser);
    }

    function testArbitraryUserCanNotRevokePauser() public {
        vm.expectRevert(ERROR_NOT_ADMIN);
        proxy.revokePauser(pauser);
    }

    function testGrantingPauserToPauserReverts() public {
        vm.prank(admin);
        vm.expectRevert("Address already is a pauser");
        proxy.grantPauser(pauser);
    }

    function testRevokingPauserFromNotPauserReverts() public {
        vm.prank(admin);
        vm.expectRevert("Address is not a pauser");
        proxy.revokePauser(user);
    }

    function testAdminCanPause() public {
        vm.prank(admin);
        proxy.pause();
        assertTrue(proxy.paused(), "Pausing failed");
    }

    function testPauserCanPause() public {
        vm.prank(pauser);
        proxy.pause();
        assertTrue(proxy.paused(), "Pausing failed");
    }

    function testArbitraryUserCanNotPause() public {
        vm.expectRevert(ERROR_NOT_ADMIN_OR_PAUSER);
        proxy.pause();
    }

    function testAdminCanUnpause() public {
        pause();
        vm.prank(admin);
        proxy.unpause();
        assertFalse(proxy.paused(), "Unpausing failed");
    }

    function testPauserCanUnpause() public {
        pause();
        vm.prank(pauser);
        proxy.unpause();
        assertFalse(proxy.paused(), "Unpausing failed");
    }

    function testArbitraryUserCanNotUnpause() public {
        pause();
        vm.expectRevert(ERROR_NOT_ADMIN_OR_PAUSER);
        proxy.unpause();
    }

    function testOnlyUnpausedContractCanBePaused() public {
        pause();
        vm.prank(admin);
        vm.expectRevert("Contract paused");
        proxy.pause();
    }

    function testOnlyPausedContractCanBeUnpaused() public {
        vm.prank(admin);
        vm.expectRevert("Contract not paused");
        proxy.unpause();
    }

    function testErc1967Slot() public {
        // Values taken from [EIP-1967](https://eips.ethereum.org/EIPS/eip-1967)
        string memory name = "eip1967.proxy.implementation";
        bytes32 expected = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(proxy.erc1967Slot(name), expected, "Invalid EIP-1967 slot");
    }
}
