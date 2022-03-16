// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {SplitsReceiver, DripsReceiver} from "./DripsHub.sol";
import {ManagedDripsHub} from "./ManagedDripsHub.sol";
import {IERC20Reserve} from "./ERC20Reserve.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";

/// @notice Drips hub contract for any ERC-20 token. Must be used via a proxy.
/// See the base `DripsHub` and `ManagedDripsHub` contract docs for more details.
contract ERC20DripsHub is ManagedDripsHub {
    /// @notice The address of the ERC-20 reserve which the drips hub works with
    IERC20Reserve public immutable reserve;

    /// @param cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being collectable by their receivers.
    /// High value makes collecting cheaper by making it process less cycles for a given time range.
    /// @param _reserve The address of the ERC-20 reserve which the drips hub will work with
    constructor(uint64 cycleSecs, IERC20Reserve _reserve) ManagedDripsHub(cycleSecs) {
        reserve = _reserve;
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

    /// @notice Gives funds from the `msg.sender` to the receiver.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the sender's wallet to the drips hub contract.
    /// @param receiver The receiver user ID
    /// @param assetId The used asset ID
    /// @param amt The given amount
    function give(
        uint256 receiver,
        uint256 assetId,
        uint128 amt
    ) public whenNotPaused {
        _give(calcUserId(msg.sender), receiver, assetId, amt);
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
            uint256 withdraw = uint128(amt);
            reserve.withdraw(erc20, withdraw);
            erc20.transfer(msg.sender, withdraw);
        } else if (amt < 0) {
            uint256 deposit = uint128(-amt);
            erc20.transferFrom(msg.sender, address(this), deposit);
            erc20.approve(address(reserve), deposit);
            reserve.deposit(erc20, deposit);
        }
    }
}
