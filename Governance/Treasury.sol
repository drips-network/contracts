// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

/// A simple treasury controlled by an admin account.
contract Treasury {
    /// The contract admin.
    address public admin;

    /// Construct a new treasury with an admin.
    constructor(address _admin) {
        admin = _admin;
    }

    /// Withdraw ETH from the treasury.
    function withdraw(address payable recipient, uint256 amount) public {
        require(msg.sender == admin, "Treasury::withdraw: only the admin can withdraw");
        require(amount <= address(this).balance, "Treasury::withdraw: insufficient balance");

        recipient.transfer(amount);
    }

    /// Receive ETH through here.
    receive() external payable {}
}
