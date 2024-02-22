// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {DripsLib} from "src/DripsLib.sol";
import {Test} from "forge-std/Test.sol";

contract DripsLibTest is Test {
    function assertMinAmtPerSec(uint32 cycleSecs, uint160 expectedMinAmtPerSec) internal {
        assertEq(
            DripsLib.minAmtPerSec(cycleSecs),
            expectedMinAmtPerSec,
            string.concat("Invalid minAmtPerSec for cycleSecs ", vm.toString(cycleSecs))
        );
    }

    function testMinAmtPerSec() public {
        assertMinAmtPerSec(2, 500_000_000);
        assertMinAmtPerSec(3, 333_333_334);
        assertMinAmtPerSec(10, 100_000_000);
        assertMinAmtPerSec(11, 90_909_091);
        assertMinAmtPerSec(999_999_999, 2);
        assertMinAmtPerSec(1_000_000_000, 1);
        assertMinAmtPerSec(1_000_000_001, 1);
        assertMinAmtPerSec(2_000_000_000, 1);
    }
}
