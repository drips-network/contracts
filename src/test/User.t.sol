// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import "./../NFTPool.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

contract User {
    NFTPool public pool;
    Dai public dai;
    constructor(NFTPool pool_, Dai dai_) {
        pool = pool_;
        dai = dai_;
    }

    function withdraw(uint withdrawAmount) public {
        pool.updateSender(0, uint128(withdrawAmount), 0,  new ReceiverWeight[](0));
    }

    function withdraw(address nftRegistry, uint tokenId, uint withdrawAmount) public {
        pool.updateSender(nftRegistry, uint128(tokenId), 0, uint128(withdrawAmount), 0, new ReceiverWeight[](0));
    }

    function collect() public {
        pool.collect();
    }

    function collect(address nftRegistry, uint tokenId) public {
        pool.collect(nftRegistry, uint128(tokenId));
    }

    function streamWithAddress(address to, uint daiPerSecond, uint lockAmount) public {
        ReceiverWeight[] memory receivers = new ReceiverWeight[](1);
        receivers[0] = ReceiverWeight({receiver:to, weight:pool.SENDER_WEIGHTS_SUM_MAX()});

        dai.approve(address(pool), type(uint).max);
        pool.updateSender(uint128(lockAmount), 0, uint128(daiPerSecond), receivers);
    }

    function streamWithNFT(address nftRegistry, uint tokenId, address to, uint daiPerSecond, uint lockAmount) public {
        ReceiverWeight[] memory receivers = new ReceiverWeight[](1);
        receivers[0] = ReceiverWeight({receiver:to, weight:pool.SENDER_WEIGHTS_SUM_MAX()});

        dai.approve(address(pool), type(uint).max);
        pool.updateSender(nftRegistry, uint128(tokenId), uint128(lockAmount), 0, uint128(daiPerSecond), receivers);
    }

    function transferNFT(address nftRegistry,address to, uint tokenId) public {
        IERC721(nftRegistry).transferFrom(address(this), to, tokenId);
    }
}
