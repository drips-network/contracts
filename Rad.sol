// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Rad is ERC20 {
    /// Construct a new Rad token.
    ///
    /// @param account The initial account to grant all the tokens
    /// @param initialSupply The initial amount of Rad tokens.
    constructor(address account, uint256 initialSupply)
        public
        ERC20("Rad", "RAD")
    {
        _mint(account, initialSupply.mul(10**uint256(decimals())));
    }

    /// Burn the given amount of tokens from the sender account.
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}
