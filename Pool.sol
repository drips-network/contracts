// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.2;

contract Pool {
    struct Sender {
        uint256 balance;
    }

    mapping(address => Sender) internal senders;

    function topUp() public payable {
        topUpSender(msg.sender);
    }

    function topUpSender(address sender) public payable {
        senders[sender].balance += msg.value;
    }

    function withdraw(uint256 value) public {
        withdrawTo(value, msg.sender);
    }

    function withdrawTo(uint256 value, address payable receiver) public {
        uint256 balance = senders[msg.sender].balance;
        require(value <= balance, "Not enough funds in account");
        balance -= value;
        senders[msg.sender].balance = balance;
        receiver.transfer(value);
    }
}
