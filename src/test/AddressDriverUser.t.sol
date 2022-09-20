// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.15;

import {DripsHistory, DripsHub, DripsReceiver, SplitsReceiver} from "../DripsHub.sol";
import {AddressDriver} from "../AddressDriver.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract AddressDriverUser {
    AddressDriver private immutable addressDriver;
    uint256 public immutable userId;

    constructor(AddressDriver addressDriver_) {
        addressDriver = addressDriver_;
        userId = addressDriver_.calcUserId(address(this));
    }

    function squeezeDrips(
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) public returns (uint128 amt, uint32 nextSqueezed) {
        return addressDriver.squeezeDrips(erc20, senderId, historyHash, dripsHistory);
    }

    function setDrips(
        IERC20 erc20,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers,
        address transferTo
    ) public returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) {
            erc20.approve(address(addressDriver), uint128(balanceDelta));
        }
        return addressDriver.setDrips(erc20, currReceivers, balanceDelta, newReceivers, transferTo);
    }

    function give(uint256 receiver, IERC20 erc20, uint128 amt) public {
        erc20.approve(address(addressDriver), amt);
        addressDriver.give(receiver, erc20, amt);
    }

    function setSplits(SplitsReceiver[] calldata receivers) public {
        addressDriver.setSplits(receivers);
    }

    function collect(IERC20 erc20, address transferTo) public returns (uint128 amt) {
        return addressDriver.collect(erc20, transferTo);
    }
}
