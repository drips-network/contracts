// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {ERC20DripsHubUser, ManagedDripsHubUser} from "./DripsHubUser.t.sol";
import {ManagedDripsHubTest} from "./ManagedDripsHub.t.sol";
import {ERC20Reserve, IERC20Reserve} from "../ERC20Reserve.sol";
import {ERC20DripsHub} from "../ERC20DripsHub.sol";
import {ManagedDripsHubProxy} from "../ManagedDripsHub.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20DripsHubTest is ManagedDripsHubTest {
    ERC20DripsHub private dripsHub;

    function setUp() public {
        IERC20 erc20 = new ERC20PresetFixedSupply("test", "test", 10**6 * 1 ether, address(this));
        ERC20Reserve reserve = new ERC20Reserve(erc20, address(this), address(0));
        ERC20DripsHub hubLogic = new ERC20DripsHub(10, erc20, reserve);
        dripsHub = ERC20DripsHub(address(wrapInProxy(hubLogic)));
        reserve.setUser(address(dripsHub));
        ManagedDripsHubTest.setUp(dripsHub);
    }

    function createManagedUser() internal override returns (ManagedDripsHubUser user) {
        user = new ERC20DripsHubUser(dripsHub);
        dripsHub.erc20().transfer(address(user), 100 ether);
    }

    function testContractCanBeUpgraded() public override {
        uint64 newCycleLength = dripsHub.cycleSecs() + 1;
        ERC20DripsHub newLogic = new ERC20DripsHub(
            newCycleLength,
            dripsHub.erc20(),
            dripsHub.reserve()
        );
        admin.upgradeTo(address(newLogic));
        assertEq(dripsHub.cycleSecs(), newCycleLength, "Invalid new cycle length");
    }
}
