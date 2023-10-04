// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {DripsDataStore} from "./DripsDataStore.sol";
import {Caller} from "../Caller.sol";
import {AccountMetadata, Drips, StreamReceiver, IERC20, SplitsReceiver} from "../Drips.sol";
import {Managed} from "../Managed.sol";
import {RepoDriver} from "../RepoDriver.sol";
import {ERC2771Context} from "openzeppelin-contracts/metatx/ERC2771Context.sol";

/// @notice A data proxy for `RepoDriver`.
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
contract RepoDriverDataProxy is ERC2771Context, Managed {
    /// @notice The Drips contract used by this proxy.
    Drips public immutable drips;
    /// @notice The RepoDriver contract used by this proxy.
    RepoDriver public immutable repoDriver;
    /// @notice The DripsDataStore contract used by this proxy.
    DripsDataStore public immutable dripsDataStore;
    // @notice The Caller contract used by this proxy. It's also the trusted ERC-2771 forwarder.
    Caller public immutable caller;

    /// @param repoDriver_ The RepoDriver contract to use.
    /// @param dripsDataStore_ The DripsDataStore contract to use.
    /// @param caller_ The Caller contract to use. It's also the trusted ERC-2771 forwarder.
    constructor(RepoDriver repoDriver_, DripsDataStore dripsDataStore_, Caller caller_)
        ERC2771Context(address(caller_))
    {
        drips = repoDriver_.drips();
        repoDriver = repoDriver_;
        dripsDataStore = dripsDataStore_;
        caller = caller_;
    }

    /// @notice Sets the account's streams configuration.
    /// Transfers funds between the message sender's wallet and the Drips contract
    /// to fulfil the change of the streams balance.
    /// The currently set list of stream receivers must be stored in DripsDataStore.
    /// @param accountId The ID of the configured account.
    /// The caller must be the owner of the account.
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
        uint256 accountId,
        IERC20 erc20,
        int128 balanceDelta,
        bytes32 newStreamsHash,
        // slither-disable-next-line similar-names
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        address transferTo
    ) public whenNotPaused returns (int128 realBalanceDelta) {
        // slither-disable-next-line unused-return
        (bytes32 currStreamsHash,,,,) = drips.streamsState(accountId, erc20);
        bytes memory data = abi.encodeCall(
            repoDriver.setStreams,
            (
                accountId,
                erc20,
                dripsDataStore.loadStreams(currStreamsHash),
                balanceDelta,
                dripsDataStore.loadStreams(newStreamsHash),
                maxEndHint1,
                maxEndHint2,
                transferTo
            )
        );
        return abi.decode(_callRepoDriver(data), (int128));
    }

    /// @notice Sets the account splits configuration.
    /// The configuration is common for all ERC-20 tokens.
    /// Nothing happens to the currently splittable funds, but when they are split
    /// after this function finishes, the new splits configuration will be used.
    /// Because anybody can call `split` on `Drips`, calling this function may be frontrun
    /// and all the currently splittable funds will be split using the old splits configuration.
    /// @param accountId The ID of the configured account.
    /// The caller must be the owner of the account.
    /// @param splitsHash The hash of the list of the sender's splits receivers to be set,
    /// the actual list must be stored in DripsDataStore.
    /// Must be sorted by the account IDs, without duplicate account IDs and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the account.
    /// If the sum of weights of all receivers is less than `_TOTAL_SPLITS_WEIGHT`,
    /// some funds won't be split, but they will be left for the account to collect.
    /// Fractions of tokens are always rounder either up or down depending on the amount
    /// being split, the receiver's position on the list and the other receivers' weights.
    /// It's valid to include the account's own `accountId` in the list of receivers,
    /// but funds split to themselves return to their splittable balance and are not collectable.
    /// This is usually unwanted, because if splitting is repeated,
    /// funds split to themselves will be again split using the current configuration.
    /// Splitting 100% to self effectively blocks splitting unless the configuration is updated.
    function setSplits(uint256 accountId, bytes32 splitsHash) public whenNotPaused {
        bytes memory data =
            abi.encodeCall(repoDriver.setSplits, (accountId, dripsDataStore.loadSplits(splitsHash)));
        abi.decode(_callRepoDriver(data), ());
    }

    /// @notice Emits the account metadata for the message sender.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param accountId The ID of the emitting account.
    /// The caller must be the owner of the account.
    /// @param accountMetadataHash The hash of the list of account metadata,
    /// the actual list must be stored in DripsDataStore.
    function emitAccountMetadata(uint256 accountId, bytes32 accountMetadataHash)
        public
        whenNotPaused
    {
        bytes memory data = abi.encodeCall(
            repoDriver.emitAccountMetadata,
            (accountId, dripsDataStore.loadAccountMetadata(accountMetadataHash))
        );
        abi.decode(_callRepoDriver(data), ());
    }

    /// @notice Calls the `RepoDriver` via Caller on behalf of the `msg.sender`.
    /// @param data The raw calldata to use when calling `RepoDriver`.
    /// @return returnData The raw data returned from `RepoDriver`.
    function _callRepoDriver(bytes memory data) internal returns (bytes memory returnData) {
        return caller.callAs(_msgSender(), address(repoDriver), data);
    }
}
