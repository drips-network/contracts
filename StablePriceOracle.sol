// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.12;

// Mainnet ETHUSD: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
// Ropsten ETHUSD: 0x30B5068156688f818cEa0874B580206dFe081a03
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

import "./PriceOracle.sol";

contract StablePriceOracle is PriceOracle {
    /// Chainlink price oracle.
    AggregatorV3Interface public priceFeed;

    constructor(address _priceFeed) public {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function latestPrice() public override view returns (int256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return price;
    }
}
