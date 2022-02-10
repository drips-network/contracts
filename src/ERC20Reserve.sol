// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IERC20Reserve {
    function withdraw(IERC20 token, uint256 amt) external;

    function deposit(IERC20 token, uint256 amt) external;
}

contract ERC20Reserve is IERC20Reserve, Ownable {
    mapping(address => bool) public isUser;
    mapping(IERC20 => uint256) public withdrawable;

    event Withdrawn(address indexed user, IERC20 indexed token, uint256 amt);
    event Deposited(address indexed user, IERC20 indexed token, uint256 amt);
    event ForceWithdrawn(address indexed owner, IERC20 indexed token, uint256 amt);
    event UserAdded(address indexed owner, address indexed user);
    event UserRemoved(address indexed owner, address indexed user);

    constructor(address owner) {
        transferOwnership(owner);
    }

    modifier onlyUser() {
        require(isUser[msg.sender], "Reserve: caller is not the user");
        _;
    }

    function withdraw(IERC20 token, uint256 amt) public override onlyUser {
        uint256 balance = withdrawable[token];
        require(balance >= amt, "Reserve: withdrawal over balance");
        withdrawable[token] = balance - amt;
        require(token.transfer(msg.sender, amt), "Reserve: transfer failed");
        emit Withdrawn(msg.sender, token, amt);
    }

    function deposit(IERC20 token, uint256 amt) public override onlyUser {
        withdrawable[token] += amt;
        require(token.transferFrom(msg.sender, address(this), amt), "Reserve: transfer failed");
        emit Deposited(msg.sender, token, amt);
    }

    function forceWithdraw(IERC20 token, uint256 amt) public onlyOwner {
        require(token.transfer(msg.sender, amt), "Reserve: transfer failed");
        emit ForceWithdrawn(msg.sender, token, amt);
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
