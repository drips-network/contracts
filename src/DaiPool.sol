// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {ERC20Pool, Receiver} from "./ERC20Pool.sol";
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

struct PermitArgs {
    uint256 nonce;
    uint256 expiry;
    uint8 v;
    bytes32 r;
    bytes32 s;
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
    /// These parameters will be passed to the Dai contract by this function.
    /// @param permitArgs The Dai permission arguments.
    function updateSenderAndPermit(
        uint128 topUpAmt,
        uint128 withdraw,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers,
        PermitArgs calldata permitArgs
    ) public returns (uint128 withdrawn) {
        permit(permitArgs);
        return updateSender(topUpAmt, withdraw, currReceivers, newReceivers);
    }

    /// @notice Updates all the parameters of a sub-sender of the sender of the message
    /// and permits spending sender's Dai by the pool.
    /// This function is an extension of `updateSubSender`, see its documentation for more details.
    ///
    /// The sender must sign a Dai permission document allowing the pool to spend their funds.
    /// These parameters will be passed to the Dai contract by this function.
    /// @param permitArgs The Dai permission arguments.
    function updateSubSenderAndPermit(
        uint256 subSenderId,
        uint128 topUpAmt,
        uint128 withdraw,
        Receiver[] calldata currReceivers,
        Receiver[] calldata newReceivers,
        PermitArgs calldata permitArgs
    ) public returns (uint128 withdrawn) {
        permit(permitArgs);
        return updateSubSender(subSenderId, topUpAmt, withdraw, currReceivers, newReceivers);
    }

    /// @notice Gives funds from the sender of the message to the receiver
    /// and permits spending sender's Dai by the pool.
    /// This function is an extension of `give`, see its documentation for more details.
    ///
    /// The sender must sign a Dai permission document allowing the pool to spend their funds.
    /// These parameters will be passed to the Dai contract by this function.
    /// @param permitArgs The Dai permission arguments.
    function giveAndPermit(
        address receiver,
        uint128 amt,
        PermitArgs calldata permitArgs
    ) public {
        permit(permitArgs);
        give(receiver, amt);
    }

    /// @notice Gives funds from the sub-sender of the sender of the message to the receiver
    /// and permits spending sender's Dai by the pool.
    /// This function is an extension of `giveFromSubSender` see its documentation for more details.
    ///
    /// The sender must sign a Dai permission document allowing the pool to spend their funds.
    /// These parameters will be passed to the Dai contract by this function.
    /// @param permitArgs The Dai permission arguments.
    function giveFromSubSenderAndPermit(
        uint256 subSenderId,
        address receiver,
        uint128 amt,
        PermitArgs calldata permitArgs
    ) public {
        permit(permitArgs);
        giveFromSubSender(subSenderId, receiver, amt);
    }

    /// @notice Permits the pool to spend the message sender's Dai.
    /// @param permitArgs The Dai permission arguments.
    function permit(PermitArgs calldata permitArgs) internal {
        dai.permit(
            msg.sender,
            address(this),
            permitArgs.nonce,
            permitArgs.expiry,
            true,
            permitArgs.v,
            permitArgs.r,
            permitArgs.s
        );
    }
}
