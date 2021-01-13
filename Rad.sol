// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract Rad is ERC20Burnable {
    using SafeMath for uint256;

    /// Construct a new Radicle token.
    ///
    /// @param account The initial account to grant all the tokens
    /// @param initialSupply The initial amount of Radicle tokens.
    constructor(address account, uint256 initialSupply) ERC20("Radicle", "RADICLE") {
        _mint(account, initialSupply.mul(10**uint256(decimals())));
    }
}
