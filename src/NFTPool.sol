// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.7;

import {DaiPool, ReceiverWeight, IDai} from "./DaiPool.sol";

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

/// @notice NFT pool contract to support streaming based on NFT ownership
/// A NFT can be a sender or a receiver, a unique id is generated based on
/// NFT registry address and the tokenId
contract NFTPool is DaiPool {
    modifier nftOwner(address nftRegistry, uint256 tokenId) {
        require(IERC721(nftRegistry).ownerOf(tokenId) == msg.sender, "not-NFT-owner");
        _;
    }

    // solhint-disable-next-line no-empty-blocks
    constructor(uint64 cycleSecs, IDai dai) DaiPool(cycleSecs, dai) {}

    /// @notice generates a unique 20 bytes by hashing the nft registry  and tokenId
    /// @param nftRegistry address of the NFT specific registry
    /// @param tokenId the unique token id for the NFT registry
    function nftID(address nftRegistry, uint128 tokenId) public pure returns (address id) {
        // gas optimized without local variables
        return address(uint160(uint256(keccak256(abi.encodePacked(nftRegistry, tokenId)))));
    }

    function _sendFromNFT(
        address to,
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) internal returns (uint128 withdrawn) {
        // msg.sender === nft owner
        _transferToContract(msg.sender, topUpAmt);
        withdrawn = _updateSenderInternal(to, topUpAmt, withdraw, amtPerSec, updatedReceivers);
        _transfer(msg.sender, withdrawn);
    }

    /// @notice updateSender based on the ownership of an NFT
    /// @param nftRegistry address of the NFT specific registry
    /// @param tokenId the unique token id for the NFT registry
    /// @return withdrawn The actually withdrawn amount.
    function updateSender(
        address nftRegistry,
        uint128 tokenId,
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers
    ) public virtual nftOwner(nftRegistry, tokenId) returns (uint128 withdrawn) {
        return
            _sendFromNFT(
                nftID(nftRegistry, tokenId),
                topUpAmt,
                withdraw,
                amtPerSec,
                updatedReceivers
            );
    }

    // todo implement update sender with permit after proxies are removed
}
