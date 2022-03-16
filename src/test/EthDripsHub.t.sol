// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {EthDripsHubUser, ManagedDripsHubUser} from "./DripsHubUser.t.sol";
import {ManagedDripsHubTest} from "./ManagedDripsHub.t.sol";
import {EthDripsHub} from "../EthDripsHub.sol";
import {ManagedDripsHubProxy} from "../ManagedDripsHub.sol";

contract EthDripsHubTest is ManagedDripsHubTest {
    EthDripsHub private dripsHub;

    function setUp() public {
        EthDripsHub hubLogic = new EthDripsHub(10);
        dripsHub = EthDripsHub(address(wrapInProxy(hubLogic)));
        ManagedDripsHubTest.setUp(dripsHub);
    }

    function createManagedUser() internal override returns (ManagedDripsHubUser) {
        return new EthDripsHubUser{value: 100 ether}(dripsHub);
    }

    function testContractCanBeUpgraded() public override {
        uint64 newCycleLength = dripsHub.cycleSecs() + 1;
        EthDripsHub newLogic = new EthDripsHub(newCycleLength);
        admin.upgradeTo(address(newLogic));
        assertEq(dripsHub.cycleSecs(), newCycleLength, "Invalid new cycle length");
    }

    function testRevertsIfBalanceReductionAndValueNonZero() public {
        try
            dripsHub.setDrips{value: 1}(
                calcUserId(address(this)),
                0,
                0,
                dripsReceivers(),
                1,
                dripsReceivers()
            )
        {
            assertTrue(false, "Set drips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(
                reason,
                "Both message value and balance reduction non-zero",
                "Invalid set drips revert reason"
            );
        }
    }
}
