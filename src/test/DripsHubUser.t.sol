// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {EthDripsHub, DripsHub} from "../EthDripsHub.sol";
import {DripsReceiver, ERC20DripsHub, Receiver} from "../ERC20DripsHub.sol";

abstract contract DripsHubUser {
    function getDripsHub() internal view virtual returns (DripsHub);

    function balance() public view virtual returns (uint256);

    function updateSender(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function updateSender(
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public virtual returns (uint128 newBalance, int128 realBalanceDelta);

    function give(address receiver, uint128 amt) public virtual;

    function give(
        uint256 account,
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
        return getDripsHub().collect(receiverAddr, currReceivers);
    }

    function collectable(DripsReceiver[] calldata currReceivers)
        public
        view
        returns (uint128 collected, uint128 dripped)
    {
        return getDripsHub().collectable(address(this), currReceivers);
    }

    function flushableCycles() public view returns (uint64 flushable) {
        return getDripsHub().flushableCycles(address(this));
    }

    function flushCycles(uint64 maxCycles) public returns (uint64 flushable) {
        return getDripsHub().flushCycles(address(this), maxCycles);
    }

    function hashSenderState(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata receivers
    ) public view returns (bytes32) {
        return getDripsHub().hashSenderState(lastUpdate, lastBalance, receivers);
    }

    function senderStateHash() public view returns (bytes32) {
        return getDripsHub().senderStateHash(address(this));
    }

    function senderStateHash(uint256 account) public view returns (bytes32 weightsHash) {
        return getDripsHub().senderStateHash(address(this), account);
    }

    function hashDripsReceivers(DripsReceiver[] calldata receivers) public view returns (bytes32) {
        return getDripsHub().hashDripsReceivers(receivers);
    }

    function dripsReceiversHash() public view returns (bytes32) {
        return getDripsHub().dripsReceiversHash(address(this));
    }
}

contract ERC20DripsHubUser is DripsHubUser {
    ERC20DripsHub internal immutable dripsHub;

    constructor(ERC20DripsHub dripsHub_) {
        dripsHub = dripsHub_;
    }

    function getDripsHub() internal view override returns (DripsHub) {
        return DripsHub(dripsHub);
    }

    function balance() public view override returns (uint256) {
        return dripsHub.erc20().balanceOf(address(this));
    }

    function updateSender(
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) dripsHub.erc20().approve(address(dripsHub), uint128(balanceDelta));
        return
            dripsHub.updateSender(
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    function updateSender(
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) dripsHub.erc20().approve(address(dripsHub), uint128(balanceDelta));
        return
            dripsHub.updateSender(
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

    function setDripsReceivers(
        DripsReceiver[] calldata currReceivers,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 collected, uint128 dripped) {
        return dripsHub.setDripsReceivers(currReceivers, newReceivers);
    }
}

contract EthDripsHubUser is DripsHubUser {
    EthDripsHub internal immutable dripsHub;

    constructor(EthDripsHub dripsHub_) payable {
        dripsHub = dripsHub_;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function getDripsHub() internal view override returns (DripsHub) {
        return DripsHub(dripsHub);
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
            dripsHub.updateSender{value: value}(
                lastUpdate,
                lastBalance,
                currReceivers,
                reduceBalance,
                newReceivers
            );
    }

    function updateSender(
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        Receiver[] calldata currReceivers,
        int128 balanceDelta,
        Receiver[] calldata newReceivers
    ) public override returns (uint128 newBalance, int128 realBalanceDelta) {
        uint256 value = balanceDelta > 0 ? uint128(balanceDelta) : 0;
        uint128 reduceBalance = balanceDelta < 0 ? uint128(-balanceDelta) : 0;
        return
            dripsHub.updateSender{value: value}(
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

    function setDripsReceivers(
        DripsReceiver[] calldata currReceivers,
        DripsReceiver[] calldata newReceivers
    ) public override returns (uint128 collected, uint128 dripped) {
        return dripsHub.setDripsReceivers(currReceivers, newReceivers);
    }
}
