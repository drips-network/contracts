// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.12;

import "./PriceOracle.sol";

contract DummyPriceOracle is PriceOracle {
    int256 private price;

    constructor(int256 _price) public {
        set(_price);
    }

    function set(int256 _price) public {
        price = _price;
    }

    function latestPrice() public override view returns (int256) {
        return price;
    }
}
