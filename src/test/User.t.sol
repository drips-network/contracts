// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {EthPool, Pool} from "../EthPool.sol";
import {ERC20Pool, ReceiverWeight, IDai} from "../DaiPool.sol";
import {NFTPool} from "../NFTPool.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

abstract contract PoolUser {
    function getPool() internal view virtual returns (Pool);

    function balance() public view virtual returns (uint256);

    function getAmtPerSecUnchanged() public view returns (uint128) {
        return getPool().AMT_PER_SEC_UNCHANGED();
    }

    function updateSender(
        uint128 toppedUp,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public virtual returns (uint128 withdrawn);

    function updateSubSender(
        uint256 subSenderId,
        uint128 toppedUp,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public virtual returns (uint128 withdrawn);

    function collect() public {
        collect(address(this));
    }

    function collect(address id) public {
        getPool().collect(id);
    }

    function collectable() public view returns (uint128) {
        return getPool().collectable(address(this));
    }

    function withdrawable() public view returns (uint128) {
        return getPool().withdrawable(address(this));
    }

    function withdrawableSubSender(uint256 subSenderId) public view returns (uint128) {
        return getPool().withdrawableSubSender(address(this), subSenderId);
    }

    function getAmtPerSec() public view returns (uint128) {
        return getPool().getAmtPerSec(address(this));
    }

    function getAmtPerSecSubSender(uint256 subSenderId) public view returns (uint128) {
        return getPool().getAmtPerSecSubSender(address(this), subSenderId);
    }

    function getAllReceivers() public view returns (ReceiverWeight[] memory weights) {
        return getPool().getAllReceivers(address(this));
    }

    function getAllReceiversSubSender(uint256 subSenderId)
        public
        view
        returns (ReceiverWeight[] memory weights)
    {
        return getPool().getAllReceiversSubSender(address(this), subSenderId);
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
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public override returns (uint128 withdrawn) {
        pool.erc20().approve(address(pool), toppedUp);
        return pool.updateSender(toppedUp, withdraw, amtPerSec, updatedReceivers);
    }

    function updateSubSender(
        uint256 subSenderId,
        uint128 toppedUp,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public override returns (uint128 withdrawn) {
        pool.erc20().approve(address(pool), toppedUp);
        return pool.updateSubSender(subSenderId, toppedUp, withdraw, amtPerSec, updatedReceivers);
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
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public override returns (uint128 withdrawn) {
        return pool.updateSender{value: toppedUp}(withdraw, amtPerSec, updatedReceivers);
    }

    function updateSubSender(
        uint256 subSenderId,
        uint128 toppedUp,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public override returns (uint128 withdrawn) {
        return
            pool.updateSubSender{value: toppedUp}(
                subSenderId,
                withdraw,
                amtPerSec,
                updatedReceivers
            );
    }
}

contract NFTPoolUser is PoolUser {
    NFTPool internal immutable pool;
    IDai internal dai;

    constructor(NFTPool pool_, IDai dai_) {
        pool = pool_;
        dai = dai_;
    }

    function getPool() internal view override returns (Pool) {
        return Pool(pool);
    }

    function balance() public view override returns (uint256) {
        return pool.erc20().balanceOf(address(this));
    }

    function updateSender(
        uint128 toppedUp,
        uint128 withdrawAmt,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public override returns (uint128 withdrawn) {
        pool.erc20().approve(address(pool), toppedUp);
        return pool.updateSender(toppedUp, withdrawAmt, amtPerSec, updatedReceivers);
    }

    function updateSubSender(
        uint256 subSenderId,
        uint128 toppedUp,
        uint128 withdrawAmt,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public override returns (uint128 withdrawn) {
        pool.erc20().approve(address(pool), toppedUp);
        return
            pool.updateSubSender(subSenderId, toppedUp, withdrawAmt, amtPerSec, updatedReceivers);
    }

    function withdraw(uint256 withdrawAmount) public {
        pool.updateSender(0, uint128(withdrawAmount), 0, new ReceiverWeight[](0));
    }

    function withdraw(
        address nftRegistry,
        uint256 tokenId,
        uint256 withdrawAmount
    ) public {
        pool.updateSender(
            nftRegistry,
            uint128(tokenId),
            0,
            uint128(withdrawAmount),
            0,
            new ReceiverWeight[](0)
        );
    }

    function streamWithAddress(
        address to,
        uint256 daiPerSecond,
        uint256 lockAmount
    ) public {
        ReceiverWeight[] memory receivers = new ReceiverWeight[](1);
        receivers[0] = ReceiverWeight({receiver: to, weight: 1});

        dai.approve(address(pool), type(uint256).max);
        pool.updateSender(uint128(lockAmount), 0, uint128(daiPerSecond), receivers);
    }

    function streamWithNFT(
        address nftRegistry,
        uint256 tokenId,
        address to,
        uint256 daiPerSecond,
        uint256 lockAmount
    ) public {
        ReceiverWeight[] memory receivers = new ReceiverWeight[](1);
        receivers[0] = ReceiverWeight({receiver: to, weight: 1});

        dai.approve(address(pool), type(uint256).max);
        pool.updateSender(
            nftRegistry,
            uint128(tokenId),
            uint128(lockAmount),
            0,
            uint128(daiPerSecond),
            receivers
        );
    }

    function transferNFT(
        address nftRegistry,
        address to,
        uint256 tokenId
    ) public {
        IERC721(nftRegistry).transferFrom(address(this), to, tokenId);
    }
}
