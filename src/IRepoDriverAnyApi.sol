// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import "./IRepoDriver.sol";
import {ERC677ReceiverInterface} from "chainlink/interfaces/ERC677ReceiverInterface.sol";
import {LinkTokenInterface} from "chainlink/interfaces/LinkTokenInterface.sol";
import {OperatorInterface} from "chainlink/interfaces/OperatorInterface.sol";

/// @notice The extension of `IRepoDriver`, see its documentation for more details.
/// A Drips driver implementing repository-based account identification
/// using a Chainlink AnyApi oracle to verify the repository ownership.
/// Use `requestUpdateOwner` or Link token's `transferAndCall` to update the owner.
interface IRepoDriverAnyApi is IRepoDriver, ERC677ReceiverInterface {
    /// @notice Emitted when the AnyApi operator configuration is updated.
    /// @param operator The new address of the AnyApi operator.
    /// @param jobId The new AnyApi job ID used for requesting account owner updates.
    /// @param defaultFee The new fee in Link for each account owner
    /// update request when the driver is covering the cost.
    /// The fee must be high enough for the operator to accept the requests,
    /// refer to their documentation to see what's the minimum value.
    event AnyApiOperatorUpdated(
        OperatorInterface indexed operator, bytes32 indexed jobId, uint96 defaultFee
    );

    /// @notice The Link token used for paying the operators.
    /// @return linkToken_ The Link token address.
    function linkToken() external view returns (LinkTokenInterface linkToken_);

    /// @notice Gets the current AnyApi operator configuration.
    /// @return operator The address of the AnyApi operator.
    /// @return jobId The AnyApi job ID used for requesting account owner updates.
    /// @return defaultFee The fee in Link for each account owner
    /// update request when the driver is covering the cost.
    /// The fee must be high enough for the operator to accept the requests,
    /// refer to their documentation to see what's the minimum value.
    function anyApiOperator()
        external
        view
        returns (OperatorInterface operator, bytes32 jobId, uint96 defaultFee);

    /// @notice Requests an update of the ownership of the account representing the repository.
    /// The actual update of the owner will be made in a future transaction.
    /// The driver will cover the fee in Link that must be paid to the operator.
    /// If you want to cover the fee yourself, use `onTokenTransfer`.
    ///
    /// The repository must contain a `FUNDING.json` file in the project root in the default branch.
    /// The file must be a valid JSON with arbitrary data, but it must contain the owner address
    /// as a hexadecimal string under `drips` -> `<CHAIN NAME>` -> `ownedBy`, a minimal example:
    /// `{ "drips": { "ethereum": { "ownedBy": "0x0123456789abcDEF0123456789abCDef01234567" } } }`.
    /// If the operator can't read the owner when processing the update request,
    /// it ignores the request and no change to the account ownership is made.
    /// @param forge The forge where the repository is stored.
    /// @param name The name of the repository.
    /// For GitHub and GitLab it must follow the `user_name/repository_name` structure
    /// and it must be formatted identically as in the repository's URL,
    /// including the case of each letter and special characters being removed.
    /// @return accountId The ID of the account.
    function requestUpdateOwner(Forge forge, bytes calldata name)
        external
        returns (uint256 accountId);

    /// @notice The function called when receiving funds from ERC-677 `transferAndCall`.
    /// Only supports receiving Link tokens, callable only by the Link token smart contract.
    /// The only supported usage is requesting account ownership updates,
    /// the transferred tokens are then used for paying the AnyApi operator fee,
    /// see `requestUpdateOwner` for more details.
    /// The received tokens are never refunded, so make sure that
    /// the amount isn't too low to cover the fee, isn't too high and wasteful,
    /// and the repository's content is valid so its ownership can be verified.
    /// @param sender The sender of the tokens, ignored.
    /// @param amount The transferred amount, it will be used as the AnyApi operator fee.
    /// @param data The `transferAndCall` payload.
    /// It must be a valid ABI-encoded calldata for `requestUpdateOwner`.
    /// The call parameters will be used the same way as when calling `requestUpdateOwner`,
    /// to determine which account's ownership update is requested.
    function onTokenTransfer(address sender, uint256 amount, bytes calldata data)
        external
        override;
}
