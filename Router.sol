// SPDX-License-Identifier: GPL-3.0-only
// solhint-disable func-name-mixedcase
pragma solidity ^0.7.5;

/// The router is a subset of the `UniswapV2Router` interface.
interface Router {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function WETH() external pure returns (address);
}
