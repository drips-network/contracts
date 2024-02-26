// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {AccountMetadata, SplitsReceiver, StreamsHistory, StreamReceiver} from "../IDrips.sol";

/// @notice `DripsDataStore` is a helper contract allowing storing large `Drips` data structures
/// on-chain, that would normally be kept off-chain, in events or in calldata.
/// It can store lists of streams receivers, splits receivers and account metadata.
/// Anybody can store lists, and once stored, a list can be loaded any number of times, by anybody.
///
/// `DripsDataStore` uses the SSTORE2 pattern, and it's cheaper than using the contract storage.
/// For example storing a list of 100 streams receivers costs 1.4M gas, and loading about 32K.
contract DripsDataStore {
    /// @notice The hash representing an empty list.
    bytes32 public constant EMPTY_HASH = 0;

    /// @notice The streams receiver lists storage contract addresses.
    mapping(bytes32 hash => address pointer) internal _streamsPointers;
    /// @notice The splits receiver lists storage contract addresses.
    mapping(bytes32 hash => address pointer) internal _splitsPointers;
    /// @notice The account metadata lists storage contract addresses.
    mapping(bytes32 hash => address pointer) internal _accountMetadataPointers;
    /// @notice The streams history entries lists storage contract addresses.
    mapping(bytes32 hash => address pointer) internal _streamsHistoryPointers;

    /// @notice Emitted when a new streams receiver list is stored.
    /// @param hash The hash of the stored streams.
    event StreamsStored(bytes32 indexed hash);
    /// @notice Emitted when a new splits receiver list is stored.
    /// @param hash The hash of the stored splits.
    event SplitsStored(bytes32 indexed hash);
    /// @notice Emitted when a new account metadata list is stored.
    /// @param hash The hash of the stored account metadata.
    event AccountMetadataStored(bytes32 indexed hash);
    /// @notice Emitted when a new streams history entries list is stored.
    /// @param hash The hash of the stored streams.
    event StreamsHistoryStored(bytes32 indexed hash);

    /// @notice Store a list of streams receivers.
    /// Storing an already stored list is valid, and it doesn't do anything.
    /// @param streams The streams receivers list to store.
    /// @return hash The hash of the stored list, that can be used to load it.
    /// If `streams` is empty, it's `EMPTY_HASH`, which is `0`.
    /// It's always equal to the streams hash in `Drips` of the stored list.
    function storeStreams(StreamReceiver[] calldata streams) external returns (bytes32 hash) {
        if (streams.length == 0) return EMPTY_HASH;
        bytes memory data = abi.encode(streams);
        hash = keccak256(data);
        if (_streamsPointers[hash] == address(0)) {
            _streamsPointers[hash] = _store(data);
            emit StreamsStored(hash);
        }
    }

    /// @notice Checks if the list of streams receivers is stored.
    /// @param hash The hash of the list, see `storeStreams`.
    /// @return isStored True if the list of streams receivers is stored.
    /// If `hash` is `EMPTY_HASH`, which is `0`, always returns true.
    function isStreamsStored(bytes32 hash) public view returns (bool isStored) {
        if (hash == EMPTY_HASH) return true;
        return _streamsPointers[hash] != address(0);
    }

    /// @notice Loads the list of streams receivers.
    /// Reverts if the list with the given hash isn't stored, see `isStreamsStored`.
    /// @param hash The hash of the list, see `storeStreams`.
    /// @return streams The loaded list of streams receivers.
    function loadStreams(bytes32 hash) external view returns (StreamReceiver[] memory streams) {
        if (hash == EMPTY_HASH) return streams;
        _loadAndReturn(_streamsPointers[hash]);
    }

    /// @notice Store a list of splits receivers.
    /// Storing an already stored list is valid, and it doesn't do anything.
    /// @param splits The splits receivers list to store.
    /// @return hash The hash of the stored list, that can be used to load it.
    /// If `splits` is empty, it's `EMPTY_HASH`, which is `0`.
    /// It's always equal to the splits hash in `Drips` of the stored list.
    function storeSplits(SplitsReceiver[] calldata splits) external returns (bytes32 hash) {
        if (splits.length == 0) return EMPTY_HASH;
        bytes memory data = abi.encode(splits);
        hash = keccak256(data);
        if (_splitsPointers[hash] == address(0)) {
            _splitsPointers[hash] = _store(data);
            emit SplitsStored(hash);
        }
    }

    /// @notice Checks if the list of splits receivers is stored.
    /// @param hash The hash of the list, see `storeSplits`.
    /// @return isStored True if the list of splits receivers is stored.
    /// If `hash` is `EMPTY_HASH`, which is `0`, always returns true.
    function isSplitsStored(bytes32 hash) public view returns (bool isStored) {
        if (hash == EMPTY_HASH) return true;
        return _splitsPointers[hash] != address(0);
    }

    /// @notice Loads the list of splits receivers.
    /// Reverts if the list with the given hash isn't stored, see `isSplitsStored`.
    /// @param hash The hash of the list, see `storeSplits`.
    /// @return splits The loaded list of splits receivers.
    function loadSplits(bytes32 hash) external view returns (SplitsReceiver[] memory splits) {
        if (hash == EMPTY_HASH) return splits;
        _loadAndReturn(_splitsPointers[hash]);
    }

    /// @notice Store a list of account metadata.
    /// Storing an already stored list is valid, and it doesn't do anything.
    /// @param accountMetadata The account metadata list to store.
    /// @return hash The hash of the stored list, that can be used to load it.
    /// If `splits` is empty, it's `EMPTY_HASH`, which is `0`.
    function storeAccountMetadata(AccountMetadata[] calldata accountMetadata)
        external
        returns (bytes32 hash)
    {
        if (accountMetadata.length == 0) return EMPTY_HASH;
        bytes memory data = abi.encode(accountMetadata);
        hash = keccak256(data);
        if (_accountMetadataPointers[hash] == address(0)) {
            _accountMetadataPointers[hash] = _store(data);
            emit AccountMetadataStored(hash);
        }
    }

    /// @notice Checks if the list of account metadata is stored.
    /// @param hash The hash of the list, see `storeSplits`.
    /// @return isStored True if the list of account metadata is stored.
    /// If `hash` is `EMPTY_HASH`, which is `0`, always returns true.
    function isAccountMetadataStored(bytes32 hash) public view returns (bool isStored) {
        if (hash == EMPTY_HASH) return true;
        return _accountMetadataPointers[hash] != address(0);
    }

    /// @notice Loads the list of account metadata.
    /// Reverts if the list with the given hash isn't stored, see `isSplitsStored`.
    /// @param hash The hash of the list, see `storeSplits`.
    /// @return accountMetadata The loaded list of account metadata.
    function loadAccountMetadata(bytes32 hash)
        external
        view
        returns (AccountMetadata[] memory accountMetadata)
    {
        if (hash == EMPTY_HASH) return accountMetadata;
        _loadAndReturn(_accountMetadataPointers[hash]);
    }

    /// @notice Store a list of streams history entries.
    /// Storing an already stored list is valid, and it doesn't do anything.
    /// @param streamsHistory The streams history entries list to store.
    /// @return hash The hash of the stored list, that can be used to load it.
    /// If `splits` is empty, it's `EMPTY_HASH`, which is `0`.
    function storeStreamsHistory(StreamsHistory[] calldata streamsHistory)
        external
        returns (bytes32 hash)
    {
        if (streamsHistory.length == 0) return EMPTY_HASH;
        bytes memory data = abi.encode(streamsHistory);
        hash = keccak256(data);
        if (_streamsHistoryPointers[hash] == address(0)) {
            _streamsHistoryPointers[hash] = _store(data);
            emit StreamsHistoryStored(hash);
        }
    }

    /// @notice Checks if the list of streams history entries is stored.
    /// @param hash The hash of the list, see `storeSplits`.
    /// @return isStored True if the list of streams history entries is stored.
    /// If `hash` is `EMPTY_HASH`, which is `0`, always returns true.
    function isStreamsHistoryStored(bytes32 hash) public view returns (bool isStored) {
        if (hash == EMPTY_HASH) return true;
        return _streamsHistoryPointers[hash] != address(0);
    }

    /// @notice Loads the list of streams history entries.
    /// Reverts if the list with the given hash isn't stored, see `isSplitsStored`.
    /// @param hash The hash of the list, see `storeSplits`.
    /// @return streamsHistory The loaded list of streams history entries.
    function loadStreamsHistory(bytes32 hash)
        external
        view
        returns (StreamsHistory[] memory streamsHistory)
    {
        if (hash == EMPTY_HASH) return streamsHistory;
        _loadAndReturn(_streamsHistoryPointers[hash]);
    }

    /// @notice Stores data as a contract bytecode.
    /// @return pointer The newly deployed contract with the calldata stored in its bytecode.
    function _store(bytes memory data) internal returns (address pointer) {
        bytes memory creationCode = bytes.concat(
            // Returns its own creation code as the deployed bytecode except for the first 11 bytes.
            // Modified from https://github.com/transmissions11/solmate.
            //---------------------------------------------------------------------------------//
            // Opcode  | Opcode + Arguments  | Description  | Stack View                       //
            //---------------------------------------------------------------------------------//
            // 0x60    |  0x600B             | PUSH1 11     | dataOffset                       //
            // 0x59    |  0x59               | MSIZE        | 0 dataOffset                     //
            // 0x81    |  0x81               | DUP2         | dataOffset 0 dataOffset          //
            // 0x38    |  0x38               | CODESIZE     | codeSize dataOffset 0 dataOffset //
            // 0x03    |  0x03               | SUB          | dataSize 0 dataOffset            //
            // 0x80    |  0x80               | DUP          | dataSize dataSize 0 dataOffset   //
            // 0x92    |  0x92               | SWAP3        | dataOffset dataSize 0 dataSize   //
            // 0x59    |  0x59               | MSIZE        | 0 dataOffset dataSize 0 dataSize //
            // 0x39    |  0x39               | CODECOPY     | 0 dataSize                       //
            // 0xF3    |  0xF3               | RETURN       |                                  //
            //---------------------------------------------------------------------------------//
            hex"600B5981380380925939F3",
            hex"00", // Prefix the data with the STOP opcode to ensure that it can't be called.
            data
        );
        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            pointer := create(0, add(creationCode, 32), mload(creationCode))
        }
        require(pointer != address(0), "Storing data failed");
    }

    /// @notice Loads the stored data and returns it.
    /// This function never returns, it stops the execution in the current context,
    /// and the loaded data is returned as the external function's return data.
    /// There is no validation, so the loaded data must be ABI-encoded and must
    /// match exactly the returned data type of an external function that calls this function.
    /// E.g. if a pointer stores ABI-encoded `uint[]`, ONLY an external function
    /// returning `uint[]` can call `_loadAndReturn` for that pointer.
    /// This is cheaper than loading data, ABI-decoding it, and then re-ABI-encoding to return it.
    /// @param pointer The contract to load data from, see `_storeCalldata`. Reverts if `0`.
    function _loadAndReturn(address pointer) internal view {
        require(pointer != address(0), "Requested data not in storage");
        bytes memory data = pointer.code;
        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            // Skip the first byte, it's the STOP opcode prefix.
            return(add(data, 33), sub(mload(data), 1))
        }
    }
}
