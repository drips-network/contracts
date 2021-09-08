// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.6;

import {Dai} from "./TestDai.sol";
import {Pool, Erc20Pool, EthPool, ReceiverWeight, IDai} from "./../Pool.sol";
import {NFTPool} from "./../NFTPool.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

abstract contract PoolUser {
    function getPool() internal virtual view returns (Pool);

    function balance() public virtual view returns (uint);

    function updateSender(uint128 toppedUp, uint128 withdraw, uint128 amtPerSec,
         ReceiverWeight[] calldata updatedReceivers) public virtual returns(uint128 withdrawn);

    function collect() public {
        getPool().collect();
    }

    function collectable() public view returns (uint128) {
        return getPool().collectable(address(this));
    }

    function withdrawable() public view returns (uint128) {
        return getPool().withdrawable(address(this));
    }

    function getAmtPerSec() public view returns (uint128) {
        return getPool().getAmtPerSec(address(this));
    }

    function getAllReceivers() public view returns (ReceiverWeight[] memory weights) {
        return getPool().getAllReceivers(address(this));
    }
}

contract Erc20PoolUser is PoolUser {

    Erc20Pool internal immutable pool;

    constructor(Erc20Pool pool_) {
        pool = pool_;
    }

    function getPool() internal override view returns (Pool) {
        return Pool(pool);
    }

    function balance() public override view returns (uint) {
        return pool.erc20().balanceOf(address(this));
    }

    function updateSender(uint128 toppedUp, uint128 withdraw, uint128 amtPerSec,
            ReceiverWeight[] calldata updatedReceivers) override public returns(uint128 withdrawn) {
        pool.erc20().approve(address(pool), toppedUp);
        return pool.updateSender(toppedUp, withdraw, amtPerSec, updatedReceivers);
    }
}

contract EthPoolUser is PoolUser {

    EthPool internal immutable pool;

    constructor(EthPool pool_) payable {
        pool = pool_;
    }

    receive() external payable {}

    function getPool() internal override view returns (Pool) {
        return Pool(pool);
    }

    function balance() public override view returns (uint) {
        return address(this).balance;
    }

    function updateSender(uint128 toppedUp, uint128 withdraw, uint128 amtPerSec,
            ReceiverWeight[] calldata updatedReceivers) override public returns(uint128 withdrawn) {
        return pool.updateSender{value: toppedUp}(withdraw, amtPerSec, updatedReceivers);
    }
}

contract NFTPoolUser is PoolUser {
    NFTPool internal immutable pool;
    IDai internal dai;

    constructor(NFTPool pool_, IDai dai_) {
        pool = pool_;
        dai = dai_;
    }

    function getPool() internal override view returns (Pool) {
        return Pool(pool);
    }

    function balance() public override view returns (uint) {
        return pool.erc20().balanceOf(address(this));
    }

    function updateSender(uint128 toppedUp, uint128 withdrawAmt, uint128 amtPerSec,
            ReceiverWeight[] calldata updatedReceivers) override public returns(uint128 withdrawn) {
        pool.erc20().approve(address(pool), toppedUp);
        return pool.updateSender(toppedUp, withdrawAmt, amtPerSec, updatedReceivers);
    }

    function withdraw(uint withdrawAmount) public {
        pool.updateSender(0, uint128(withdrawAmount), 0,  new ReceiverWeight[](0));
    }

    function withdraw(address nftRegistry, uint tokenId, uint withdrawAmount) public {
        pool.updateSender(nftRegistry, uint128(tokenId), 0, uint128(withdrawAmount), 0, new ReceiverWeight[](0));
    }

    function collect(address nftRegistry, uint tokenId) public {
        pool.collect(nftRegistry, uint128(tokenId));
    }

    function streamWithAddress(address to, uint daiPerSecond, uint lockAmount) public {
        ReceiverWeight[] memory receivers = new ReceiverWeight[](1);
        receivers[0] = ReceiverWeight({receiver:to, weight:1});

        dai.approve(address(pool), type(uint).max);
        pool.updateSender(uint128(lockAmount), 0, uint128(daiPerSecond), receivers);
    }

    function streamWithNFT(address nftRegistry, uint tokenId, address to, uint daiPerSecond, uint lockAmount) public {
        ReceiverWeight[] memory receivers = new ReceiverWeight[](1);
        receivers[0] = ReceiverWeight({receiver:to, weight:1});

        dai.approve(address(pool), type(uint).max);
        pool.updateSender(nftRegistry, uint128(tokenId), uint128(lockAmount), 0, uint128(daiPerSecond), receivers);
    }

    function transferNFT(address nftRegistry,address to, uint tokenId) public {
        IERC721(nftRegistry).transferFrom(address(this), to, tokenId);
    }
}
