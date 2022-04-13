// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DripsHub, DripsReceiver, SplitsReceiver} from "./DripsHub.sol";
import {IERC20Reserve} from "./ERC20Reserve.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract AddressId {
    DripsHub public immutable dripsHub;
    address public immutable reserve;
    uint32 public immutable accountId;

    /// @param _dripsHub The drips hub to use
    constructor(DripsHub _dripsHub) {
        dripsHub = _dripsHub;
        reserve = address(_dripsHub.reserve());
        accountId = _dripsHub.createAccount(address(this));
    }

    /// @notice Calculates the user ID for an address
    /// @param userAddr The user address
    /// @return userId The user ID
    function calcUserId(address userAddr) public view returns (uint256 userId) {
        return (uint256(accountId) << 224) | uint160(userAddr);
    }

    /// @notice Collects all received funds available for the user
    /// and transfers them out of the drips hub contract to that user.
    /// @param erc20 The token to use
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectedAmt The collected amount
    /// @return splitAmt The amount split to the user's splits receivers
    function collectAll(
        address user,
        IERC20 erc20,
        SplitsReceiver[] memory currReceivers
    ) public returns (uint128 collectedAmt, uint128 splitAmt) {
        (collectedAmt, splitAmt) = dripsHub.collectAll(
            calcUserId(user),
            _calcAssetId(erc20),
            currReceivers
        );
        _transferTo(user, erc20, collectedAmt);
    }

    /// @notice Collects the user's received already split funds
    /// and transfers them out of the drips hub contract to that user.
    /// @param erc20 The token to use
    /// @return amt The collected amount
    function collect(address user, IERC20 erc20) public returns (uint128 amt) {
        amt = dripsHub.collect(calcUserId(user), _calcAssetId(erc20));
        _transferTo(user, erc20, amt);
    }

    /// @notice Gives funds from the msg.sender to the receiver.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the msg.sender's wallet to the drips hub contract.
    /// @param receiver The receiver
    /// @param erc20 The token to use
    /// @param amt The given amount
    function give(
        uint256 receiver,
        IERC20 erc20,
        uint128 amt
    ) public {
        _transferFromCaller(erc20, amt);
        dripsHub.give(calcUserId(msg.sender), receiver, _calcAssetId(erc20), amt);
    }

    /// @notice Sets the msg.sender's drips configuration.
    /// Transfers funds between the msg.sender's wallet and the drips hub contract
    /// to fulfill the change of the drips balance.
    /// @param erc20 The token to use
    /// @param lastUpdate The timestamp of the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user or the account.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the user or the account to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the user or the account.
    /// Pass it as `lastBalance` when updating that user or the account for the next time.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        IERC20 erc20,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) public returns (uint128 newBalance, int128 realBalanceDelta) {
        if (balanceDelta > 0) _transferFromCaller(erc20, uint128(balanceDelta));
        (newBalance, realBalanceDelta) = dripsHub.setDrips(
            calcUserId(msg.sender),
            _calcAssetId(erc20),
            lastUpdate,
            lastBalance,
            currReceivers,
            balanceDelta,
            newReceivers
        );
        if (realBalanceDelta < 0) _transferTo(msg.sender, erc20, uint128(-realBalanceDelta));
    }

    /// @notice Sets msg.sender's splits configuration.
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    function setSplits(SplitsReceiver[] memory receivers) public {
        dripsHub.setSplits(calcUserId(msg.sender), receivers);
    }

    function _calcAssetId(IERC20 erc20) internal pure returns (uint256) {
        return uint160(address(erc20));
    }

    function _transferFromCaller(IERC20 erc20, uint128 amt) internal {
        require(erc20.transferFrom(msg.sender, address(this), amt), "Transfer from caller failed");
        if (erc20.allowance(address(this), reserve) < amt) {
            erc20.approve(reserve, type(uint256).max);
        }
    }

    function _transferTo(
        address receiver,
        IERC20 erc20,
        uint128 amt
    ) internal {
        require(erc20.transfer(receiver, amt), "Transfer to caller failed");
    }
}
