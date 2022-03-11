// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {DripsHub} from "../DripsHub.sol";
import {EthDripsHub} from "../EthDripsHub.sol";
import {ManagedDripsHub} from "../ManagedDripsHub.sol";
import {SplitsReceiver, ERC20DripsHub, DripsReceiver, IERC20} from "../ERC20DripsHub.sol";

abstract contract DripsHubUser {
    DripsHub private immutable dripsHub;

    constructor(DripsHub dripsHub_) {
        dripsHub = dripsHub_;
    }

    function balance(uint256 assetId) public view virtual returns (uint256);

    function setDrips(
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function setDrips(
        uint256 account,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function give(
        address receiver,
        uint256 assetId,
        uint128 amt
    ) public virtual;

    function give(
        uint256 account,
        address receiver,
        uint256 assetId,
        uint128 amt
    ) public virtual;

    function setSplits(SplitsReceiver[] calldata receivers) public virtual;

    function collectAll(uint256 assetId, SplitsReceiver[] calldata currReceivers)
        public
        returns (uint128 collected, uint128 splitAmt)
    {
        return dripsHub.collectAll(assetId, currReceivers);
    }

    function collectableAll(uint256 assetId, SplitsReceiver[] calldata currReceivers)
        public
        view
        returns (uint128 collected, uint128 splitAmt)
    {
        return dripsHub.collectableAll(address(this), assetId, currReceivers);
    }

    function receivableDripsCycles(uint256 assetId) public view returns (uint64 cycles) {
        return dripsHub.receivableDripsCycles(address(this), assetId);
    }

    function receivableDrips(uint256 assetId, uint64 maxCycles)
        public
        view
        returns (uint128 receivableAmt, uint64 receivableCycles)
    {
        return dripsHub.receivableDrips(address(this), assetId, maxCycles);
    }

    function receiveDrips(uint256 assetId, uint64 maxCycles)
        public
        returns (uint128 receivedAmt, uint64 receivableCycles)
    {
        return dripsHub.receiveDrips(address(this), assetId, maxCycles);
    }

    function splittable(address user, uint256 assetId) public view returns (uint128 amt) {
        return dripsHub.splittable(user, assetId);
    }

    function split(
        address user,
        uint256 assetId,
        SplitsReceiver[] memory currReceivers
    ) public virtual returns (uint128 collectableAmt, uint128 splitAmt) {
        return dripsHub.split(user, assetId, currReceivers);
    }

    function collectable(address user, uint256 assetId) public view returns (uint128 amt) {
        return dripsHub.collectable(user, assetId);
    }

    function collect(uint256 assetId) public virtual returns (uint128 aamt) {
        return dripsHub.collect(assetId);
    }

    function hashDrips(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata receivers
    ) public view returns (bytes32) {
        return dripsHub.hashDrips(lastUpdate, lastBalance, receivers);
    }

    function dripsHash(uint256 assetId) public view returns (bytes32) {
        return dripsHub.dripsHash(address(this), assetId);
    }

    function dripsHash(uint256 account, uint256 assetId) public view returns (bytes32 weightsHash) {
        return dripsHub.dripsHash(address(this), account, assetId);
    }

    function hashSplits(SplitsReceiver[] calldata receivers) public view returns (bytes32) {
        return dripsHub.hashSplits(receivers);
    }

    function splitsHash() public view returns (bytes32) {
        return dripsHub.splitsHash(address(this));
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
                assetId,
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    function setDrips(
        uint256 account,
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
                account,
                assetId,
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    function give(
        address receiver,
        uint256 assetId,
        uint128 amt
    ) public override {
        IERC20(address(uint160(assetId))).approve(address(dripsHub), amt);
        dripsHub.give(receiver, assetId, amt);
    }

    function give(
        uint256 account,
        address receiver,
        uint256 assetId,
        uint128 amt
    ) public override {
        IERC20(address(uint160(assetId))).approve(address(dripsHub), amt);
        dripsHub.give(account, receiver, assetId, amt);
    }

    function setSplits(SplitsReceiver[] calldata receivers) public override {
        dripsHub.setSplits(receivers);
    }
}

contract EthDripsHubUser is ManagedDripsHubUser {
    EthDripsHub private immutable dripsHub;

    constructor(EthDripsHub dripsHub_) payable ManagedDripsHubUser(dripsHub_) {
        dripsHub = dripsHub_;
    }

    receive() external payable {
        return;
    }

    function balance(uint256 assetId) public view override returns (uint256) {
        assetId;
        return address(this).balance;
    }

    function setDrips(
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        assetId;
        uint256 value = balanceDelta > 0 ? uint128(balanceDelta) : 0;
        uint128 reduceBalance = balanceDelta < 0 ? uint128(uint136(-int136(balanceDelta))) : 0;
        return
            dripsHub.setDrips{value: value}(
                lastUpdate,
                lastBalance,
                currReceivers,
                reduceBalance,
                newReceivers
            );
    }

    function setDrips(
        uint256 account,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        assetId;
        uint256 value = balanceDelta > 0 ? uint128(balanceDelta) : 0;
        uint128 reduceBalance = balanceDelta < 0 ? uint128(-balanceDelta) : 0;
        return
            dripsHub.setDrips{value: value}(
                account,
                lastUpdate,
                lastBalance,
                currReceivers,
                reduceBalance,
                newReceivers
            );
    }

    function give(
        address receiver,
        uint256 assetId,
        uint128 amt
    ) public override {
        assetId;
        dripsHub.give{value: amt}(receiver);
    }

    function give(
        uint256 account,
        address receiver,
        uint256 assetId,
        uint128 amt
    ) public override {
        assetId;
        dripsHub.give{value: amt}(account, receiver);
    }

    function setSplits(SplitsReceiver[] calldata receivers) public override {
        dripsHub.setSplits(receivers);
    }
}
