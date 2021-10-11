// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {ERC20Pool, ReceiverWeight} from "./ERC20Pool.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IDai is IERC20 {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @notice Funding pool contract for DAI token.
/// See the base `Pool` contract docs for more details.
contract DaiPool is ERC20Pool {
    /// @notice The address of the Dai contract which tokens the pool works with.
    /// Always equal to `erc20`, but more strictly typed.
    IDai public immutable dai;

    /// @notice See `ERC20Pool` constructor documentation for more details.
    constructor(uint64 cycleSecs, IDai _dai) ERC20Pool(cycleSecs, _dai) {
        dai = _dai;
    }

    /// @notice Updates all the sender parameters of the sender of the message
    /// and permits spending sender's Dai by the pool.
    /// This function is an extension of `updateSender`, see its documentation for more details.
    ///
    /// The sender must sign a Dai permission document allowing the pool to spend their funds.
    /// The document's `nonce` and `expiry` must be passed here along the parts of its signature.
    /// These parameters will be passed to the Dai contract by this function.
    function updateSenderAndPermit(
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        uint32 dripsFraction,
        ReceiverWeight[] calldata updatedReceivers,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (uint128 withdrawn) {
        dai.permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
        return updateSender(topUpAmt, withdraw, amtPerSec, dripsFraction, updatedReceivers);
    }

    /// @notice Updates all the parameters of a sub-sender of the sender of the message
    /// and permits spending sender's Dai by the pool.
    /// This function is an extension of `updateSubSender`, see its documentation for more details.
    /// @param subSenderId The id of the sender's sub-sender
    function updateSubSenderAndPermit(
        uint256 subSenderId,
        uint128 topUpAmt,
        uint128 withdraw,
        uint128 amtPerSec,
        ReceiverWeight[] calldata updatedReceivers,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (uint128 withdrawn) {
        dai.permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
        return updateSubSender(subSenderId, topUpAmt, withdraw, amtPerSec, updatedReceivers);
    }
}
