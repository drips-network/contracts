// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {PoolUser, EthPoolUser} from "./User.t.sol";
import {PoolTest} from "./Pool.t.sol";
import {EthPool} from "../EthPool.sol";

contract EthPoolTest is PoolTest {
    EthPool private pool;

    function setUp() public {
        pool = new EthPool(10);
        setUp(pool);
    }

    function createUser() internal override returns (PoolUser) {
        return new EthPoolUser{value: 100 ether}(pool);
    }
}
