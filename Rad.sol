//SPDX-License-Identifier: ISC
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Rad is ERC20 {
    /*
     * @notice Construct a new Rad token.
     * @param account The initial account to grant all the tokens
     */
    constructor(address account, uint256 _totalSupply)
        public
        ERC20("Rad", "RAD")
    {
        _mint(account, _totalSupply.mul(10**uint256(decimals())));
    }
}
