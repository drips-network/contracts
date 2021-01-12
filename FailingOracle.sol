// SPDX-License-Identifier: GPL-3.0-only
// solhint-disable no-empty-blocks
pragma solidity ^0.7.5;

import "./PriceOracle.sol";

contract FailingOracle is PriceOracle {
    constructor() {}

    function updatePrices() public override {}

    function consultUsdEth(uint256 _usdAmount) public view override returns (uint256) {
        revert("FailingOracle::consultUsdEth: this oracle always fails");
    }
}
