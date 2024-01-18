// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {DripsDataStore} from "./DripsDataStore.sol";
import {Drips, StreamReceiver, IERC20, SplitsReceiver} from "../Drips.sol";
import {Managed} from "../Managed.sol";

/// @notice A data proxy for `Drips`.
/// Large parameters aren't passed in calldata, but instead their hashes are accepted,
/// and the actual data is loaded from `DripsDataStore`.
/// The data must be explicitly stored in `DripsDataStore` before its usage.
///
/// In some cases using the proxy is easier and cheaper than calling the driver directly.
/// For example multisigs and governance contracts often need the whole calldata
/// provided as a binary blob, which then sometimes needs to be stored on-chain.
/// It's easier to build calldata consisting of a flat list of scalar parameters,
/// and calldata is much smaller when large lists are substituted with their hashes.
contract DripsDataProxy is Managed {
    /// @notice The Drips contract used by this proxy.
    Drips public immutable drips;
    /// @notice The DripsDataStore contract used by this proxy.
    DripsDataStore public immutable dripsDataStore;

    /// @param drips_ The Drips contract to use.
    /// @param dripsDataStore_ The DripsDataStore contract to use.
    constructor(Drips drips_, DripsDataStore dripsDataStore_) {
        drips = drips_;
        dripsDataStore = dripsDataStore_;
    }

    /// @notice Receive streams from the currently running cycle from a single sender.
    /// It doesn't receive streams from the finished cycles, to do that use `receiveStreams`.
    /// Squeezed funds won't be received in the next calls to `squeezeStreams` or `receiveStreams`.
    /// Only funds streamed before `block.timestamp` can be squeezed.
    /// @param accountId The ID of the account receiving streams to squeeze funds for.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param senderId The ID of the streaming account to squeeze funds from.
    /// @param historyStartHash The sender's history hash that was valid right before
    /// they set up the sequence of configurations described by `streamsHistoryHash`.
    /// @param streamsHistoryHash The hash of the sequence of the sender's streams configurations,
    /// the actual list must be stored in DripsDataStore.
    /// It can start at an arbitrary past configuration, but must describe all the configurations
    /// which have been used since then including the current one, in the chronological order.
    /// Only streams described by `streamsHistoryHash` will be squeezed.
    /// If `streamsHistoryHash` entries have no receivers, they won't be squeezed.
    /// @return amt The squeezed amount.
    function squeezeStreams(
        uint256 accountId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyStartHash,
        bytes32 streamsHistoryHash
    ) public whenNotPaused returns (uint128 amt) {
        return drips.squeezeStreams(
            accountId,
            erc20,
            senderId,
            historyStartHash,
            dripsDataStore.loadStreamsHistory(streamsHistoryHash)
        );
    }

    /// @notice Calculate effects of calling `squeezeStreams` with the given parameters.
    /// See its documentation for more details.
    /// @param accountId The ID of the account receiving streams to squeeze funds for.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param senderId The ID of the streaming account to squeeze funds from.
    /// @param historyStartHash The sender's history hash that was valid right before
    /// they set up the sequence of configurations described by `streamsHistoryHash`.
    /// @param streamsHistoryHash The hash of the sequence of the sender's streams configurations,
    /// the actual list must be stored in DripsDataStore.
    /// @return amt The squeezed amount.
    function squeezeStreamsResult(
        uint256 accountId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyStartHash,
        bytes32 streamsHistoryHash
    ) public view returns (uint128 amt) {
        return drips.squeezeStreamsResult(
            accountId,
            erc20,
            senderId,
            historyStartHash,
            dripsDataStore.loadStreamsHistory(streamsHistoryHash)
        );
    }

    /// @notice Calculate the result of splitting an amount using the current splits configuration.
    /// The currently set list of splits receivers must be stored in DripsDataStore.
    /// @param accountId The account ID.
    /// @param amount The amount being split.
    /// @return collectableAmt The amount made collectable for the account
    /// on top of what was collectable before.
    /// @return splitAmt The amount split to the account's splits receivers
    function splitResult(uint256 accountId, uint128 amount)
        public
        view
        returns (uint128 collectableAmt, uint128 splitAmt)
    {
        bytes32 splitsHash = drips.splitsHash(accountId);
        // slither-disable-next-line unused-return
        return drips.splitResult(accountId, dripsDataStore.loadSplits(splitsHash), amount);
    }

    /// @notice Splits the account's splittable funds among receivers.
    /// The entire splittable balance of the given ERC-20 token is split.
    /// All split funds are split using the current splits configuration.
    /// Because the account can update their splits configuration at any time,
    /// it is possible that calling this function will be frontrun,
    /// and all the splittable funds will become splittable only using the new configuration.
    /// The account must be trusted with how funds sent to them will be splits,
    /// in the end they can do with their funds whatever they want by changing the configuration.
    /// The currently set list of splits receivers must be stored in DripsDataStore.
    /// @param accountId The account ID.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @return collectableAmt The amount made collectable for the account
    /// on top of what was collectable before.
    /// @return splitAmt The amount split to the account's splits receivers
    function split(uint256 accountId, IERC20 erc20)
        public
        whenNotPaused
        returns (uint128 collectableAmt, uint128 splitAmt)
    {
        bytes32 splitsHash = drips.splitsHash(accountId);
        // slither-disable-next-line unused-return
        return drips.split(accountId, erc20, dripsDataStore.loadSplits(splitsHash));
    }

    /// @notice The account's streams balance at the given timestamp.
    /// The currently set list of stream receivers must be stored in DripsDataStore.
    /// @param accountId The account ID.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param timestamp The timestamp for which balance should be calculated.
    /// It can't be lower than the timestamp of the last call to `setStreams`.
    /// If it's bigger than `block.timestamp`, then it's a prediction assuming
    /// that `setStreams` won't be called before `timestamp`.
    /// @return balance The account balance on `timestamp`
    function balanceAt(uint256 accountId, IERC20 erc20, uint32 timestamp)
        public
        view
        returns (uint128 balance)
    {
        // slither-disable-next-line unused-return
        (bytes32 streamsHash,,,,) = drips.streamsState(accountId, erc20);
        return drips.balanceAt(accountId, erc20, dripsDataStore.loadStreams(streamsHash), timestamp);
    }
}
