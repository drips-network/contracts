// spdx-license-identifier: MIT
pragma solidity ^0.7.5;

import "./PriceOracle.sol";
import "./FixedWindowOracle.sol";

contract StablePriceOracle is PriceOracle {
    /// Uniswap USD/ETH price oracle.
    FixedWindowOracle public usdEthOracle;

    constructor(address _usdEthOracle) {
        usdEthOracle = FixedWindowOracle(_usdEthOracle);
    }

    function updatePrices() public override {
        usdEthOracle.update();
    }

    function consultUsdEth(uint256 usdAmount) public view override returns (uint256) {
        return usdEthOracle.consult(usdAmount);
    }
}
