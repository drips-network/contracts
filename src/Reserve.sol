// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IReserve {
    function withdraw(
        IERC20 token,
        address to,
        uint256 amt
    ) external;

    function deposit(
        IERC20 token,
        address from,
        uint256 amt
    ) external;
}

contract Reserve is IReserve, Ownable {
    mapping(address => bool) public isUser;
    mapping(IERC20 => uint256) public withdrawable;

    event Withdrawn(address user, IERC20 indexed token, address indexed to, uint256 amt);
    event Deposited(address user, IERC20 indexed token, address indexed from, uint256 amt);
    event ForceWithdrawn(address owner, IERC20 indexed token, address indexed to, uint256 amt);
    event UserAdded(address owner, address indexed user);
    event UserRemoved(address owner, address indexed user);

    constructor(address owner) {
        transferOwnership(owner);
    }

    modifier onlyUser() {
        require(isUser[msg.sender], "Reserve: caller is not the user");
        _;
    }

    function withdraw(
        IERC20 token,
        address to,
        uint256 amt
    ) public override onlyUser {
        uint256 balance = withdrawable[token];
        require(balance >= amt, "Reserve: withdrawal over balance");
        withdrawable[token] = balance - amt;
        require(token.transfer(to, amt), "Reserve: transfer failed");
        emit Withdrawn(msg.sender, token, to, amt);
    }

    function deposit(
        IERC20 token,
        address from,
        uint256 amt
    ) public override onlyUser {
        withdrawable[token] += amt;
        require(token.transferFrom(from, address(this), amt), "Reserve: transfer failed");
        emit Deposited(msg.sender, token, from, amt);
    }

    function forceWithdraw(
        IERC20 token,
        address to,
        uint256 amt
    ) public onlyOwner {
        require(token.transfer(to, amt), "Reserve: transfer failed");
        emit ForceWithdrawn(msg.sender, token, to, amt);
    }

    function addUser(address user) public onlyOwner {
        isUser[user] = true;
        emit UserAdded(msg.sender, user);
    }

    function removeUser(address user) public onlyOwner {
        isUser[user] = false;
        emit UserRemoved(msg.sender, user);
    }
}
