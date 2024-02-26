// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice A stream receiver
struct StreamReceiver {
    /// @notice The account ID.
    uint256 accountId;
    /// @notice The stream configuration.
    StreamConfig config;
}

/// @notice The sender streams history entry, used when squeezing streams.
struct StreamsHistory {
    /// @notice Streams receivers list hash, see `_hashStreams`.
    /// If it's non-zero, `receivers` must be empty.
    bytes32 streamsHash;
    /// @notice The streams receivers. If it's non-empty, `streamsHash` must be `0`.
    /// If it's empty, this history entry will be skipped when squeezing streams
    /// and `streamsHash` will be used when verifying the streams history validity.
    /// Skipping a history entry allows cutting gas usage on analysis
    /// of parts of the streams history which are not worth squeezing.
    /// The hash of an empty receivers list is `0`, so when the sender updates
    /// their receivers list to be empty, the new `StreamsHistory` entry will have
    /// both the `streamsHash` equal to `0` and the `receivers` empty making it always skipped.
    /// This is fine, because there can't be any funds to squeeze from that entry anyway.
    StreamReceiver[] receivers;
    /// @notice The time when streams have been configured
    uint32 updateTime;
    /// @notice The maximum end time of streaming.
    uint32 maxEnd;
}

/// @notice A splits receiver
struct SplitsReceiver {
    /// @notice The account ID.
    uint256 accountId;
    /// @notice The splits weight. Must never be zero.
    /// The account will be getting `weight / DripsLib.TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the splitting account.
    uint256 weight;
}

/// @notice The account metadata.
/// The key and the value are not standardized by the protocol, it's up to the users
/// to establish and follow conventions to ensure compatibility with the consumers.
struct AccountMetadata {
    /// @param key The metadata key
    bytes32 key;
    /// @param value The metadata value
    bytes value;
}

/// @notice Describes a streams configuration.
/// It's a 256-bit integer constructed by concatenating the configuration parameters:
/// `streamId (32 bits) | amtPerSec (160 bits) | start (32 bits) | duration (32 bits)`.
/// `streamId` is an arbitrary number used to identify a stream.
/// It's a part of the configuration but the protocol doesn't use it.
/// `amtPerSec` is the amount per second being streamed. Must never be zero.
/// It must have additional `DripsLib.AMT_PER_SEC_EXTRA_DECIMALS` decimals and can have fractions.
/// To achieve that its value must be multiplied by `DripsLib.AMT_PER_SEC_MULTIPLIER`.
/// `start` is the timestamp when streaming should start.
/// If zero, use the timestamp when the stream is configured.
/// `duration` is the duration of streaming.
/// If zero, stream until balance runs out.
type StreamConfig is uint256;

using StreamConfigImpl for StreamConfig global;

library StreamConfigImpl {
    /// @notice Create a new StreamConfig.
    /// @param streamId_ An arbitrary number used to identify a stream.
    /// It's a part of the configuration but the protocol doesn't use it.
    /// @param amtPerSec_ The amount per second being streamed. Must never be zero.
    /// It must have additional `DripsLib.AMT_PER_SEC_EXTRA_DECIMALS`
    /// decimals and can have fractions.
    /// To achieve that the passed value must be multiplied by `DripsLib.AMT_PER_SEC_MULTIPLIER`.
    /// @param start_ The timestamp when streaming should start.
    /// If zero, use the timestamp when the stream is configured.
    /// @param duration_ The duration of streaming. If zero, stream until the balance runs out.
    // slither-disable-next-line dead-code
    function create(uint32 streamId_, uint160 amtPerSec_, uint32 start_, uint32 duration_)
        internal
        pure
        returns (StreamConfig)
    {
        // By assignment we get `config` value:
        // `zeros (224 bits) | streamId (32 bits)`
        uint256 config = streamId_;
        // By bit shifting we get `config` value:
        // `zeros (64 bits) | streamId (32 bits) | zeros (160 bits)`
        // By bit masking we get `config` value:
        // `zeros (64 bits) | streamId (32 bits) | amtPerSec (160 bits)`
        config = (config << 160) | amtPerSec_;
        // By bit shifting we get `config` value:
        // `zeros (32 bits) | streamId (32 bits) | amtPerSec (160 bits) | zeros (32 bits)`
        // By bit masking we get `config` value:
        // `zeros (32 bits) | streamId (32 bits) | amtPerSec (160 bits) | start (32 bits)`
        config = (config << 32) | start_;
        // By bit shifting we get `config` value:
        // `streamId (32 bits) | amtPerSec (160 bits) | start (32 bits) | zeros (32 bits)`
        // By bit masking we get `config` value:
        // `streamId (32 bits) | amtPerSec (160 bits) | start (32 bits) | duration (32 bits)`
        config = (config << 32) | duration_;
        return StreamConfig.wrap(config);
    }

    /// @notice Extracts streamId from a `StreamConfig`
    // slither-disable-next-line dead-code
    function streamId(StreamConfig config) internal pure returns (uint32) {
        // `config` has value:
        // `streamId (32 bits) | amtPerSec (160 bits) | start (32 bits) | duration (32 bits)`
        // By bit shifting we get value:
        // `zeros (224 bits) | streamId (32 bits)`
        // By casting down we get value:
        // `streamId (32 bits)`
        return uint32(StreamConfig.unwrap(config) >> 224);
    }

    /// @notice Extracts amtPerSec from a `StreamConfig`
    function amtPerSec(StreamConfig config) internal pure returns (uint160) {
        // `config` has value:
        // `streamId (32 bits) | amtPerSec (160 bits) | start (32 bits) | duration (32 bits)`
        // By bit shifting we get value:
        // `zeros (64 bits) | streamId (32 bits) | amtPerSec (160 bits)`
        // By casting down we get value:
        // `amtPerSec (160 bits)`
        return uint160(StreamConfig.unwrap(config) >> 64);
    }

    /// @notice Extracts start from a `StreamConfig`
    function start(StreamConfig config) internal pure returns (uint32) {
        // `config` has value:
        // `streamId (32 bits) | amtPerSec (160 bits) | start (32 bits) | duration (32 bits)`
        // By bit shifting we get value:
        // `zeros (32 bits) | streamId (32 bits) | amtPerSec (160 bits) | start (32 bits)`
        // By casting down we get value:
        // `start (32 bits)`
        return uint32(StreamConfig.unwrap(config) >> 32);
    }

    /// @notice Extracts duration from a `StreamConfig`
    function duration(StreamConfig config) internal pure returns (uint32) {
        // `config` has value:
        // `streamId (32 bits) | amtPerSec (160 bits) | start (32 bits) | duration (32 bits)`
        // By casting down we get value:
        // `duration (32 bits)`
        return uint32(StreamConfig.unwrap(config));
    }

    /// @notice Compares two `StreamConfig`s.
    /// First compares `streamId`s, then `amtPerSec`s, then `start`s and finally `duration`s.
    /// @return isLower True if `config` is strictly lower than `otherConfig`.
    function lt(StreamConfig config, StreamConfig otherConfig)
        internal
        pure
        returns (bool isLower)
    {
        // Both configs have value:
        // `streamId (32 bits) | amtPerSec (160 bits) | start (32 bits) | duration (32 bits)`
        // Comparing them as integers is equivalent to comparing their fields from left to right.
        return StreamConfig.unwrap(config) < StreamConfig.unwrap(otherConfig);
    }
}

/// @notice The list of 8 hints for max end time calculation.
/// They are constructed as a concatenation of 8 32-bit values:
/// `the leftmost hint (32 bits) | ... | the rightmost hint (32 bits)
type MaxEndHints is uint256;

using MaxEndHintsImpl for MaxEndHints global;

library MaxEndHintsImpl {
    /// @notice Create a list of 8 zero value hints.
    /// @return hints The list of hints.
    // slither-disable-next-line dead-code
    function create() internal pure returns (MaxEndHints hints) {
        return MaxEndHints.wrap(0);
    }

    /// @notice Add a hint to the list of hints as the rightmost and remove the leftmost.
    /// @param hints The list of hints.
    /// @param hint The added hint.
    /// @return newHints The modified list of hints.
    // slither-disable-next-line dead-code
    function push(MaxEndHints hints, uint32 hint) internal pure returns (MaxEndHints newHints) {
        // `hints` has value:
        // `leftmost hint (32 bits) | other hints (224 bits)`
        // By bit shifting we get value:
        // `other hints (224 bits) | zeros (32 bits)`
        // By bit masking we get value:
        // `other hints (224 bits) | rightmost hint (32 bits)`
        return MaxEndHints.wrap((MaxEndHints.unwrap(hints) << 32) | hint);
    }

    /// @notice Remove and return the rightmost hint, and add the zero value hint as the leftmost.
    /// @param hints The list of hints.
    /// @return newHints The modified list of hints.
    /// @return hint The removed hint.
    function pop(MaxEndHints hints) internal pure returns (MaxEndHints newHints, uint32 hint) {
        // `hints` has value:
        // `other hints (224 bits) | rightmost hint (32 bits)`
        // By bit shifting we get value:
        // `zeros (32 bits) | other hints (224 bits)`
        // By casting down we get value:
        // `rightmost hint (32 bits)`
        return
            (MaxEndHints.wrap(MaxEndHints.unwrap(hints) >> 32), uint32(MaxEndHints.unwrap(hints)));
    }

    /// @notice Check if the list contains any non-zero value hints.
    /// @param hints The list of hints.
    /// @return hasHints_ True if the list contains any non-zero value hints.
    function hasHints(MaxEndHints hints) internal pure returns (bool hasHints_) {
        return MaxEndHints.unwrap(hints) != 0;
    }
}

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
