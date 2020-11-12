// SPDX-License-Identifier: GPL-3.0-only
// solhint-disable no-empty-blocks
pragma solidity ^0.7.5;

import "./PriceOracle.sol";

contract DummyPriceOracle is PriceOracle {
    uint256 private price;

    constructor(uint256 _price) {
        set(_price);
    }

    function set(uint256 _price) public {
        price = _price;
    }

    function updatePrices() public override {}

    function consultUsdEth(uint256 usdAmount) public view override returns (uint256) {
        return usdAmount * price;
    }
}
