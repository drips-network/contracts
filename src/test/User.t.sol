// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {EthPool, Pool} from "../EthPool.sol";
import {DripsReceiver, ERC20Pool, Receiver} from "../ERC20Pool.sol";

abstract contract PoolUser {
    function getPool() internal view virtual returns (Pool);

    function balance() public view virtual returns (uint256);

    function updateSender(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function updateSubSender(
        uint256 subSenderId,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function give(address receiver, uint128 amt) public virtual;

    function giveFromSubSender(
        uint256 subSenderId,
        address receiver,
        uint128 amt
    ) public virtual;

    function setDripsReceivers(
        DripsReceiver[] calldata currReceivers,
        DripsReceiver[] calldata newReceivers
    ) public virtual returns (uint128 collected, uint128 dripped);

    function collect(address receiverAddr, DripsReceiver[] calldata currReceivers)
        public
        returns (uint128 collected, uint128 dripped)
    {
        return getPool().collect(receiverAddr, currReceivers);
    }

    function collectable(DripsReceiver[] calldata currReceivers)
        public
        view
        returns (uint128 collected, uint128 dripped)
    {
        return getPool().collectable(address(this), currReceivers);
    }

    function flushableCycles() public view returns (uint64 flushable) {
        return getPool().flushableCycles(address(this));
    }

    function flushCycles(uint64 maxCycles) public returns (uint64 flushable) {
        return getPool().flushCycles(address(this), maxCycles);
    }

    function withdrawable(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers
    ) public view returns (uint128) {
        return getPool().withdrawable(address(this), lastUpdate, lastBalance, currReceivers);
    }

    function withdrawableSubSender(
        uint256 subSenderId,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers
    ) public view returns (uint128) {
        return
            getPool().withdrawableSubSender(
                address(this),
                subSenderId,
                lastUpdate,
                lastBalance,
                currReceivers
            );
    }

    function hashSenderState(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata receivers
    ) public view returns (bytes32) {
        return getPool().hashSenderState(lastUpdate, lastBalance, receivers);
    }

    function senderStateHash() public view returns (bytes32) {
        return getPool().senderStateHash(address(this));
    }

    function subSenderStateHash(uint256 subSenderId) public view returns (bytes32 weightsHash) {
        return getPool().subSenderStateHash(address(this), subSenderId);
    }

    function hashDripsReceivers(DripsReceiver[] calldata receivers) public view returns (bytes32) {
        return getPool().hashDripsReceivers(receivers);
    }

    function dripsReceiversHash() public view returns (bytes32) {
        return getPool().dripsReceiversHash(address(this));
    }
}

contract ERC20PoolUser is PoolUser {
    ERC20Pool internal immutable pool;

    constructor(ERC20Pool pool_) {
        pool = pool_;
    }

    function getPool() internal view override returns (Pool) {
        return Pool(pool);
    }

    function balance() public view override returns (uint256) {
        return pool.erc20().balanceOf(address(this));
    }

    function updateSender(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) pool.erc20().approve(address(pool), uint128(balanceDelta));
        return
            pool.updateSender(lastUpdate, lastBalance, currReceivers, balanceDelta, newReceivers);
    }

    function updateSubSender(
        uint256 subSenderId,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) pool.erc20().approve(address(pool), uint128(balanceDelta));
        return
            pool.updateSubSender(
                subSenderId,
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    function give(address receiver, uint128 amt) public override {
        pool.erc20().approve(address(pool), amt);
        pool.give(receiver, amt);
    }

    function giveFromSubSender(
        uint256 subSenderId,
        address receiver,
        uint128 amt
    ) public override {
        pool.erc20().approve(address(pool), amt);
        pool.giveFromSubSender(subSenderId, receiver, amt);
    }

    function setDripsReceivers(
        DripsReceiver[] calldata currReceivers,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 collected, uint128 dripped) {
        return pool.setDripsReceivers(currReceivers, newReceivers);
    }
}

contract EthPoolUser is PoolUser {
    EthPool internal immutable pool;

    constructor(EthPool pool_) payable {
        pool = pool_;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function getPool() internal view override returns (Pool) {
        return Pool(pool);
    }

    function balance() public view override returns (uint256) {
        return address(this).balance;
    }

    function updateSender(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        uint256 value = balanceDelta > 0 ? uint128(balanceDelta) : 0;
        uint128 reduceBalance = balanceDelta < 0 ? uint128(uint136(-int136(balanceDelta))) : 0;
        return
            pool.updateSender{value: value}(
                lastUpdate,
                lastBalance,
                currReceivers,
                reduceBalance,
                newReceivers
            );
    }

    function updateSubSender(
        uint256 subSenderId,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        uint256 value = balanceDelta > 0 ? uint128(balanceDelta) : 0;
        uint128 reduceBalance = balanceDelta < 0 ? uint128(-balanceDelta) : 0;
        return
            pool.updateSubSender{value: value}(
                subSenderId,
                lastUpdate,
                lastBalance,
                currReceivers,
                reduceBalance,
                newReceivers
            );
    }

    function give(address receiver, uint128 amt) public override {
        pool.give{value: amt}(receiver);
    }

    function giveFromSubSender(
        uint256 subSenderId,
        address receiver,
        uint128 amt
    ) public override {
        pool.giveFromSubSender{value: amt}(subSenderId, receiver);
    }

    function setDripsReceivers(
        DripsReceiver[] calldata currReceivers,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 collected, uint128 dripped) {
        return pool.setDripsReceivers(currReceivers, newReceivers);
    }
}
