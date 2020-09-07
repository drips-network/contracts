// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.12;

interface PriceOracle {
    /// Get the latest price known to the oracle.
    function latestPrice() external view returns (int256);
}
