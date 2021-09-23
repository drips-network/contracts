// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {PoolUser, ERC20PoolUser} from "./User.t.sol";
import {PoolTest} from "./EthPool.t.sol";
import {ERC20Pool} from "../ERC20Pool.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20PoolTest is PoolTest {
    ERC20Pool private pool;

    function setUp() public {
        IERC20 erc20 = new ERC20PresetFixedSupply("test", "test", 10**6 * 1 ether, address(this));
        pool = new ERC20Pool(10, erc20);
        setUp(pool);
    }

    function createUser() internal override returns (PoolUser user) {
        user = new ERC20PoolUser(pool);
        pool.erc20().transfer(address(user), 100 ether);
    }
}
