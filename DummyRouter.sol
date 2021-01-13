// spdx-license-identifier: gpl-3.0-only
// solhint-disable func-name-mixedcase
pragma solidity ^0.7.5;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Router.sol";

contract DummyRouter is Router {
    IERC20 private rad;

    constructor(address _rad) {
        rad = IERC20(_rad);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata,
        address to,
        uint256
    ) external payable override returns (uint256[] memory) {
        require(msg.value > 0, "Swap amount should be positive");

        uint256 tokenAmount = msg.value;

        rad.transfer(to, tokenAmount);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = tokenAmount;

        require(tokenAmount >= amountOutMin, "Token amount swapped should be greater than minimum");

        return amounts;
    }

    function WETH() external pure override returns (address) {
        return address(0x123456789abcdef);
    }
}
