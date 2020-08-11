//SPDX-License-Identifier: ISC
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(string memory symbol, uint256 initialBalance)
        public
        ERC20(symbol, symbol)
    {
        _mint(msg.sender, initialBalance);
    }
}
