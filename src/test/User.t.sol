// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {EthPool, Pool} from "../EthPool.sol";
import {DripsReceiver, ERC20Pool, Receiver} from "../ERC20Pool.sol";

abstract contract PoolUser {
    function getPool() internal view virtual returns (Pool);

    function balance() public view virtual returns (uint256);

    function getDripsFractionMax() public view returns (uint32) {
        return getPool().MAX_DRIPS_FRACTION();
    }

    function updateSender(
        uint128 toppedUp,
        uint128 withdraw,
        uint32 dripsFraction,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) public virtual returns (uint128 withdrawn);

    function updateSubSender(
        uint256 subSenderId,
        uint128 toppedUp,
        uint128 withdraw,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) public virtual returns (uint128 withdrawn);

    function give(address receiver, uint128 amt) public virtual;

    function giveFromSubSender(
        uint256 subSenderId,
        address receiver,
        uint128 amt
    ) public virtual;

    function setDripsReceivers(
        DripsReceiver[] calldata currReceivers,
        DripsReceiver[] calldata newReceivers
    ) public virtual;

    function collect(address receiverAddr, Receiver[] calldata currReceivers)
        public
        returns (uint128 collected, uint128 dripped)
    {
        return getPool().collect(receiverAddr, currReceivers);
    }

    function collectable(Receiver[] calldata currReceivers)
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

    function withdrawable(Receiver[] calldata currReceivers) public view returns (uint128) {
        return getPool().withdrawable(address(this), currReceivers);
    }

    function withdrawableSubSender(uint256 subSenderId, Receiver[] calldata currReceivers)
        public
        view
        returns (uint128)
    {
        return getPool().withdrawableSubSender(address(this), subSenderId, currReceivers);
    }

    function getDripsFraction() public view returns (uint32) {
        return getPool().getDripsFraction(address(this));
    }

    function hashReceivers(Receiver[] calldata receivers) public view returns (bytes32) {
        return getPool().hashReceivers(receivers);
    }

    function getReceiversHash() public view returns (bytes32) {
        return getPool().getReceiversHash(address(this));
    }

    function getSubSenderReceiversHash(uint256 subSenderId)
        public
        view
        returns (bytes32 weightsHash)
    {
        return getPool().getSubSenderReceiversHash(address(this), subSenderId);
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
        uint128 toppedUp,
        uint128 withdraw,
        uint32 dripsFraction,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 withdrawn) {
        pool.erc20().approve(address(pool), toppedUp);
        return pool.updateSender(toppedUp, withdraw, dripsFraction, currReceivers, newReceivers);
    }

    function updateSubSender(
        uint256 subSenderId,
        uint128 toppedUp,
        uint128 withdraw,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 withdrawn) {
        pool.erc20().approve(address(pool), toppedUp);
        return pool.updateSubSender(subSenderId, toppedUp, withdraw, currReceivers, newReceivers);
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
    ) public override {
        pool.setDripsReceivers(currReceivers, newReceivers);
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
        uint128 toppedUp,
        uint128 withdraw,
        uint32 dripsFraction,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 withdrawn) {
        return
            pool.updateSender{value: toppedUp}(
                withdraw,
                dripsFraction,
                currReceivers,
                newReceivers
            );
    }

    function updateSubSender(
        uint256 subSenderId,
        uint128 toppedUp,
        uint128 withdraw,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 withdrawn) {
        return
            pool.updateSubSender{value: toppedUp}(
                subSenderId,
                withdraw,
                currReceivers,
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
    ) public override {
        pool.setDripsReceivers(currReceivers, newReceivers);
    }
}
