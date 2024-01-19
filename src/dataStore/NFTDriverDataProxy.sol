// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {DripsDataStore} from "./DripsDataStore.sol";
import {Caller} from "../Caller.sol";
import {AccountMetadata, Drips, StreamReceiver, IERC20, SplitsReceiver} from "../Drips.sol";
import {NFTDriver} from "../NFTDriver.sol";
import {Managed} from "../Managed.sol";
import {ERC2771Context} from "openzeppelin-contracts/metatx/ERC2771Context.sol";

/// @notice A data proxy for `NFTDriver`.
/// Large parameters aren't passed in calldata, but instead their hashes are accepted,
/// and the actual data is loaded from `DripsDataStore`.
/// The data must be explicitly stored in `DripsDataStore` before its usage.
///
/// Calls to the proxy requiring authentication are forwarded to the actual driver
/// via `Caller`'s `callAs` on behalf of the message sender, so to make
/// such calls the sender must have the proxy address `authorize`d in `Caller`.
/// The proxy treats `Caller` as the trusted ERC-2771 forwarder.
///
/// In some cases using the proxy is easier and cheaper than calling the driver directly.
/// For example multisigs and governance contracts often need the whole calldata
/// provided as a binary blob, which then sometimes needs to be stored on-chain.
/// It's easier to build calldata consisting of a flat list of scalar parameters,
/// and calldata is much smaller when large lists are substituted with their hashes.
contract NFTDriverDataProxy is ERC2771Context, Managed {
    /// @notice The Drips contract used by this proxy.
    Drips public immutable drips;
    /// @notice The NFTDriver contract used by this proxy.
    NFTDriver public immutable nftDriver;
    /// @notice The DripsDataStore contract used by this proxy.
    DripsDataStore public immutable dripsDataStore;
    // @notice The Caller contract used by this proxy. It's also the trusted ERC-2771 forwarder.
    Caller public immutable caller;

    /// @param nftDriver_ The NFTDriver contract to use.
    /// @param dripsDataStore_ The DripsDataStore contract to use.
    /// @param caller_ The Caller contract to use. It's also the trusted ERC-2771 forwarder.
    constructor(NFTDriver nftDriver_, DripsDataStore dripsDataStore_, Caller caller_)
        ERC2771Context(address(caller_))
    {
        drips = nftDriver_.drips();
        nftDriver = nftDriver_;
        dripsDataStore = dripsDataStore_;
        caller = caller_;
    }

    /// @notice Mints a new token controlling a new account ID and transfers it to an address.
    /// Emits account metadata for the new token.
    /// Usage of this method is discouraged, use `safeMint` whenever possible.
    /// @param to The address to transfer the minted token to.
    /// @param accountMetadataHash The hash of the list of account metadata to emit
    /// for the minted token, the actual list must be stored in DripsDataStore.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return tokenId The minted token ID. It's equal to the account ID controlled by it.
    function mint(address to, bytes32 accountMetadataHash)
        public
        onlyProxy
        returns (uint256 tokenId)
    {
        return nftDriver.mint(to, dripsDataStore.loadAccountMetadata(accountMetadataHash));
    }

    /// @notice Mints a new token controlling a new account ID,
    /// and safely transfers it to an address.
    /// Emits account metadata for the new token.
    /// @param to The address to transfer the minted token to.
    /// @param accountMetadataHash The hash of the list of account metadata to emit
    /// for the minted token, the actual list must be stored in DripsDataStore.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return tokenId The minted token ID. It's equal to the account ID controlled by it.
    function safeMint(address to, bytes32 accountMetadataHash)
        public
        onlyProxy
        returns (uint256 tokenId)
    {
        return nftDriver.safeMint(to, dripsDataStore.loadAccountMetadata(accountMetadataHash));
    }

    /// @notice Mints a new token controlling a new account ID and transfers it to an address.
    /// The token ID is deterministically derived from the caller's address and the salt.
    /// Each caller can use each salt only once, to mint a single token.
    /// Emits account metadata for the new token.
    /// Usage of this method is discouraged, use `safeMint` whenever possible.
    /// @param to The address to transfer the minted token to.
    /// @param accountMetadataHash The hash of the list of account metadata to emit
    /// for the minted token, the actual list must be stored in DripsDataStore.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return tokenId The minted token ID. It's equal to the account ID controlled by it.
    /// The ID is calculated using `calcTokenIdWithSalt` for the caller's address and the used salt.
    function mintWithSalt(uint64 salt, address to, bytes32 accountMetadataHash)
        public
        onlyProxy
        returns (uint256 tokenId)
    {
        bytes memory data = abi.encodeCall(
            nftDriver.mintWithSalt,
            (salt, to, dripsDataStore.loadAccountMetadata(accountMetadataHash))
        );
        return abi.decode(_callNFTDriver(data), (uint256));
    }

    /// @notice Mints a new token controlling a new account ID,
    /// and safely transfers it to an address.
    /// The token ID is deterministically derived from the caller's address and the salt.
    /// Each caller can use each salt only once, to mint a single token.
    /// Emits account metadata for the new token.
    /// @param to The address to transfer the minted token to.
    /// @param accountMetadataHash The hash of the list of account metadata to emit
    /// for the minted token, the actual list must be stored in DripsDataStore.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @return tokenId The minted token ID. It's equal to the account ID controlled by it.
    /// The ID is calculated using `calcTokenIdWithSalt` for the caller's address and the used salt.
    function safeMintWithSalt(uint64 salt, address to, bytes32 accountMetadataHash)
        public
        onlyProxy
        returns (uint256 tokenId)
    {
        bytes memory data = abi.encodeCall(
            nftDriver.safeMintWithSalt,
            (salt, to, dripsDataStore.loadAccountMetadata(accountMetadataHash))
        );
        return abi.decode(_callNFTDriver(data), (uint256));
    }

    /// @notice Sets the account's streams configuration.
    /// Transfers funds between the message sender's wallet and the Drips contract
    /// to fulfil the change of the streams balance.
    /// The currently set list of stream receivers must be stored in DripsDataStore.
    /// @param tokenId The ID of the token representing the configured account ID.
    /// The caller must be the owner of the token or be approved to use it.
    /// The token ID is equal to the account ID controlled by it.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param balanceDelta The streams balance change to be applied.
    /// If it's positive, the balance is increased by `balanceDelta`.
    /// If it's zero, the balance doesn't change.
    /// If it's negative, the balance is decreased by `balanceDelta`,
    /// but the change is capped at the current balance amount, so it doesn't go below 0.
    /// Passing `type(int128).min` always decreases the current balance to 0.
    /// @param newStreamsHash The hash of the list of the streams receivers of the sender to be set,
    /// the actual list must be stored in DripsDataStore.
    /// Must be sorted by the account IDs and then by the stream configurations,
    /// without identical elements and without 0 amtPerSecs.
    /// @param maxEndHint1 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The first hint for finding the maximum end time when all streams stop due to funds
    /// running out after the balance is updated and the new receivers list is applied.
    /// Hints have no effect on the results of calling this function, except potentially saving gas.
    /// Hints are Unix timestamps used as the starting points for binary search for the time
    /// when funds run out in the range of timestamps from the current block's to `2^32`.
    /// Hints lower than the current timestamp are ignored.
    /// You can provide zero, one or two hints. The order of hints doesn't matter.
    /// Hints are the most effective when one of them is lower than or equal to
    /// the last timestamp when funds are still streamed, and the other one is strictly larger
    /// than that timestamp,the smaller the difference between such hints, the higher gas savings.
    /// The savings are the highest possible when one of the hints is equal to
    /// the last timestamp when funds are still streamed, and the other one is larger by 1.
    /// It's worth noting that the exact timestamp of the block in which this function is executed
    /// may affect correctness of the hints, especially if they're precise.
    /// Hints don't provide any benefits when balance is not enough to cover
    /// a single second of streaming or is enough to cover all streams until timestamp `2^32`.
    /// Even inaccurate hints can be useful, and providing a single hint
    /// or two hints that don't enclose the time when funds run out can still save some gas.
    /// Providing poor hints that don't reduce the number of binary search steps
    /// may cause slightly higher gas usage than not providing any hints.
    /// @param maxEndHint2 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The second hint for finding the maximum end time, see `maxEndHint1` docs for more details.
    /// @param transferTo The address to send funds to in case of decreasing balance
    /// @return realBalanceDelta The actually applied streams balance change.
    /// It's equal to the passed `balanceDelta`, unless it's negative
    /// and it gets capped at the current balance amount.
    function setStreams(
        uint256 tokenId,
        IERC20 erc20,
        int128 balanceDelta,
        bytes32 newStreamsHash,
        // slither-disable-next-line similar-names
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        address transferTo
    ) public onlyProxy returns (int128 realBalanceDelta) {
        // slither-disable-next-line unused-return
        (bytes32 currStreamsHash,,,,) = drips.streamsState(tokenId, erc20);
        bytes memory data = abi.encodeCall(
            nftDriver.setStreams,
            (
                tokenId,
                erc20,
                dripsDataStore.loadStreams(currStreamsHash),
                balanceDelta,
                dripsDataStore.loadStreams(newStreamsHash),
                maxEndHint1,
                maxEndHint2,
                transferTo
            )
        );
        return abi.decode(_callNFTDriver(data), (int128));
    }

    /// @notice Sets the account splits configuration.
    /// The configuration is common for all ERC-20 tokens.
    /// Nothing happens to the currently splittable funds, but when they are split
    /// after this function finishes, the new splits configuration will be used.
    /// Because anybody can call `split` on `Drips`, calling this function may be frontrun
    /// and all the currently splittable funds will be split using the old splits configuration.
    /// @param tokenId The ID of the token representing the configured account ID.
    /// The caller must be the owner of the token or be approved to use it.
    /// The token ID is equal to the account ID controlled by it.
    /// @param splitsHash The hash of the list of the sender's splits receivers to be set,
    /// the actual list must be stored in DripsDataStore.
    /// Must be sorted by the account IDs, without duplicate account IDs and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the account.
    /// If the sum of weights of all receivers is less than `_TOTAL_SPLITS_WEIGHT`,
    /// some funds won't be split, but they will be left for the account to collect.
    /// Fractions of tokens are always rounded either up or down depending on the amount
    /// being split, the receiver's position on the list and the other receivers' weights.
    /// It's valid to include the account's own `accountId` in the list of receivers,
    /// but funds split to themselves return to their splittable balance and are not collectable.
    /// This is usually unwanted, because if splitting is repeated,
    /// funds split to themselves will be again split using the current configuration.
    /// Splitting 100% to self effectively blocks splitting unless the configuration is updated.
    function setSplits(uint256 tokenId, bytes32 splitsHash) public onlyProxy {
        bytes memory data =
            abi.encodeCall(nftDriver.setSplits, (tokenId, dripsDataStore.loadSplits(splitsHash)));
        abi.decode(_callNFTDriver(data), ());
    }

    /// @notice Emits the account metadata for the message sender.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param tokenId The ID of the token representing the emitting account ID.
    /// The caller must be the owner of the token or be approved to use it.
    /// The token ID is equal to the account ID controlled by it.
    /// @param accountMetadataHash The hash of the list of account metadata,
    /// the actual list must be stored in DripsDataStore.
    function emitAccountMetadata(uint256 tokenId, bytes32 accountMetadataHash) public onlyProxy {
        bytes memory data = abi.encodeCall(
            nftDriver.emitAccountMetadata,
            (tokenId, dripsDataStore.loadAccountMetadata(accountMetadataHash))
        );
        abi.decode(_callNFTDriver(data), ());
    }

    /// @notice Calls the `NFTDriver` via Caller on behalf of the `msg.sender`.
    /// @param data The raw calldata to use when calling `NFTDriver`.
    /// @return returnData The raw data returned from `NFTDriver`.
    function _callNFTDriver(bytes memory data) internal returns (bytes memory returnData) {
        return caller.callAs(_msgSender(), address(nftDriver), data);
    }
}
