// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

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

    function balance(uint256 assetId) public view returns (uint256) {
        return _erc20(assetId).balanceOf(address(this));
    }

    function setDrips(
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public returns (uint128 newBalance, int128 realBalanceDelta) {
        IERC20 erc20 = _erc20(assetId);
        if (balanceDelta > 0) erc20.approve(address(addressId), uint128(balanceDelta));
        return
            addressId.setDrips(
                erc20,
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    function give(
        uint256 receiver,
        uint256 assetId,
        uint128 amt
    ) public {
        IERC20 erc20 = _erc20(assetId);
        erc20.approve(address(addressId), amt);
        addressId.give(receiver, erc20, amt);
    }

    function setSplits(SplitsReceiver[] calldata receivers) public {
        addressId.setSplits(receivers);
    }

    function collectAll(
        address user,
        uint256 assetId,
        SplitsReceiver[] calldata currReceivers
    ) public returns (uint128 collected, uint128 splitAmt) {
        return addressId.collectAll(user, _erc20(assetId), currReceivers);
    }

    function collect(address user, uint256 assetId) public returns (uint128 amt) {
        return addressId.collect(user, _erc20(assetId));
    }

    function _erc20(uint256 assetId) internal pure returns (IERC20) {
        return IERC20(address(uint160(assetId)));
    }
}
