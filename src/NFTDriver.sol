// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import "./INFTDriver.sol";
import {DriverTransferUtils, ERC2771Context} from "./DriverTransferUtils.sol";
import {Managed} from "./Managed.sol";
import {Context, ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";

/// @notice The implementation of `INFTDriver`, see its documentation for more details.
contract NFTDriver is INFTDriver, ERC721, DriverTransferUtils, Managed {
    /// @inheritdoc INFTDriver
    IDrips public immutable drips;
    /// @inheritdoc INFTDriver
    uint32 public immutable driverId;
    /// @notice The ERC-1967 storage slot holding a single `NFTDriverStorage` structure.
    bytes32 private immutable _nftDriverStorageSlot = _erc1967Slot("eip1967.nftDriver.storage");

    struct NFTDriverStorage {
        /// @notice The number of tokens minted without salt.
        uint64 mintedTokens;
        /// @notice The salts already used for minting tokens.
        mapping(address minter => mapping(uint64 salt => bool)) isSaltUsed;
    }

    /// @param drips_ The Drips contract to use.
    /// @param forwarder The ERC-2771 forwarder to trust. May be the zero address.
    /// @param driverId_ The driver ID to use when calling Drips.
    constructor(IDrips drips_, address forwarder, uint32 driverId_)
        DriverTransferUtils(forwarder)
        ERC721("", "")
    {
        drips = drips_;
        driverId = driverId_;
    }

    modifier onlyApprovedOrOwner(uint256 tokenId) {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: caller is not token owner or approved"
        );
        _;
    }

    /// @inheritdoc INFTDriver
    function nextTokenId() public view onlyProxy returns (uint256 tokenId) {
        return calcTokenIdWithSalt(address(0), _nftDriverStorage().mintedTokens);
    }

    /// @inheritdoc INFTDriver
    function calcTokenIdWithSalt(address minter, uint64 salt)
        public
        view
        onlyProxy
        returns (uint256 tokenId)
    {
        // By assignment we get `tokenId` value:
        // `zeros (224 bits) | driverId (32 bits)`
        tokenId = driverId;
        // By bit shifting we get `tokenId` value:
        // `zeros (64 bits) | driverId (32 bits) | zeros (160 bits)`
        // By bit masking we get `tokenId` value:
        // `zeros (64 bits) | driverId (32 bits) | minter (160 bits)`
        tokenId = (tokenId << 160) | uint160(minter);
        // By bit shifting we get `tokenId` value:
        // `driverId (32 bits) | minter (160 bits) | zeros (64 bits)`
        // By bit masking we get `tokenId` value:
        // `driverId (32 bits) | minter (160 bits) | salt (64 bits)`
        tokenId = (tokenId << 64) | salt;
    }

    /// @inheritdoc INFTDriver
    function isSaltUsed(address minter, uint64 salt) public view onlyProxy returns (bool isUsed) {
        return _nftDriverStorage().isSaltUsed[minter][salt];
    }

    /// @inheritdoc INFTDriver
    function mint(address to, AccountMetadata[] calldata accountMetadata)
        public
        onlyProxy
        returns (uint256 tokenId)
    {
        tokenId = _registerTokenId();
        _mint(to, tokenId);
        _emitAccountMetadata(tokenId, accountMetadata);
    }

    /// @inheritdoc INFTDriver
    function safeMint(address to, AccountMetadata[] calldata accountMetadata)
        public
        onlyProxy
        returns (uint256 tokenId)
    {
        tokenId = _registerTokenId();
        _safeMint(to, tokenId);
        _emitAccountMetadata(tokenId, accountMetadata);
    }

    /// @notice Registers the next token ID when minting.
    /// @return tokenId The registered token ID.
    function _registerTokenId() internal returns (uint256 tokenId) {
        tokenId = nextTokenId();
        _nftDriverStorage().mintedTokens++;
    }

    /// @inheritdoc INFTDriver
    function mintWithSalt(uint64 salt, address to, AccountMetadata[] calldata accountMetadata)
        public
        onlyProxy
        returns (uint256 tokenId)
    {
        tokenId = _registerTokenIdWithSalt(salt);
        _mint(to, tokenId);
        _emitAccountMetadata(tokenId, accountMetadata);
    }

    /// @inheritdoc INFTDriver
    function safeMintWithSalt(uint64 salt, address to, AccountMetadata[] calldata accountMetadata)
        public
        onlyProxy
        returns (uint256 tokenId)
    {
        tokenId = _registerTokenIdWithSalt(salt);
        _safeMint(to, tokenId);
        _emitAccountMetadata(tokenId, accountMetadata);
    }

    /// @notice Registers the token ID minted with salt by the caller.
    /// Reverts if the caller has already used the salt.
    /// @return tokenId The registered token ID.
    function _registerTokenIdWithSalt(uint64 salt) internal returns (uint256 tokenId) {
        address minter = _msgSender();
        require(!isSaltUsed(minter, salt), "ERC721: token already minted");
        _nftDriverStorage().isSaltUsed[minter][salt] = true;
        return calcTokenIdWithSalt(minter, salt);
    }

    /// @inheritdoc INFTDriver
    function burn(uint256 tokenId) public onlyProxy onlyApprovedOrOwner(tokenId) {
        _burn(tokenId);
    }

    /// @inheritdoc INFTDriver
    function collect(uint256 tokenId, IERC20 erc20, address transferTo)
        public
        onlyProxy
        onlyApprovedOrOwner(tokenId)
        returns (uint128 amt)
    {
        return _collectAndTransfer(drips, tokenId, erc20, transferTo);
    }

    /// @inheritdoc INFTDriver
    function give(uint256 tokenId, uint256 receiver, IERC20 erc20, uint128 amt)
        public
        onlyProxy
        onlyApprovedOrOwner(tokenId)
    {
        _giveAndTransfer(drips, tokenId, receiver, erc20, amt);
    }

    /// @inheritdoc INFTDriver
    function setStreams(
        uint256 tokenId,
        IERC20 erc20,
        StreamReceiver[] calldata currReceivers,
        int128 balanceDelta,
        StreamReceiver[] calldata newReceivers,
        MaxEndHints maxEndHints,
        address transferTo
    ) public onlyProxy onlyApprovedOrOwner(tokenId) returns (int128 realBalanceDelta) {
        return _setStreamsAndTransfer(
            drips,
            tokenId,
            erc20,
            currReceivers,
            balanceDelta,
            newReceivers,
            maxEndHints,
            transferTo
        );
    }

    /// @inheritdoc INFTDriver
    function setSplits(uint256 tokenId, SplitsReceiver[] calldata receivers)
        public
        onlyProxy
        onlyApprovedOrOwner(tokenId)
    {
        drips.setSplits(tokenId, receivers);
    }

    /// @inheritdoc INFTDriver
    function emitAccountMetadata(uint256 tokenId, AccountMetadata[] calldata accountMetadata)
        public
        onlyProxy
        onlyApprovedOrOwner(tokenId)
    {
        _emitAccountMetadata(tokenId, accountMetadata);
    }

    /// @notice Emits the account metadata for the given token.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param tokenId The ID of the token representing the emitting account ID.
    /// The token ID is equal to the account ID controlled by it.
    /// @param accountMetadata The list of account metadata.
    function _emitAccountMetadata(uint256 tokenId, AccountMetadata[] calldata accountMetadata)
        internal
    {
        if (accountMetadata.length != 0) {
            drips.emitAccountMetadata(tokenId, accountMetadata);
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, IERC165)
        onlyProxy
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC721
    function balanceOf(address owner)
        public
        view
        override(ERC721, IERC721)
        onlyProxy
        returns (uint256)
    {
        return super.balanceOf(owner);
    }

    /// @inheritdoc IERC721
    function ownerOf(uint256 tokenId)
        public
        view
        override(ERC721, IERC721)
        onlyProxy
        returns (address)
    {
        return super.ownerOf(tokenId);
    }

    /// @inheritdoc IERC721Metadata
    function name()
        public
        view
        override(ERC721, IERC721Metadata)
        onlyProxy
        returns (string memory)
    {
        return "Drips identity";
    }

    /// @inheritdoc IERC721Metadata
    function symbol()
        public
        view
        override(ERC721, IERC721Metadata)
        onlyProxy
        returns (string memory)
    {
        return "DHI";
    }

    /// @inheritdoc IERC721Metadata
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, IERC721Metadata)
        onlyProxy
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) public override(ERC721, IERC721) onlyProxy {
        super.approve(to, tokenId);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 tokenId)
        public
        view
        override(ERC721, IERC721)
        onlyProxy
        returns (address)
    {
        return super.getApproved(tokenId);
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved)
        public
        override(ERC721, IERC721)
        onlyProxy
    {
        super.setApprovalForAll(operator, approved);
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner, address operator)
        public
        view
        override(ERC721, IERC721)
        onlyProxy
        returns (bool)
    {
        return super.isApprovedForAll(owner, operator);
    }

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyProxy
    {
        super.transferFrom(from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override(ERC721, IERC721)
        onlyProxy
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override(ERC721, IERC721)
        onlyProxy
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    // Workaround for https://github.com/ethereum/solidity/issues/12554
    function _msgSender() internal view override(Context, ERC2771Context) returns (address) {
        return ERC2771Context._msgSender();
    }

    // Workaround for https://github.com/ethereum/solidity/issues/12554
    // slither-disable-next-line dead-code
    function _msgData() internal view override(Context, ERC2771Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    /// @notice Returns the NFTDriver storage.
    /// @return storageRef The storage.
    function _nftDriverStorage() internal view returns (NFTDriverStorage storage storageRef) {
        bytes32 slot = _nftDriverStorageSlot;
        // slither-disable-next-line assembly
        assembly {
            storageRef.slot := slot
        }
    }
}
