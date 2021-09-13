// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import "ds-test/test.sol";

interface Hevm {
    function warp(uint256) external;
}
contract BaseTest is DSTest {

    uint constant SECONDS_PER_YEAR = 31536000;
    uint64 constant CYCLE_SECS = 30 days;
    uint constant TOLERANCE = 10 ** 10;

    function fundingInSeconds(uint fundingPerCycle) public pure returns(uint) {
        return fundingPerCycle/CYCLE_SECS;
    }
}
