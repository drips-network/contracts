// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IERC20Reserve {
    function erc20() external view returns (IERC20);

    function withdraw(uint256 amt) external;

    function deposit(uint256 amt) external;
}

contract ERC20Reserve is IERC20Reserve, Ownable {
    IERC20 public immutable override erc20;
    address public user;
    uint256 public balance;

    event Withdrawn(address to, uint256 amt);
    event Deposited(address from, uint256 amt);
    event ForceWithdrawn(address to, uint256 amt);
    event UserSet(address oldUser, address newUser);

    constructor(
        IERC20 _erc20,
        address owner,
        address _user
    ) {
        erc20 = _erc20;
        setUser(_user);
        transferOwnership(owner);
    }

    modifier onlyUser() {
        require(_msgSender() == user, "Reserve: caller is not the user");
        _;
    }

    function withdraw(uint256 amt) public override onlyUser {
        require(balance >= amt, "Reserve: withdrawal over balance");
        balance -= amt;
        emit Withdrawn(_msgSender(), amt);
        require(erc20.transfer(_msgSender(), amt), "Reserve: transfer failed");
    }

    function deposit(uint256 amt) public override onlyUser {
        balance += amt;
        emit Deposited(_msgSender(), amt);
        require(erc20.transferFrom(_msgSender(), address(this), amt), "Reserve: transfer failed");
    }

    function forceWithdraw(uint256 amt) public onlyOwner {
        emit ForceWithdrawn(_msgSender(), amt);
        require(erc20.transfer(_msgSender(), amt), "Reserve: transfer failed");
    }

    function setUser(address newUser) public onlyOwner {
        emit UserSet(user, newUser);
        user = newUser;
    }
}
