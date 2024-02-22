// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice The helper library for using Drips.
// slither-disable-next-line unused-state
library DripsLib {
    /// @notice Maximum number of streams receivers of a single account.
    /// Limits cost of changes in streams configuration.
    uint256 internal constant MAX_STREAMS_RECEIVERS = 100;
    /// @notice The additional decimals for all amtPerSec values.
    uint8 internal constant AMT_PER_SEC_EXTRA_DECIMALS = 9;
    /// @notice The multiplier for all amtPerSec values.
    uint160 internal constant AMT_PER_SEC_MULTIPLIER = uint160(10) ** AMT_PER_SEC_EXTRA_DECIMALS;
    /// @notice Maximum number of splits receivers of a single account.
    /// Limits the cost of splitting.
    uint256 internal constant MAX_SPLITS_RECEIVERS = 200;
    /// @notice The total splits weight of an account
    uint256 internal constant TOTAL_SPLITS_WEIGHT = 1_000_000;
    /// @notice The offset of the controlling driver ID in the account ID.
    /// In other words the controlling driver ID is the highest 32 bits of the account ID.
    /// Every account ID is a 256-bit integer constructed by concatenating:
    /// `driverId (32 bits) | driverCustomData (224 bits)`.
    uint8 internal constant DRIVER_ID_OFFSET = 224;
    /// @notice The total amount the protocol can store of each token.
    uint256 internal constant MAX_TOTAL_BALANCE = type(uint128).max >> 1;

    /// @notice The minimum amtPerSec of a stream. It's 1 token per cycle.
    /// @param cycleSecs The `cycleSecs` value used by the Drips contract.
    /// @return amtPerSec The amount per second.
    function minAmtPerSec(uint32 cycleSecs) internal pure returns (uint160 amtPerSec) {
        return (AMT_PER_SEC_MULTIPLIER + cycleSecs - 1) / cycleSecs;
    }
}
