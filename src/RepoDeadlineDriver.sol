// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Drips, IERC20} from "./Drips.sol";
import {Managed} from "./Managed.sol";
import {RepoDriver} from "./RepoDriver.sol";

// TODO
/// @notice A Drips driver for funding an account if a RepoDriver account is claimed
/// with a refund feature in case the repo isn't claimed in the given time.
/// Each repo account - recipient account - refund account - deadline
/// triplet is deterministically assigned a unique account ID.
/// The resulting account ID doesn't need to be explicitly created,
/// it can be funded without any prior iteraction with this driver.
/// The accounts are permissionless, they don't have owners
/// and anybody can trigger the flow of funds.
contract RepoDeadlineDriver is Managed {
    /// @notice The Drips address used by this driver.
    Drips public immutable drips;
    /// @notice The driver ID which this driver uses when calling Drips.
    uint32 public immutable driverId;
    /// @notice The RepoDriver for which claim deadlines are created.
    RepoDriver public immutable repoDriver;

    /// @notice Emitted when an account is seen because it's interacted with.
    /// @return accountId The account ID that is seen.
    /// It's calculated from the account IDs and  the deadline.
    /// @param repoAccountId The RepoDriver account ID that is checked for being claimed.
    /// The account is considered claimed while its owner is not the zero address.
    /// @param recipientAccountId The account ID that receives funds if `repoAccountId` is claimed.
    /// @param refundAccountId The account ID that receives funds if `repoAccountId` isn't claimed.
    /// @param deadline The timestamp from which `refundAccountId`
    /// receives funds if `repoAccountId` is unclaimed.
    /// If `repoAccountId` is claimed at the moment, it receives funds regardless of the deadline.
    event AccountSeen(
        uint256 indexed accountId,
        uint256 repoAccountId,
        uint256 indexed recipientAccountId,
        uint256 indexed refundAccountId,
        uint32 deadline
    );

    /// @param repoDriver_ The RepoDriver for which sub-accounts are created.
    /// @param driverId_ The driver ID to use when calling Drips.
    constructor(RepoDriver repoDriver_, uint32 driverId_) {
        repoDriver = repoDriver_;
        drips = repoDriver.drips();
        driverId = driverId_;
    }

    /// @notice Calculates the account ID.
    /// @param repoAccountId The RepoDriver account ID that is checked for being claimed.
    /// The account is considered claimed while its owner is not the zero address.
    /// @param recipientAccountId The account ID that receives funds if `repoAccountId` is claimed.
    /// @param refundAccountId The account ID that receives funds if `repoAccountId` isn't claimed.
    /// @param deadline The timestamp from which `refundAccountId`
    /// receives funds if `repoAccountId` is unclaimed.
    /// If `repoAccountId` is claimed at the moment, it receives funds regardless of the deadline.
    /// @return accountId The result account ID.
    function calcAccountId(
        uint256 repoAccountId,
        uint256 recipientAccountId,
        uint256 refundAccountId,
        uint32 deadline
    ) public view returns (uint256 accountId) {
        uint192 accountsHash = uint192(
            uint256(keccak256(abi.encodePacked(repoAccountId, recipientAccountId, refundAccountId)))
        );
        // By assignment we get `accountId` value:
        // `zeros (224 bits) | driverId (32 bits)`
        accountId = driverId;
        // By bit shifting we get `accountId` value:
        // `zeros (32 bits) | driverId (32 bits) | zeros (192 bits)`
        // By bit masking we get `accountId` value:
        // `zeros (32 bits) | driverId (32 bits) | accountsHash (192 bits)`
        accountId = (accountId << 192) | accountsHash;
        // By bit shifting we get `accountId` value:
        // `driverId (32 bits) | accountsHash (192 bits) | zeros (32 bits)`
        // By bit masking we get `accountId` value:
        // `driverId (32 bits) | accountsHash (192 bits) | deadline (32 bits)`
        accountId = (accountId << 32) | deadline;
    }

    /// @notice Distributes funds received by the account with ID
    /// calculated from the account IDs and  the deadline.
    /// Collects and then gives these funds to the account eligible for funding.
    /// If neither is eligible, the funds are not collected and not given.
    /// This function doesn't call `receiveStreams` or `split` on Drips, it's up to
    /// the users to do that in order to maximize the account's collectable balance.
    /// Calling this function always emits an event announcing the recipients of the account.
    /// @param repoAccountId The RepoDriver account ID that is checked for being claimed.
    /// The account is considered claimed while its owner is not the zero address.
    /// @param recipientAccountId The account ID that receives funds if `repoAccountId` is claimed.
    /// @param refundAccountId The account ID that receives funds if `repoAccountId` isn't claimed.
    /// @param deadline The timestamp from which `refundAccountId`
    /// receives funds if `repoAccountId` is unclaimed.
    /// If `repoAccountId` is claimed at the moment, it receives funds regardless of the deadline.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    function collectAndGive(
        uint256 repoAccountId,
        uint256 recipientAccountId,
        uint256 refundAccountId,
        uint32 deadline,
        IERC20 erc20
    ) public whenNotPaused returns (uint128 amt) {
        uint256 accountId =
            calcAccountId(repoAccountId, recipientAccountId, refundAccountId, deadline);
        emit AccountSeen(accountId, repoAccountId, recipientAccountId, refundAccountId, deadline);
        uint256 giveTo;
        if (repoDriver.ownerOf(repoAccountId) != address(0)) {
            giveTo = recipientAccountId;
        } else if (block.timestamp >= deadline) {
            giveTo = refundAccountId;
        } else {
            return 0;
        }
        if (drips.collectable(accountId, erc20) == 0) return 0;
        amt = drips.collect(accountId, erc20);
        drips.give(accountId, giveTo, erc20, amt);
    }
}
