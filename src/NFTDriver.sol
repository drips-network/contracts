// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {
    DripsHub,
    DripsReceiver,
    IERC20,
    SafeERC20,
    SplitsReceiver,
    UserMetadata
} from "./DripsHub.sol";
import {Managed} from "./Managed.sol";
import {Context, ERC2771Context} from "openzeppelin-contracts/metatx/ERC2771Context.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";
import {
    ERC721,
    ERC721Burnable,
    IERC721,
    IERC721Metadata
} from "openzeppelin-contracts/token/ERC721/extensions/ERC721Burnable.sol";

/// @notice A DripsHub driver implementing token-based user identification.
/// Anybody can mint a new token and create a new identity.
/// Only the current holder of the token can control its user ID.
/// The token ID and the user ID controlled by it are always equal.
contract NFTDriver is ERC721Burnable, ERC2771Context, Managed {
    using SafeERC20 for IERC20;

    /// @notice The DripsHub address used by this driver.
    DripsHub public immutable dripsHub;
    /// @notice The driver ID which this driver uses when calling DripsHub.
    uint32 public immutable driverId;
    /// @notice The ERC-1967 storage slot holding a single `uint256` counter of minted tokens.
    bytes32 private immutable _mintedTokensSlot = _erc1967Slot("eip1967.nftDriver.storage");

    /// @param _dripsHub The drips hub to use.
    /// @param forwarder The ERC-2771 forwarder to trust. May be the zero address.
    /// @param _driverId The driver ID to use when calling DripsHub.
    constructor(DripsHub _dripsHub, address forwarder, uint32 _driverId)
        ERC2771Context(forwarder)
        ERC721("", "")
    {
        dripsHub = _dripsHub;
        driverId = _driverId;
    }

    modifier onlyHolder(uint256 tokenId) {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: caller is not token owner or approved"
        );
        _;
    }

    /// @notice Get the ID of the next minted token.
    /// @return tokenId The token ID.
    function nextTokenId() public view returns (uint256 tokenId) {
        return (uint256(driverId) << 224) + StorageSlot.getUint256Slot(_mintedTokensSlot).value;
    }

    /// @notice Mints a new token controlling a new user ID and transfers it to an address.
    /// Emits user metadata for the new token.
    /// Usage of this method is discouraged, use `safeMint` whenever possible.
    /// @param to The address to transfer the minted token to.
    /// @param userMetadata The list of user metadata to emit for the minted token.
    /// The keys and the values are not standardized by the protocol, it's up to the user
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return tokenId The minted token ID. It's equal to the user ID controlled by it.
    function mint(address to, UserMetadata[] calldata userMetadata)
        public
        whenNotPaused
        returns (uint256 tokenId)
    {
        tokenId = _registerTokenId();
        _mint(to, tokenId);
        if (userMetadata.length > 0) dripsHub.emitUserMetadata(tokenId, userMetadata);
    }

    /// @notice Mints a new token controlling a new user ID and safely transfers it to an address.
    /// Emits user metadata for the new token.
    /// @param to The address to transfer the minted token to.
    /// @param userMetadata The list of user metadata to emit for the minted token.
    /// The keys and the values are not standardized by the protocol, it's up to the user
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return tokenId The minted token ID. It's equal to the user ID controlled by it.
    function safeMint(address to, UserMetadata[] calldata userMetadata)
        public
        whenNotPaused
        returns (uint256 tokenId)
    {
        tokenId = _registerTokenId();
        _safeMint(to, tokenId);
        if (userMetadata.length > 0) dripsHub.emitUserMetadata(tokenId, userMetadata);
    }

    /// @notice Registers the next token ID when minting.
    /// @return tokenId The registered token ID.
    function _registerTokenId() internal returns (uint256 tokenId) {
        tokenId = nextTokenId();
        StorageSlot.getUint256Slot(_mintedTokensSlot).value++;
    }

    /// @notice Collects the user's received already split funds
    /// and transfers them out of the drips hub contract.
    /// @param tokenId The ID of the token representing the collecting user ID.
    /// The caller must be the owner of the token or be approved to use it.
    /// The token ID is equal to the user ID controlled by it.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param transferTo The address to send collected funds to
    /// @return amt The collected amount
    function collect(uint256 tokenId, IERC20 erc20, address transferTo)
        public
        whenNotPaused
        onlyHolder(tokenId)
        returns (uint128 amt)
    {
        amt = dripsHub.collect(tokenId, erc20);
        if (amt > 0) dripsHub.withdraw(erc20, transferTo, amt);
    }

    /// @notice Gives funds from the user to the receiver.
    /// The receiver can split and collect them immediately.
    /// Transfers the funds to be given from the message sender's wallet to the drips hub contract.
    /// @param tokenId The ID of the token representing the giving user ID.
    /// The caller must be the owner of the token or be approved to use it.
    /// The token ID is equal to the user ID controlled by it.
    /// @param receiver The receiver
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param amt The given amount
    function give(uint256 tokenId, uint256 receiver, IERC20 erc20, uint128 amt)
        public
        whenNotPaused
        onlyHolder(tokenId)
    {
        if (amt > 0) _transferFromCaller(erc20, amt);
        dripsHub.give(tokenId, receiver, erc20, amt);
    }

    /// @notice Sets the user's drips configuration.
    /// Transfers funds between the message sender's wallet and the drips hub contract
    /// to fulfil the change of the drips balance.
    /// @param tokenId The ID of the token representing the configured user ID.
    /// The caller must be the owner of the token or be approved to use it.
    /// The token ID is equal to the user ID controlled by it.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param currReceivers The current drips receivers list.
    /// It must be exactly the same as the last list set for the user with `setDrips`.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the sender to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @param maxEndHint1 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The first hint for finding the maximum end time when all drips stop due to funds
    /// running out after the balance is updated and the new receivers list is applied.
    /// Hints have no effect on the results of calling this function, except potentially saving gas.
    /// Hints are Unix timestamps used as the starting points for binary search for the time
    /// when funds run out in the range of timestamps from the current block's to `2^32`.
    /// Hints lower than the current timestamp are ignored.
    /// You can provide zero, one or two hints. The order of hints doesn't matter.
    /// Hints are the most effective when one of them is lower than or equal to
    /// the last timestamp when funds are still dripping, and the other one is strictly larger
    /// than that timestamp,the smaller the difference between such hints, the higher gas savings.
    /// The savings are the highest possible when one of the hints is equal to
    /// the last timestamp when funds are still dripping, and the other one is larger by 1.
    /// It's worth noting that the exact timestamp of the block in which this function is executed
    /// may affect correctness of the hints, especially if they're precise.
    /// Hints don't provide any benefits when balance is not enough to cover
    /// a single second of dripping or is enough to cover all drips until timestamp `2^32`.
    /// Even inaccurate hints can be useful, and providing a single hint
    /// or two hints that don't enclose the time when funds run out can still save some gas.
    /// Providing poor hints that don't reduce the number of binary search steps
    /// may cause slightly higher gas usage than not providing any hints.
    /// @param maxEndHint2 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The second hint for finding the maximum end time, see `maxEndHint1` docs for more details.
    /// @param transferTo The address to send funds to in case of decreasing balance
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        uint256 tokenId,
        IERC20 erc20,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers,
        // slither-disable-next-line similar-names
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        address transferTo
    ) public whenNotPaused onlyHolder(tokenId) returns (int128 realBalanceDelta) {
        if (balanceDelta > 0) _transferFromCaller(erc20, uint128(balanceDelta));
        realBalanceDelta = dripsHub.setDrips(
            tokenId, erc20, currReceivers, balanceDelta, newReceivers, maxEndHint1, maxEndHint2
        );
        if (realBalanceDelta < 0) dripsHub.withdraw(erc20, transferTo, uint128(-realBalanceDelta));
    }

    /// @notice Sets user splits configuration. The configuration is common for all assets.
    /// Nothing happens to the currently splittable funds, but when they are split
    /// after this function finishes, the new splits configuration will be used.
    /// Because anybody can call `split` on `DripsHub`, calling this function may be frontrun
    /// and all the currently splittable funds will be split using the old splits configuration.
    /// @param tokenId The ID of the token representing the configured user ID.
    /// The caller must be the owner of the token or be approved to use it.
    /// The token ID is equal to the user ID controlled by it.
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    /// If the sum of weights of all receivers is less than `_TOTAL_SPLITS_WEIGHT`,
    /// some funds won't be split, but they will be left for the user to collect.
    /// It's valid to include the user's own `userId` in the list of receivers,
    /// but funds split to themselves return to their splittable balance and are not collectable.
    /// This is usually unwanted, because if splitting is repeated,
    /// funds split to themselves will be again split using the current configuration.
    /// Splitting 100% to self effectively blocks splitting unless the configuration is updated.
    function setSplits(uint256 tokenId, SplitsReceiver[] calldata receivers)
        public
        whenNotPaused
        onlyHolder(tokenId)
    {
        dripsHub.setSplits(tokenId, receivers);
    }

    /// @notice Emits the user metadata for the given token.
    /// The keys and the values are not standardized by the protocol, it's up to the user
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param tokenId The ID of the token representing the emitting user ID.
    /// The caller must be the owner of the token or be approved to use it.
    /// The token ID is equal to the user ID controlled by it.
    /// @param userMetadata The list of user metadata.
    function emitUserMetadata(uint256 tokenId, UserMetadata[] calldata userMetadata)
        public
        whenNotPaused
        onlyHolder(tokenId)
    {
        dripsHub.emitUserMetadata(tokenId, userMetadata);
    }

    /// @inheritdoc IERC721Metadata
    function name() public pure override returns (string memory) {
        return "DripsHub identity";
    }

    /// @inheritdoc IERC721Metadata
    function symbol() public pure override returns (string memory) {
        return "DHI";
    }

    /// @inheritdoc ERC721Burnable
    function burn(uint256 tokenId) public override whenNotPaused {
        super.burn(tokenId);
    }

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) public override whenNotPaused {
        super.approve(to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        override
        whenNotPaused
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        override
        whenNotPaused
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) public override whenNotPaused {
        super.setApprovalForAll(operator, approved);
    }

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId)
        public
        override
        whenNotPaused
    {
        super.transferFrom(from, to, tokenId);
    }

    function _transferFromCaller(IERC20 erc20, uint128 amt) internal {
        erc20.safeTransferFrom(_msgSender(), address(dripsHub), amt);
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
}
