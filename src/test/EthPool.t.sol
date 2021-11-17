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

    function testRevertsIfBalanceReductionAndValueNonZero() public {
        try pool.updateSender{value: 1}(0, 0, receivers(), 1, receivers()) {
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
