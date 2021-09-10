// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.6;

import {PoolUser, ERC20PoolUser} from "./User.t.sol";
import {EthPoolTest} from "./EthPool.t.sol";
import {ERC20Pool, Pool} from "../ERC20Pool.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20PoolTest is EthPoolTest {

    ERC20Pool private pool;

    function setUp() public override {
        IERC20 erc20 = new ERC20PresetFixedSupply("test", "test", 10 ** 6 * 1 ether, address(this));
        pool = new ERC20Pool(CYCLE_SECS, erc20);
        super.setUp();
    }

    function getPool() internal override view returns (Pool) {
        return Pool(pool);
    }

    function createUser() internal override returns (PoolUser) {
        ERC20PoolUser user = new ERC20PoolUser(pool);
        pool.erc20().transfer(address(user), 100 ether);
        return PoolUser(user);
    }
}
