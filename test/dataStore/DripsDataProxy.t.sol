// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {DripsDataProxy, DripsDataStore} from "src/dataStore/DripsDataProxy.sol";
import {
    Drips, StreamConfigImpl, StreamReceiver, StreamsHistory, SplitsReceiver
} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";
import {
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract DripsDataProxyTest is Test {
    Drips internal drips;
    DripsDataStore internal dripsDataStore;
    DripsDataProxy internal dataProxy;
    IERC20 internal erc20;

    address internal driver = address(1);

    uint256 internal account = 1;
    uint256 internal receiver = 2;

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this))));
        drips.registerDriver(driver);

        dripsDataStore = new DripsDataStore();
        DripsDataProxy dataProxyLogic = new DripsDataProxy(drips, dripsDataStore);
        dataProxy = DripsDataProxy(address(new ManagedProxy(dataProxyLogic, address(2))));

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
    }

    function testSqueezeStreams() public {
        // Start streaming
        StreamReceiver[] memory streams = new StreamReceiver[](1);
        streams[0] = StreamReceiver(
            receiver, StreamConfigImpl.create(0, 1 * drips.AMT_PER_SEC_MULTIPLIER(), 0, 0)
        );
        erc20.transfer(address(drips), 2);
        vm.prank(driver);
        drips.setStreams(account, erc20, new StreamReceiver[](0), 2, streams, 0, 0);

        // Create history
        (,, uint32 updateTime,, uint32 maxEnd) = drips.streamsState(account, erc20);
        StreamsHistory[] memory history = new StreamsHistory[](1);
        history[0] = StreamsHistory(0, streams, updateTime, maxEnd);
        bytes32 historyHash = dripsDataStore.storeStreamsHistory(history);

        // Test squeezeStreamsResult
        skip(1);
        uint128 amt = dataProxy.squeezeStreamsResult(receiver, erc20, account, 0, historyHash);
        assertEq(amt, 1, "Invalid squeezable amt");

        // Squeeze
        amt = dataProxy.squeezeStreams(receiver, erc20, account, 0, historyHash);
        assertEq(amt, 1, "Invalid squeezed amt");
        assertEq(drips.splittable(receiver, erc20), 1, "Invalid splittable amt");
    }

    function testSplit() public {
        uint32 splitWeight = drips.TOTAL_SPLITS_WEIGHT() / 4;
        uint128 totalAmt = 8;
        uint128 splitAmt = 2;
        uint128 collectableAmt = 6;

        // Set splits
        SplitsReceiver[] memory splits = new SplitsReceiver[](1);
        splits[0] = SplitsReceiver(receiver, splitWeight);
        dripsDataStore.storeSplits(splits);
        vm.prank(driver);
        drips.setSplits(account, splits);

        // Test splitResult
        (uint128 actualCollectableAmt, uint128 actualSplitAmt) =
            dataProxy.splitResult(account, totalAmt);
        assertEq(actualCollectableAmt, collectableAmt, "Invalid results collectable amount");
        assertEq(actualSplitAmt, splitAmt, "Invalid results split amount");

        // Give funds
        erc20.transfer(address(drips), totalAmt);
        vm.prank(driver);
        drips.give(receiver, account, erc20, totalAmt);

        // Split
        (actualCollectableAmt, actualSplitAmt) = dataProxy.split(account, erc20);
        assertEq(actualCollectableAmt, collectableAmt, "Invalid collectable amount");
        assertEq(actualSplitAmt, splitAmt, "Invalid split amount");
        assertEq(drips.splittable(receiver, erc20), splitAmt, "Invalid actually split");
        assertEq(drips.collectable(account, erc20), collectableAmt, "Invalid actually collectable");
    }

    function testBalanceAt() public {
        StreamReceiver[] memory streams = new StreamReceiver[](1);
        streams[0] = StreamReceiver(
            receiver, StreamConfigImpl.create(0, 1 * drips.AMT_PER_SEC_MULTIPLIER(), 0, 0)
        );
        dripsDataStore.storeStreams(streams);
        erc20.transfer(address(drips), 2);
        vm.prank(driver);
        drips.setStreams(account, erc20, new StreamReceiver[](0), 2, streams, 0, 0);

        uint256 balanceAt = dataProxy.balanceAt(account, erc20, uint32(vm.getBlockTimestamp() + 1));
        assertEq(balanceAt, 1, "Invalid balance");
    }

    function notDelegatedReverts() internal returns (DripsDataProxy dataProxy_) {
        dataProxy_ = DripsDataProxy(dataProxy.implementation());
        vm.expectRevert("Function must be called through delegatecall");
    }

    function testSqueezeStreamsMustBeDelegated() public {
        notDelegatedReverts().squeezeStreams(account, erc20, account, 0, 0);
    }

    function testSplitMustBeDelegated() public {
        notDelegatedReverts().split(account, erc20);
    }
}
