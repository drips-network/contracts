// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.12;

import "./PriceOracle.sol";
import "./FixedWindowOracle.sol";

contract StablePriceOracle is PriceOracle {
    /// Uniswap USD/ETH price oracle.
    FixedWindowOracle public usdEthOracle;

    constructor(address _usdEthOracle) public {
        usdEthOracle = FixedWindowOracle(_usdEthOracle);
    }

    function updatePrices() public override {
        usdEthOracle.update();
    }

    function consultUsdEth(uint256 usdAmount) public override view returns (uint256) {
        return usdEthOracle.consult(usdAmount);
    }
}
