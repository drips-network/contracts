// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Create3} from "src/DripsDeployer.sol";
import {Test} from "forge-std/Test.sol";

contract Dummy {
    bytes public data;

    constructor(bytes memory data_) payable {
        require(keccak256(data_) != keccak256("revert"));
        data = data_;
    }
}

contract Create3Test is Test {
    function dummyCreationCode(bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(type(Dummy).creationCode, abi.encode(data));
    }

    function deployDummy(uint256 amount, bytes32 salt, bytes memory data) internal {
        Create3.deploy(amount, salt, dummyCreationCode(data));

        address dummy = Create3.computeAddress(salt);
        assertEq(dummy.code, type(Dummy).runtimeCode, "Invalid bytecode");
        assertEq(Dummy(dummy).data(), data, "Invalid data");
        assertEq(dummy.balance, amount, "Invalid balance");
    }

    function deployDummyExternal(uint256 amount, bytes32 salt, bytes memory data) external {
        Create3.deploy(amount, salt, dummyCreationCode(data));
    }

    function testDeploy() public {
        deployDummy(123, bytes32("salt"), "data");
    }

    function testDeployRevertsWhenSaltReused() public {
        bytes32 salt = bytes32(0);
        deployDummy(0, salt, "data 1");
        vm.expectRevert("Salt already used");
        this.deployDummyExternal(1, salt, "data 2");
    }

    function testDeployWithSaltReusedAfterFailedDeployment() public {
        bytes32 salt = bytes32(0);
        vm.expectRevert("Deployment failed");
        this.deployDummyExternal(0, salt, "revert");
        deployDummy(0, salt, "data");
    }

    function testDeployRevertsWhenConstructorReverts() public {
        vm.expectRevert("Deployment failed");
        this.deployDummyExternal(0, bytes32(0), "revert");
    }

    function testComputeAddress() public view {
        bytes32 salt = bytes32("salt");
        bytes32 otherSalt = bytes32("other salt");
        require(
            Create3.computeAddress(salt, address(this)) == Create3.computeAddress(salt),
            "Different addresses for this"
        );
        require(
            Create3.computeAddress(salt) != Create3.computeAddress(otherSalt),
            "Same address for different salts"
        );
        require(
            Create3.computeAddress(salt, address(1)) != Create3.computeAddress(salt, address(2)),
            "Same address for different deployers"
        );
    }
}
