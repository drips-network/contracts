// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {DripsHub} from "../DripsHub.sol";
import {ManagedDripsHub} from "../ManagedDripsHub.sol";
import {SplitsReceiver, ERC20DripsHub, DripsReceiver, IERC20} from "../ERC20DripsHub.sol";

abstract contract DripsHubUser {
    DripsHub private immutable dripsHub;

    constructor(DripsHub dripsHub_) {
        dripsHub = dripsHub_;
    }

    function balance(uint256 assetId) public view virtual returns (uint256);

    function setDrips(
        uint256 userId,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function give(
        uint256 userId,
        uint256 receiver,
        uint256 assetId,
        uint128 amt
    ) public virtual;

    function setSplits(uint256 userId, SplitsReceiver[] calldata receivers) public virtual;

    function collectAll(
        uint256 userId,
        uint256 assetId,
        SplitsReceiver[] calldata currReceivers
    ) public returns (uint128 collected, uint128 splitAmt) {
        return dripsHub.collectAll(userId, assetId, currReceivers);
    }

    function collectableAll(
        uint256 userId,
        uint256 assetId,
        SplitsReceiver[] calldata currReceivers
    ) public view returns (uint128 collected, uint128 splitAmt) {
        return dripsHub.collectableAll(userId, assetId, currReceivers);
    }

    function receivableDripsCycles(uint256 userId, uint256 assetId)
        public
        view
        returns (uint64 cycles)
    {
        return dripsHub.receivableDripsCycles(userId, assetId);
    }

    function receivableDrips(
        uint256 userId,
        uint256 assetId,
        uint64 maxCycles
    ) public view returns (uint128 receivableAmt, uint64 receivableCycles) {
        return dripsHub.receivableDrips(userId, assetId, maxCycles);
    }

    function receiveDrips(
        uint256 userId,
        uint256 assetId,
        uint64 maxCycles
    ) public returns (uint128 receivedAmt, uint64 receivableCycles) {
        return dripsHub.receiveDrips(userId, assetId, maxCycles);
    }

    function splittable(uint256 userId, uint256 assetId) public view returns (uint128 amt) {
        return dripsHub.splittable(userId, assetId);
    }

    function split(
        uint256 userId,
        uint256 assetId,
        SplitsReceiver[] memory currReceivers
    ) public virtual returns (uint128 collectableAmt, uint128 splitAmt) {
        return dripsHub.split(userId, assetId, currReceivers);
    }

    function collectable(uint256 userId, uint256 assetId) public view returns (uint128 amt) {
        return dripsHub.collectable(userId, assetId);
    }

    function collect(uint256 userId, uint256 assetId) public virtual returns (uint128 aamt) {
        return dripsHub.collect(userId, assetId);
    }

    function hashDrips(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata receivers
    ) public view returns (bytes32) {
        return dripsHub.hashDrips(lastUpdate, lastBalance, receivers);
    }

    function dripsHash(uint256 userId, uint256 assetId) public view returns (bytes32 weightsHash) {
        return dripsHub.dripsHash(userId, assetId);
    }

    function hashSplits(SplitsReceiver[] calldata receivers) public view returns (bytes32) {
        return dripsHub.hashSplits(receivers);
    }

    function splitsHash(uint256 userId) public view returns (bytes32) {
        return dripsHub.splitsHash(userId);
    }
}

abstract contract ManagedDripsHubUser is DripsHubUser {
    ManagedDripsHub private immutable dripsHub;

    constructor(ManagedDripsHub dripsHub_) DripsHubUser(dripsHub_) {
        dripsHub = dripsHub_;
    }

    function admin() public view returns (address) {
        return dripsHub.admin();
    }

    function changeAdmin(address newAdmin) public {
        dripsHub.changeAdmin(newAdmin);
    }

    function paused() public view returns (bool) {
        return dripsHub.paused();
    }

    function pause() public {
        dripsHub.pause();
    }

    function unpause() public {
        dripsHub.unpause();
    }

    function upgradeTo(address newImplementation) public {
        dripsHub.upgradeTo(newImplementation);
    }
}

contract ERC20DripsHubUser is ManagedDripsHubUser {
    ERC20DripsHub private immutable dripsHub;

    constructor(ERC20DripsHub dripsHub_) ManagedDripsHubUser(dripsHub_) {
        dripsHub = dripsHub_;
    }

    function balance(uint256 assetId) public view override returns (uint256) {
        return IERC20(address(uint160(assetId))).balanceOf(address(this));
    }

    function setDrips(
        uint256 userId,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0)
            IERC20(address(uint160(assetId))).approve(address(dripsHub), uint128(balanceDelta));
        return
            dripsHub.setDrips(
                userId,
                assetId,
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    function give(
        uint256 userId,
        uint256 receiver,
        uint256 assetId,
        uint128 amt
    ) public override {
        IERC20(address(uint160(assetId))).approve(address(dripsHub), amt);
        dripsHub.give(userId, receiver, assetId, amt);
    }

    function setSplits(uint256 userId, SplitsReceiver[] calldata receivers) public override {
        dripsHub.setSplits(userId, receivers);
    }
}
