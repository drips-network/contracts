//SPDX-License-Identifier: ISC
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Rad is ERC20 {
    constructor(uint256 initialBalance) public ERC20("Rad", "RAD") {
        _mint(msg.sender, initialBalance);
    }
}
