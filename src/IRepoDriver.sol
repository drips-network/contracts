// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import "./IDrips.sol";

/// @notice The supported forges where repositories are stored.
enum Forge {
    GitHub,
    GitLab
}

/// @notice A Drips driver implementing repository-based account identification.
/// Each repository stored in one of the supported forges has a deterministic account ID assigned.
/// By default the repositories have no owner and their accounts can't be controlled by anybody.
interface IRepoDriver {
    /// @notice Emitted when the account ownership update is requested.
    /// @param accountId The ID of the account.
    /// @param forge The forge where the repository is stored.
    /// @param name The name of the repository.
    event OwnerUpdateRequested(uint256 indexed accountId, Forge forge, bytes name);

    /// @notice Emitted when the account ownership is updated.
    /// @param accountId The ID of the account.
    /// @param owner The new owner of the repository.
    event OwnerUpdated(uint256 indexed accountId, address owner);

    /// @notice The Drips address used by this driver.
    /// @return drips_ The Drips address.
    function drips() external view returns (IDrips drips_);

    /// @notice The driver ID which this driver uses when calling Drips.
    /// @return driverId_ The driver ID.
    function driverId() external view returns (uint32 driverId_);

    /// @notice Calculates the account ID.
    /// Every account ID is a 256-bit integer constructed by concatenating:
    /// `driverId (32 bits) | forgeId (8 bits) | nameEncoded (216 bits)`.
    /// When `forge` is GitHub and `name` is at most 27 bytes long,
    /// `forgeId` is 0 and `nameEncoded` is `name` right-padded with zeros
    /// When `forge` is GitHub and `name` is longer than 27 bytes,
    /// `forgeId` is 1 and `nameEncoded` is the lower 27 bytes of the hash of `name`.
    /// When `forge` is GitLab and `name` is at most 27 bytes long,
    /// `forgeId` is 2 and `nameEncoded` is `name` right-padded with zeros
    /// When `forge` is GitLab and `name` is longer than 27 bytes,
    /// `forgeId` is 3 and `nameEncoded` is the lower 27 bytes of the hash of `name`.
    /// @param forge The forge where the repository is stored.
    /// @param name The name of the repository.
    /// For GitHub and GitLab it must follow the `user_name/repository_name` structure
    /// and it must be formatted identically as in the repository's URL,
    /// including the case of each letter and special characters being removed.
    /// @return accountId The account ID.
    function calcAccountId(Forge forge, bytes calldata name)
        external
        view
        returns (uint256 accountId);

    /// @notice Gets the account owner.
    /// @param accountId The ID of the account.
    /// @return owner The owner of the account.
    function ownerOf(uint256 accountId) external view returns (address owner);

    /// @notice Collects the account's received already split funds
    /// and transfers them out of the Drips contract.
    /// @param accountId The ID of the collecting account.
    /// The caller must be the owner of the account.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param transferTo The address to send collected funds to
    /// @return amt The collected amount
    function collect(uint256 accountId, IERC20 erc20, address transferTo)
        external
        returns (uint128 amt);
    /// @notice Gives funds from the account to the receiver.
    /// The receiver can split and collect them immediately.
    /// Transfers the funds to be given from the message sender's wallet to the Drips contract.
    /// @param accountId The ID of the giving account. The caller must be the owner of the account.
    /// @param receiver The receiver account ID.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param amt The given amount
    function give(uint256 accountId, uint256 receiver, IERC20 erc20, uint128 amt) external;

    /// @notice Sets the account's streams configuration.
    /// Transfers funds between the message sender's wallet and the Drips contract
    /// to fulfil the change of the streams balance.
    /// @param accountId The ID of the configured account.
    /// The caller must be the owner of the account.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param currReceivers The current streams receivers list.
    /// It must be exactly the same as the last list set for the account with `setStreams`.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The streams balance change to be applied.
    /// If it's positive, the balance is increased by `balanceDelta`.
    /// If it's zero, the balance doesn't change.
    /// If it's negative, the balance is decreased by `balanceDelta`,
    /// but the change is capped at the current balance amount, so it doesn't go below 0.
    /// Passing `type(int128).min` always decreases the current balance to 0.
    /// @param newReceivers The list of the streams receivers of the sender to be set.
    /// Must be sorted by the account IDs and then by the stream configurations,
    /// without identical elements and without 0 amtPerSecs.
    /// @param maxEndHints An optional parameter allowing gas optimization.
    /// Pass a list of 8 zero value hints to ignore it, it's represented as an integer `0`.
    /// The list of hints for finding the maximum end time when all streams stop due to funds
    /// running out after the balance is updated and the new receivers list is applied.
    /// Hints have no effect on the results of calling this function, except potentially saving gas.
    /// Hints are Unix timestamps used as the starting points for binary search for the time
    /// when funds run out in the range of timestamps from the current block's to `2^32`.
    /// Hints lower than the current timestamp including the zero value hints are ignored.
    /// If you provide fewer than 8 non-zero value hints make them the rightmost values to save gas.
    /// It's the best approach to make the most risky and precise hints the rightmost ones.
    /// Hints are the most effective when one of them is lower than or equal to
    /// the last timestamp when funds are still streamed, and the other one is strictly larger
    /// than that timestamp, the smaller the difference between such hints, the more gas is saved.
    /// The savings are the highest possible when one of the hints is equal to
    /// the last timestamp when funds are still streamed, and the other one is larger by 1.
    /// It's worth noting that the exact timestamp of the block in which this function is executed
    /// may affect correctness of the hints, especially if they're precise.
    /// Hints don't provide any benefits when balance is not enough to cover
    /// a single second of streaming or is enough to cover all streams until timestamp `2^32`.
    /// Even inaccurate hints can be useful, and providing a single hint
    /// or hints that don't enclose the time when funds run out can still save some gas.
    /// Providing poor hints that don't reduce the number of binary search steps
    /// may cause slightly higher gas usage than not providing any hints.
    /// @param transferTo The address to send funds to in case of decreasing balance
    /// @return realBalanceDelta The actually applied streams balance change.
    /// It's equal to the passed `balanceDelta`, unless it's negative
    /// and it gets capped at the current balance amount.
    function setStreams(
        uint256 accountId,
        IERC20 erc20,
        StreamReceiver[] calldata currReceivers,
        int128 balanceDelta,
        StreamReceiver[] calldata newReceivers,
        MaxEndHints maxEndHints,
        address transferTo
    ) external returns (int128 realBalanceDelta);

    /// @notice Sets the account splits configuration.
    /// The configuration is common for all ERC-20 tokens.
    /// Nothing happens to the currently splittable funds, but when they are split
    /// after this function finishes, the new splits configuration will be used.
    /// Because anybody can call `split` on `Drips`, calling this function may be frontrun
    /// and all the currently splittable funds will be split using the old splits configuration.
    /// @param accountId The ID of the configured account.
    /// The caller must be the owner of the account.
    /// @param receivers The list of the account's splits receivers to be set.
    /// Must be sorted by the account IDs, without duplicate account IDs and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the account.
    /// If the sum of weights of all receivers is less than `DripsLib.TOTAL_SPLITS_WEIGHT`,
    /// some funds won't be split, but they will be left for the account to collect.
    /// Fractions of tokens are always rounded either up or down depending on the amount
    /// being split, the receiver's position on the list and the other receivers' weights.
    /// It's valid to include the account's own `accountId` in the list of receivers,
    /// but funds split to themselves return to their splittable balance and are not collectable.
    /// This is usually unwanted, because if splitting is repeated,
    /// funds split to themselves will be again split using the current configuration.
    /// Splitting 100% to self effectively blocks splitting unless the configuration is updated.
    function setSplits(uint256 accountId, SplitsReceiver[] calldata receivers) external;

    /// @notice Emits the account's metadata.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param accountId The ID of the emitting account.
    /// The caller must be the owner of the account.
    /// @param accountMetadata The list of account metadata.
    function emitAccountMetadata(uint256 accountId, AccountMetadata[] calldata accountMetadata)
        external;
}
