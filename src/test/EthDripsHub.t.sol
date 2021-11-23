// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DripsHubUser, EthDripsHubUser} from "./DripsHubUser.t.sol";
import {DripsHubTest} from "./DripsHub.t.sol";
import {EthDripsHub} from "../EthDripsHub.sol";

contract EthDripsHubTest is DripsHubTest {
    EthDripsHub private dripsHub;

    function setUp() public {
        dripsHub = new EthDripsHub(10);
        setUp(dripsHub);
    }

    function createUser() internal override returns (DripsHubUser) {
        return new EthDripsHubUser{value: 100 ether}(dripsHub);
    }

    function testRevertsIfBalanceReductionAndValueNonZero() public {
        try dripsHub.updateSender{value: 1}(0, 0, receivers(), 1, receivers()) {
            assertTrue(false, "Update sender hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(
                reason,
                "Both message value and balance reduction non-zero",
                "Invalid update sender revert reason"
            );
        }
    }
}
