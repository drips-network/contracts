// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DripsHub, SplitsReceiver, DripsReceiver} from "./DripsHub.sol";
import {Managed} from "./Managed.sol";
import {IERC20Reserve} from "./ERC20Reserve.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";

/// @notice Drips hub contract for any ERC-20 token. Must be used via a proxy.
/// See the base `DripsHub` and `Managed` contract docs for more details.
contract ERC20DripsHub is Managed, DripsHub {
    /// @notice The ERC-1967 storage slot holding a single `DripsHubStorage` structure.
    bytes32 private immutable storageSlot = erc1967Slot("eip1967.dripsHub.storage");

    /// @notice The address of the ERC-20 reserve which the drips hub works with
    IERC20Reserve public immutable reserve;

    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being collectable by their receivers.
    /// High value makes collecting cheaper by making it process less cycles for a given time range.
    /// @param _reserve The address of the ERC-20 reserve which the drips hub will work with
    constructor(uint64 cycleSecs, IERC20Reserve _reserve) DripsHub(cycleSecs) {
        reserve = _reserve;
    }

    /// @notice Creates an account.
    /// Assigns it an ID and lets its owner perform actions on behalf of all its sub-accounts.
    /// Multiple accounts can be registered for a single address, it will own all of them.
    /// @return accountId The new account ID.
    function createAccount(address owner) public override whenNotPaused returns (uint32 accountId) {
        return super.createAccount(owner);
    }

    /// @notice Collects all received funds available for the user
    /// and transfers them out of the drips hub contract to msg.sender.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectedAmt The collected amount
    /// @return splitAmt The amount split to the user's splits receivers
    function collectAll(
        uint256 userId,
        uint256 assetId,
        SplitsReceiver[] memory currReceivers
    ) public override whenNotPaused returns (uint128 collectedAmt, uint128 splitAmt) {
        return super.collectAll(userId, assetId, currReceivers);
    }

    /// @notice Receive drips from uncollected cycles of the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// Calling this function does not collect but makes the funds ready to be split and collected.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The received amount
    /// @return receivableCycles The number of cycles which still can be received
    function receiveDrips(
        uint256 userId,
        uint256 assetId,
        uint64 maxCycles
    ) public override whenNotPaused returns (uint128 receivedAmt, uint64 receivableCycles) {
        return super.receiveDrips(userId, assetId, maxCycles);
    }

    /// @notice Splits user's received but not split yet funds among receivers.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectableAmt The amount made collectable for the user
    /// on top of what was collectable before.
    /// @return splitAmt The amount split to the user's splits receivers
    function split(
        uint256 userId,
        uint256 assetId,
        SplitsReceiver[] memory currReceivers
    ) public override whenNotPaused returns (uint128 collectableAmt, uint128 splitAmt) {
        return super.split(userId, assetId, currReceivers);
    }

    /// @notice Collects user's received already split funds
    /// and transfers them out of the drips hub contract to msg.sender.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return amt The collected amount
    function collect(uint256 userId, uint256 assetId)
        public
        override
        whenNotPaused
        returns (uint128 amt)
    {
        return super.collect(userId, assetId);
    }

    /// @notice Sets the drips configuration of the user. See `setDrips` for more details.
    /// @param userId The user ID
    function setDrips(
        uint256 userId,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) public whenNotPaused returns (uint128 newBalance, int128 realBalanceDelta) {
        return
            _setDrips(
                userId,
                assetId,
                lastUpdate,
                lastBalance,
                currReceivers,
                balanceDelta,
                newReceivers
            );
    }

    /// @notice Gives funds from the user to the receiver.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the sender's wallet to the drips hub contract.
    /// @param userId The user ID
    /// @param receiver The receiver user ID
    /// @param assetId The used asset ID
    /// @param amt The given amount
    function give(
        uint256 userId,
        uint256 receiver,
        uint256 assetId,
        uint128 amt
    ) public whenNotPaused {
        _give(userId, receiver, assetId, amt);
    }

    /// @notice Sets user splits configuration.
    /// @param userId The user ID
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    function setSplits(uint256 userId, SplitsReceiver[] memory receivers) public whenNotPaused {
        _setSplits(userId, receivers);
    }

    function _transfer(uint256 assetId, int128 amt) internal override {
        IERC20 erc20 = IERC20(address(uint160(assetId)));
        if (amt > 0) {
            reserve.withdraw(erc20, msg.sender, uint128(amt));
        } else if (amt < 0) {
            reserve.deposit(erc20, msg.sender, uint128(-amt));
        }
    }

    /// @notice Returns the DripsHub storage.
    /// @return storageRef The storage.
    function _dripsHubStorage()
        internal
        view
        override
        returns (DripsHubStorage storage storageRef)
    {
        bytes32 slot = storageSlot;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Based on OpenZeppelin's StorageSlot
            storageRef.slot := slot
        }
    }
}
