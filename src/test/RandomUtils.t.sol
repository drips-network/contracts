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

    function randomUint128(uint128 maxValue) public returns (uint128) {
        return uint128(random(maxValue));
    }

    function randomUint128() public returns (uint128) {
        return randomUint128(type(uint128).max);
    }

    function randomUint32(uint32 range) public returns (uint32) {
        return uint32(random(range));
    }

    function randomUint32() public returns (uint32) {
        return randomUint32(type(uint32).max);
    }
}
