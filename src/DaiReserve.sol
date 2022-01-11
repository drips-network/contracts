// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {ERC20Reserve, IERC20Reserve} from "./ERC20Reserve.sol";
import {IDai} from "./IDai.sol";

interface IDaiReserve is IERC20Reserve {
    function dai() external view returns (IDai);
}

contract DaiReserve is ERC20Reserve, IDaiReserve {
    IDai public immutable override dai;

    constructor(
        IDai _dai,
        address owner,
        address user
    ) ERC20Reserve(_dai, owner, user) {
        dai = _dai;
    }
}
