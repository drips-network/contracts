// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Reserve, IReserve, IReservePlugin} from "../../src/Reserve.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";


contract ReserveHarness is Reserve {
    constructor(address owner) Reserve(owner) {}

    function getIsUser(address user
    ) public view returns (bool result) {
        result = isUser[user];
    }

    function getDeposited(IERC20 token
    ) public view returns (uint256 result) {
        result = deposited[token];
    }

    function getPlugins(IERC20 token
    ) public view returns (IReservePlugin result) {
        result = plugins[token];
    }
}