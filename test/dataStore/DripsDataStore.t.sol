// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {
    AccountMetadata,
    DripsDataStore,
    SplitsReceiver,
    StreamsHistory,
    StreamReceiver
} from "src/dataStore/DripsDataStore.sol";
import {Drips, StreamConfig} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";

contract DripsDataStoreTest is Test {
    DripsDataStore internal dripsDataStore;
    Drips internal drips;
    address internal admin = address(1);

    function setUp() public {
        dripsDataStore = new DripsDataStore();
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, admin)));
    }

    function hashUint(uint256 input) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(input)));
    }

    function storeStreams(StreamReceiver[] memory streams, bool expectStored) public {
        bytes32 hash = drips.hashStreams(streams);
        assertEq(
            dripsDataStore.isStreamsStored(hash), expectStored, "Invalid streams storage state"
        );
        assertEq(dripsDataStore.storeStreams(streams), hash, "Invalid stored streams hash");
        assertTrue(dripsDataStore.isStreamsStored(hash), "Streams not stored");
        StreamReceiver[] memory stored = dripsDataStore.loadStreams(hash);
        assertEq(abi.encode(streams), abi.encode(stored), "Invalid loaded streams");
    }

    function generateStreams(uint256 length)
        public
        pure
        returns (StreamReceiver[] memory receivers)
    {
        uint256 salt = hashUint(length);
        receivers = new StreamReceiver[](length);
        for (uint256 i = 0; i < length; i++) {
            receivers[i] = StreamReceiver({
                accountId: hashUint(salt),
                config: StreamConfig.wrap(hashUint(salt + 1))
            });
            salt = hashUint(salt);
        }
    }

    function storeSplits(SplitsReceiver[] memory splits, bool expectStored) public {
        bytes32 hash = drips.hashSplits(splits);
        assertEq(dripsDataStore.isSplitsStored(hash), expectStored, "Invalid splits storage state");
        assertEq(dripsDataStore.storeSplits(splits), hash, "Invalid stored splits hash");
        assertTrue(dripsDataStore.isSplitsStored(hash), "Splits not stored");
        SplitsReceiver[] memory stored = dripsDataStore.loadSplits(hash);
        assertEq(abi.encode(splits), abi.encode(stored), "Invalid loaded splits");
    }

    function generateSplits(uint256 length) public pure returns (SplitsReceiver[] memory splits) {
        uint256 salt = hashUint(length);
        splits = new SplitsReceiver[](length);
        for (uint256 i = 0; i < length; i++) {
            splits[i] =
                SplitsReceiver({accountId: hashUint(salt), weight: uint32(hashUint(salt + 1))});
            salt = hashUint(salt);
        }
    }

    function storeAccountMetadata(AccountMetadata[] memory metadata, bool expectStored) public {
        bytes32 hash = 0;
        if (metadata.length != 0) hash = keccak256(abi.encode(metadata));
        assertEq(
            dripsDataStore.isAccountMetadataStored(hash),
            expectStored,
            "Invalid metadata storage state"
        );
        assertEq(
            dripsDataStore.storeAccountMetadata(metadata), hash, "Invalid stored metadata hash"
        );
        assertTrue(dripsDataStore.isAccountMetadataStored(hash), "Metadata not stored");
        AccountMetadata[] memory stored = dripsDataStore.loadAccountMetadata(hash);
        assertEq(abi.encode(metadata), abi.encode(stored), "Invalid loaded metadata");
    }

    function generateAccountMetadata(uint256 length)
        public
        pure
        returns (AccountMetadata[] memory metadata)
    {
        uint256 salt = hashUint(length);
        metadata = new AccountMetadata[](length);
        for (uint256 i = 0; i < length; i++) {
            metadata[i] = AccountMetadata({
                key: bytes32(hashUint(salt)),
                value: new bytes(hashUint(salt + 1) % 321)
            });
            bytes memory value = metadata[i].value;
            for (uint256 j = 0; j < value.length; j++) {
                value[j] = bytes1(uint8(hashUint(salt + 2 + j)));
            }
            salt = hashUint(salt);
        }
    }

    function storeStreamsHistory(StreamsHistory[] memory streamsHistory, bool expectStored)
        public
    {
        bytes32 hash = 0;
        if (streamsHistory.length != 0) hash = keccak256(abi.encode(streamsHistory));
        assertEq(
            dripsDataStore.isStreamsHistoryStored(hash),
            expectStored,
            "Invalid streams storage state"
        );
        assertEq(
            dripsDataStore.storeStreamsHistory(streamsHistory), hash, "Invalid stored streams hash"
        );
        assertTrue(dripsDataStore.isStreamsHistoryStored(hash), "Streams not stored");
        StreamsHistory[] memory stored = dripsDataStore.loadStreamsHistory(hash);
        assertEq(abi.encode(streamsHistory), abi.encode(stored), "Invalid loaded streams history");
    }

    function generateStreamsHistory(uint256 length)
        public
        view
        returns (StreamsHistory[] memory streamsHistory)
    {
        uint256 salt = hashUint(length);
        streamsHistory = new StreamsHistory[](length);
        for (uint256 i = 0; i < length; i++) {
            streamsHistory[i] = StreamsHistory({
                streamsHash: 0,
                receivers: new StreamReceiver[](0),
                updateTime: uint32(hashUint(salt)),
                maxEnd: uint32(hashUint(salt + 1))
            });
            if (hashUint(salt + 2) % 2 == 0) {
                streamsHistory[i].streamsHash = bytes32(hashUint(salt + 3));
            } else {
                uint256 receiversLength = hashUint(salt + 3) % (drips.MAX_STREAMS_RECEIVERS() + 1);
                streamsHistory[i].receivers = new StreamReceiver[](receiversLength);
                for (uint256 j = 0; j < receiversLength; j++) {
                    streamsHistory[i].receivers[j] = StreamReceiver({
                        accountId: hashUint(salt + 4 + j * 2),
                        config: StreamConfig.wrap(hashUint(salt + 5 + j * 2))
                    });
                }
            }
            salt = hashUint(salt);
        }
    }

    function testStoringEmptyStreamsDoesNothing() public {
        storeStreams(generateStreams(0), true);
    }

    function testStore2Streams() public {
        storeStreams(generateStreams(2), false);
    }

    function testStore100Streams() public {
        storeStreams(generateStreams(100), false);
    }

    function testStoringStreamsTwiceDoesNothing() public {
        StreamReceiver[] memory streams = generateStreams(2);
        storeStreams(streams, false);
        storeStreams(streams, true);
    }

    function testLoadingUnstoredStreamsReverts() public {
        vm.expectRevert("Requested data not in storage");
        dripsDataStore.loadStreams(hex"01");
    }

    function testLoadingUnstoredEmptyStreamsSucceeds() public {
        assertEq(dripsDataStore.loadStreams(0).length, 0, "Invalid loaded streams");
    }

    function testStoringEmptySplitsDoesNothing() public {
        storeSplits(generateSplits(0), true);
    }

    function testStore2Splits() public {
        storeSplits(generateSplits(2), false);
    }

    function testStore200Splits() public {
        storeSplits(generateSplits(200), false);
    }

    function testStoringSplitsTwiceDoesNothing() public {
        SplitsReceiver[] memory splits = generateSplits(2);
        storeSplits(splits, false);
        storeSplits(splits, true);
    }

    function testLoadingUnstoredSplitsReverts() public {
        vm.expectRevert("Requested data not in storage");
        dripsDataStore.loadSplits(hex"01");
    }

    function testLoadingUnstoredEmptySplitsSucceeds() public {
        assertEq(dripsDataStore.loadSplits(0).length, 0, "Invalid loaded splits");
    }

    function testStoringEmptyAccountMetadataDoesNothing() public {
        storeAccountMetadata(generateAccountMetadata(0), true);
    }

    function testStore2AccountMetadata() public {
        storeAccountMetadata(generateAccountMetadata(2), false);
    }

    function testStore100AccountMetadata() public {
        storeAccountMetadata(generateAccountMetadata(100), false);
    }

    function testStoringAccountMetadataTwiceDoesNothing() public {
        AccountMetadata[] memory metadata = generateAccountMetadata(2);
        storeAccountMetadata(metadata, false);
        storeAccountMetadata(metadata, true);
    }

    function testLoadingUnstoredAccountMetadataReverts() public {
        vm.expectRevert("Requested data not in storage");
        dripsDataStore.loadAccountMetadata(hex"01");
    }

    function testLoadingUnstoredEmptyAccountMetadataSucceeds() public {
        assertEq(dripsDataStore.loadAccountMetadata(0).length, 0, "Invalid loaded metadata");
    }

    function testStoringEmptyStreamsHistoryDoesNothing() public {
        storeStreamsHistory(generateStreamsHistory(0), true);
    }

    function testStore2EntryStreamsHistory() public {
        storeStreamsHistory(generateStreamsHistory(2), false);
    }

    function testStore10EntryStreamsHistory() public {
        storeStreamsHistory(generateStreamsHistory(10), false);
    }

    function testStoringStreamsHistoryTwiceDoesNothing() public {
        StreamsHistory[] memory streamsHistory = generateStreamsHistory(2);
        storeStreamsHistory(streamsHistory, false);
        storeStreamsHistory(streamsHistory, true);
    }

    function testLoadingUnstoredStreamsHistoryReverts() public {
        vm.expectRevert("Requested data not in storage");
        dripsDataStore.loadStreamsHistory(hex"01");
    }

    function testLoadingUnstoredEmptyStreamsHistorySucceeds() public {
        assertEq(dripsDataStore.loadStreamsHistory(0).length, 0, "Invalid loaded streams history");
    }

    function testBenchStoreStreams() public {
        benchStoreStreams(1);
        benchStoreStreams(10);
        benchStoreStreams(100);
    }

    function benchStoreStreams(uint256 count) public {
        emit log_named_uint("Streams count", count);
        StreamReceiver[] memory streams = generateStreams(count);
        emit log_named_uint("Encoded size", abi.encode(streams).length);
        uint256 gas = gasleft();
        bytes32 hash = dripsDataStore.storeStreams(streams);
        emit log_named_uint("Gas store", gas - gasleft());
        gas = gasleft();
        dripsDataStore.loadStreams(hash);
        emit log_named_uint("Gas load", gas - gasleft());
        emit log_string("-------------------");
    }

    function testBenchStoreSplits() public {
        benchStoreSplits(1);
        benchStoreSplits(10);
        benchStoreSplits(100);
        benchStoreSplits(200);
    }

    function benchStoreSplits(uint256 length) public {
        emit log_named_uint("Splits length", length);
        SplitsReceiver[] memory splits = generateSplits(length);
        emit log_named_uint("Encoded size", abi.encode(splits).length);
        uint256 gas = gasleft();
        bytes32 hash = dripsDataStore.storeSplits(splits);
        emit log_named_uint("Gas store", gas - gasleft());
        gas = gasleft();
        dripsDataStore.loadSplits(hash);
        emit log_named_uint("Gas load", gas - gasleft());
        emit log_string("-------------------");
    }

    function testBenchStoreAccountMetadata() public {
        benchStoreAccountMetadata(1);
        benchStoreAccountMetadata(10);
        benchStoreAccountMetadata(100);
    }

    function benchStoreAccountMetadata(uint256 length) public {
        emit log_named_uint("AccountMetadata length", length);
        AccountMetadata[] memory metadata = generateAccountMetadata(length);
        emit log_named_uint("Encoded size", abi.encode(metadata).length);
        uint256 gas = gasleft();
        bytes32 hash = dripsDataStore.storeAccountMetadata(metadata);
        emit log_named_uint("Gas store", gas - gasleft());
        gas = gasleft();
        dripsDataStore.loadAccountMetadata(hash);
        emit log_named_uint("Gas load", gas - gasleft());
        emit log_string("-------------------");
    }

    function testBenchStoreStreamsHistory() public {
        benchStoreStreamsHistory(1);
        benchStoreStreamsHistory(10);
    }

    function benchStoreStreamsHistory(uint256 length) public {
        emit log_named_uint("StreamsHistory length", length);
        StreamsHistory[] memory streamsHistory = generateStreamsHistory(length);
        emit log_named_uint("Encoded size", abi.encode(streamsHistory).length);
        uint256 gas = gasleft();
        bytes32 hash = dripsDataStore.storeStreamsHistory(streamsHistory);
        emit log_named_uint("Gas store", gas - gasleft());
        gas = gasleft();
        dripsDataStore.loadStreamsHistory(hash);
        emit log_named_uint("Gas load", gas - gasleft());
        emit log_string("-------------------");
    }
}
