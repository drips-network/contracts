// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {DripsHub} from "../DripsHub.sol";
import {EthDripsHub} from "../EthDripsHub.sol";
import {ManagedDripsHub} from "../ManagedDripsHub.sol";
import {SplitsReceiver, ERC20DripsHub, DripsReceiver} from "../ERC20DripsHub.sol";

abstract contract DripsHubUser {
    DripsHub private immutable dripsHub;

    constructor(DripsHub dripsHub_) {
        dripsHub = dripsHub_;
    }

    function balance() public view virtual returns (uint256);

    function setDrips(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function setDrips(
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function give(address receiver, uint128 amt) public virtual;

    function give(
        uint256 account,
        address receiver,
        uint128 amt
    ) public virtual;

    function setSplits(
        SplitsReceiver[] calldata currReceivers,
        SplitsReceiver[] calldata newReceivers
    ) public virtual returns (uint128 collected, uint128 split);

    function collect(address receiver, SplitsReceiver[] calldata currReceivers)
        public
        returns (uint128 collected, uint128 split)
    {
        return dripsHub.collect(receiver, currReceivers);
    }

    function collectable(SplitsReceiver[] calldata currReceivers)
        public
        view
        returns (uint128 collected, uint128 split)
    {
        return dripsHub.collectable(address(this), currReceivers);
    }

    function flushableCycles() public view returns (uint64 flushable) {
        return dripsHub.flushableCycles(address(this));
    }

    function flushCycles(uint64 maxCycles) public returns (uint64 flushable) {
        return dripsHub.flushCycles(address(this), maxCycles);
    }

    function hashDrips(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata receivers
    ) public view returns (bytes32) {
        return dripsHub.hashDrips(lastUpdate, lastBalance, receivers);
    }

    function dripsHash() public view returns (bytes32) {
        return dripsHub.dripsHash(address(this));
    }

    function dripsHash(uint256 account) public view returns (bytes32 weightsHash) {
        return dripsHub.dripsHash(address(this), account);
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

    function balance() public view override returns (uint256) {
        return dripsHub.erc20().balanceOf(address(this));
    }

    function setDrips(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) dripsHub.erc20().approve(address(dripsHub), uint128(balanceDelta));
        return
            dripsHub.setDrips(lastUpdate, lastBalance, currReceivers, balanceDelta, newReceivers);
    }

    function setDrips(
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) dripsHub.erc20().approve(address(dripsHub), uint128(balanceDelta));
        return
            dripsHub.setDrips(
                account,
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    function give(address receiver, uint128 amt) public override {
        dripsHub.erc20().approve(address(dripsHub), amt);
        dripsHub.give(receiver, amt);
    }

    function give(
        uint256 account,
        address receiver,
        uint128 amt
    ) public override {
        dripsHub.erc20().approve(address(dripsHub), amt);
        dripsHub.give(account, receiver, amt);
    }

    function setSplits(
        SplitsReceiver[] calldata currReceivers,
        SplitsReceiver[] calldata newReceivers
    ) public override returns (uint128 collected, uint128 split) {
        return dripsHub.setSplits(currReceivers, newReceivers);
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

    function balance() public view override returns (uint256) {
        return address(this).balance;
    }

    function setDrips(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
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
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
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

    function give(address receiver, uint128 amt) public override {
        dripsHub.give{value: amt}(receiver);
    }

    function give(
        uint256 account,
        address receiver,
        uint128 amt
    ) public override {
        dripsHub.give{value: amt}(account, receiver);
    }

    function setSplits(
        SplitsReceiver[] calldata currReceivers,
        SplitsReceiver[] calldata newReceivers
    ) public override returns (uint128 collected, uint128 split) {
        return dripsHub.setSplits(currReceivers, newReceivers);
    }
}
