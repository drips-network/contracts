// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

contract RandomUtils {
    bytes32 private seed;
    bool private initialized = false;

    function setSeed(bytes32 seed_) public {
        require(!initialized, "only init seed once per test run");
        seed = seed_;
        initialized = true;
    }

    function random(uint256 maxValue) public returns (uint256 value) {
        value = random();
        if (maxValue != type(uint256).max) value %= maxValue + 1;
    }

    function random() public returns (uint256 value) {
        require(initialized, "seed not set for test run");
        seed = keccak256(bytes.concat(seed));
        return uint256(seed);
    }
}
