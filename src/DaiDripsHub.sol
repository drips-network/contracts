// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {ERC20DripsHub, DripsReceiver, SplitsReceiver} from "./ERC20DripsHub.sol";
import {IDai} from "./Dai.sol";
import {IDaiReserve} from "./DaiReserve.sol";

struct PermitArgs {
    uint256 nonce;
    uint256 expiry;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @notice Drips hub contract for DAI token. Must be used via a proxy.
/// See the base `DripsHub` contract docs for more details.
contract DaiDripsHub is ERC20DripsHub {
    /// @notice The address of the Dai contract which tokens the drips hub works with.
    /// Always equal to `erc20`, but more strictly typed.
    IDai public immutable dai;

    /// @notice See `ERC20DripsHub` constructor documentation for more details.
    constructor(uint64 cycleSecs, IDai _dai) ERC20DripsHub(cycleSecs, _dai) {
        dai = _dai;
    }

    /// @notice Sets the drips configuration of the `msg.sender`
    /// and permits spending their Dai by the drips hub.
    /// This function is an extension of `setDrips`, see its documentation for more details.
    ///
    /// The user must sign a Dai permission document allowing the drips hub to spend their funds.
    /// These parameters will be passed to the Dai contract by this function.
    /// @param permitArgs The Dai permission arguments.
    function setDripsAndPermit(
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers,
        PermitArgs calldata permitArgs
    ) public whenNotPaused returns (uint128 newBalance, int128 realBalanceDelta) {
        _permit(permitArgs);
        return setDrips(lastUpdate, lastBalance, currReceivers, balanceDelta, newReceivers);
    }

    /// @notice Sets the drips configuration of an account of the `msg.sender`
    /// and permits spending their Dai by the drips hub.
    /// This function is an extension of `setDrips`, see its documentation for more details.
    ///
    /// The user must sign a Dai permission document allowing the drips hub to spend their funds.
    /// These parameters will be passed to the Dai contract by this function.
    /// @param permitArgs The Dai permission arguments.
    function setDripsAndPermit(
        uint256 account,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers,
        PermitArgs calldata permitArgs
    ) public whenNotPaused returns (uint128 newBalance, int128 realBalanceDelta) {
        _permit(permitArgs);
        return
            setDrips(account, lastUpdate, lastBalance, currReceivers, balanceDelta, newReceivers);
    }

    /// @notice Gives funds from the `msg.sender` to the receiver
    /// and permits spending sender's Dai by the drips hub.
    /// This function is an extension of `give`, see its documentation for more details.
    ///
    /// The user must sign a Dai permission document allowing the drips hub to spend their funds.
    /// These parameters will be passed to the Dai contract by this function.
    /// @param permitArgs The Dai permission arguments.
    function giveAndPermit(
        address receiver,
        uint128 amt,
        PermitArgs calldata permitArgs
    ) public whenNotPaused {
        _permit(permitArgs);
        give(receiver, amt);
    }

    /// @notice Gives funds from the account of the `msg.sender` to the receiver
    /// and permits spending sender's Dai by the drips hub.
    /// This function is an extension of `give` see its documentation for more details.
    ///
    /// The user must sign a Dai permission document allowing the drips hub to spend their funds.
    /// These parameters will be passed to the Dai contract by this function.
    /// @param permitArgs The Dai permission arguments.
    function giveAndPermit(
        uint256 account,
        address receiver,
        uint128 amt,
        PermitArgs calldata permitArgs
    ) public whenNotPaused {
        _permit(permitArgs);
        give(account, receiver, amt);
    }

    /// @notice Permits the drips hub to spend the message sender's Dai.
    /// @param permitArgs The Dai permission arguments.
    function _permit(PermitArgs calldata permitArgs) internal {
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
