// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DripsHubUser, ERC20DripsHubUser} from "./DripsHubUser.t.sol";
import {DripsHubTest} from "./EthDripsHub.t.sol";
import {ERC20Reserve, IERC20Reserve} from "../ERC20Reserve.sol";
import {ERC20DripsHub} from "../ERC20DripsHub.sol";
import {ManagedDripsHubProxy} from "../ManagedDripsHub.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import "ds-test/test.sol";

contract ERC20DripsHubTest is DripsHubTest {
    ERC20DripsHub private dripsHub;

    function setUp() public {
        address owner = address(this);
        IERC20 erc20 = new ERC20PresetFixedSupply("test", "test", 10**6 * 1 ether, owner);
        ERC20DripsHub hubLogic = new ERC20DripsHub(10, erc20);
        ManagedDripsHubProxy proxy = new ManagedDripsHubProxy(hubLogic, owner);
        dripsHub = ERC20DripsHub(address(proxy));
        ERC20Reserve reserve = new ERC20Reserve(erc20, owner, address(dripsHub));
        dripsHub.setReserve(reserve);
        setUp(dripsHub);
    }

    function createUser() internal override returns (DripsHubUser user) {
        user = new ERC20DripsHubUser(dripsHub);
        dripsHub.erc20().transfer(address(user), 100 ether);
    }
}
