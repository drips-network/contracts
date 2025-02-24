// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {AccountMetadata, Drips, StreamReceiver, IERC20, SplitsReceiver} from "./Drips.sol";
import {DriverTransferUtils} from "./DriverTransferUtils.sol";
import {Managed} from "./Managed.sol";
import {RepoDriver} from "./RepoDriver.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

/// @notice A Drips driver implementing sub-accounts of RepoDriver accounts.
/// Each RepoDriver account has a single sub-account with a deteministically derived account ID.
/// The sub-account is always owned by the address owning the parent account.
contract RepoSubAccountDriver is DriverTransferUtils, Managed {
    /// @notice The Drips address used by this driver.
    Drips public immutable drips;
    /// @notice The driver ID which this driver uses when calling Drips.
    uint32 public immutable driverId;
    /// @notice The RepoDriver for which sub-accounts are created.
    RepoDriver public immutable repoDriver;
    /// @notice The xor mask to apply when calculating the account ID.
    /// This mask works two ways, if applied on a parent ID it produces its sub-account ID
    /// and if applied on a sub-account ID it produces its parent ID.
    uint256 internal immutable accountIdTranslationMask;

    modifier onlyOwner(uint256 accountId) {
        require(_msgSender() == ownerOf(accountId), "Caller is not the account owner");
        _;
    }

    /// @param repoDriver_ The RepoDriver for which sub-accounts are created.
    /// @param forwarder The ERC-2771 forwarder to trust. May be the zero address.
    /// @param driverId_ The driver ID to use when calling Drips.
    constructor(RepoDriver repoDriver_, address forwarder, uint32 driverId_)
        DriverTransferUtils(forwarder)
    {
        repoDriver = repoDriver_;
        drips = repoDriver.drips();
        driverId = driverId_;
        // By applying xor we get `mask` value:
        // `zeros (224 bits) | driverIdMask (32 bits)`
        // The logic of the xor operation dictates that
        // `driverId ^ mask == repoDriver.driverId()` and that
        // `repoDriver.driverId() ^ mask == driverId`.
        uint256 mask = driverId ^ repoDriver.driverId();
        // By bit shifting we get `accountIdTranslationMask` value:
        // `driverIdMask (32 bits) | zeros (224 bits)`
        accountIdTranslationMask = mask << 224;
    }

    /// @notice Returns the address of the Drips contract to use for ERC-20 transfers.
    function _drips() internal view override returns (Drips) {
        return drips;
    }

    /// @notice Calculates the account ID.
    /// This function works two ways, if `accountId` is a parent ID it produces its sub-account ID
    /// and if `accountId` is a sub-account ID it produces its parent ID.
    /// If `accountId` is neither, an undefined junk account ID is returned.
    /// @param accountId The input account ID.
    /// @return resultAccountId The result account ID.
    function calcAccountId(uint256 accountId) public view returns (uint256 resultAccountId) {
        return accountId ^ accountIdTranslationMask;
    }

    /// @notice Gets the account owner.
    /// Each account is owned by the address owning its parent account.
    /// @param accountId The ID of the account. It must be the sub-account managed by this driver.
    /// @return owner The owner of the account.
    function ownerOf(uint256 accountId) public view returns (address owner) {
        return repoDriver.ownerOf(calcAccountId(accountId));
    }

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
        public
        whenNotPaused
        onlyOwner(accountId)
        returns (uint128 amt)
    {
        return _collectAndTransfer(accountId, erc20, transferTo);
    }

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
    function give(uint256 accountId, uint256 receiver, IERC20 erc20, uint128 amt)
        public
        whenNotPaused
        onlyOwner(accountId)
    {
        _giveAndTransfer(accountId, receiver, erc20, amt);
    }

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
    /// Positive to add funds to the streams balance, negative to remove them.
    /// @param newReceivers The list of the streams receivers of the sender to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
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
    function setStreams(
        uint256 accountId,
        IERC20 erc20,
        StreamReceiver[] calldata currReceivers,
        int128 balanceDelta,
        StreamReceiver[] calldata newReceivers,
        // slither-disable-next-line similar-names
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        address transferTo
    ) public whenNotPaused onlyOwner(accountId) returns (int128 realBalanceDelta) {
        return _setStreamsAndTransfer(
            accountId,
            erc20,
            currReceivers,
            balanceDelta,
            newReceivers,
            maxEndHint1,
            maxEndHint2,
            transferTo
        );
    }

    /// @notice Sets the account splits configuration.
    /// The configuration is common for all ERC-20 tokens.
    /// Nothing happens to the currently splittable funds, but when they are split
    /// after this function finishes, the new splits configuration will be used.
    /// Because anybody can call `split` on `Drips`, calling this function may be frontrun
    /// and all the currently splittable funds will be split using the old splits configuration.
    /// @param accountId The ID of the configured account.
    /// The caller must be the owner of the account.
    /// @param receivers The list of the account's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the account.
    /// If the sum of weights of all receivers is less than `_TOTAL_SPLITS_WEIGHT`,
    /// some funds won't be split, but they will be left for the account to collect.
    /// It's valid to include the account's own `accountId` in the list of receivers,
    /// but funds split to themselves return to their splittable balance and are not collectable.
    /// This is usually unwanted, because if splitting is repeated,
    /// funds split to themselves will be again split using the current configuration.
    /// Splitting 100% to self effectively blocks splitting unless the configuration is updated.
    function setSplits(uint256 accountId, SplitsReceiver[] calldata receivers)
        public
        whenNotPaused
        onlyOwner(accountId)
    {
        drips.setSplits(accountId, receivers);
    }

    /// @notice Emits the account's metadata.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param accountId The ID of the emitting account.
    /// The caller must be the owner of the account.
    /// @param accountMetadata The list of account metadata.
    function emitAccountMetadata(uint256 accountId, AccountMetadata[] calldata accountMetadata)
        public
        whenNotPaused
        onlyOwner(accountId)
    {
        if (accountMetadata.length == 0) return;
        drips.emitAccountMetadata(accountId, accountMetadata);
    }
}
