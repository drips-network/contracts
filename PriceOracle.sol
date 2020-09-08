// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.12;

interface PriceOracle {
    function updatePrices() external;

    function consultUsdEth(uint256 usdAmount) external view returns (uint256);
}
