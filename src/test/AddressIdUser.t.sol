// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.13;

import {DripsHub, DripsReceiver, SplitsReceiver} from "../DripsHub.sol";
import {AddressId} from "../AddressId.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract AddressIdUser {
    AddressId private immutable addressId;
    uint256 public immutable userId;

    constructor(AddressId addressId_) {
        addressId = addressId_;
        userId = addressId_.calcUserId(address(this));
    }

    function setDrips(
        IERC20 erc20,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) erc20.approve(address(addressId), uint128(balanceDelta));
        return addressId.setDrips(erc20, currReceivers, balanceDelta, newReceivers);
    }

    function give(
        uint256 receiver,
        IERC20 erc20,
        uint128 amt
    ) public {
        erc20.approve(address(addressId), amt);
        addressId.give(receiver, erc20, amt);
    }

    function setSplits(SplitsReceiver[] calldata receivers) public {
        addressId.setSplits(receivers);
    }

    function collectAll(
        address user,
        IERC20 erc20,
        SplitsReceiver[] calldata currReceivers
    ) public returns (uint128 collected, uint128 splitAmt) {
        return addressId.collectAll(user, erc20, currReceivers);
    }

    function collect(address user, IERC20 erc20) public returns (uint128 amt) {
        return addressId.collect(user, erc20);
    }
}
