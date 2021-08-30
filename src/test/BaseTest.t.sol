// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "./User.t.sol";

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

    // assert equal two variables with a wei tolerance
    function assertEqTol(uint actual, uint expected, bytes32 msg_) public {
        uint diff;
        if (actual > expected) {
            diff = actual -expected;
        } else {
            diff = expected - actual;
        }
        if (diff > TOLERANCE) {
            emit log_named_bytes32(string(abi.encodePacked(msg_)), "Assert Equal Failed");
            emit log_named_uint("Expected", expected);
            emit log_named_uint("Actual  ", actual);
            emit log_named_uint("Diff    ", diff);

        }
        assertTrue(diff <= TOLERANCE);
    }
}
