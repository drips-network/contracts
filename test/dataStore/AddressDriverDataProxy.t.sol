// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {AddressDriverDataProxy} from "src/dataStore/AddressDriverDataProxy.sol";
import {DripsDataStore} from "src/dataStore/DripsDataStore.sol";
import {AddressDriver} from "src/AddressDriver.sol";
import {Call, Caller} from "src/Caller.sol";
import {Drips} from "src/Drips.sol";
import {DripsLib, MaxEndHintsImpl, StreamConfigImpl} from "src/DripsLib.sol";
import {
    AccountMetadata,
    IDrips,
    IERC20,
    MaxEndHints,
    StreamReceiver,
    SplitsReceiver
} from "src/IDrips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20PresetFixedSupply} from
    "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract AddressDriverDataProxyTest is Test {
    IDrips internal drips;
    Caller internal caller;
    AddressDriver internal addressDriver;
    DripsDataStore internal dripsDataStore;
    AddressDriverDataProxy internal dataProxy;
    IERC20 internal erc20;

    uint256 internal thisId;
    address internal user = address(1);

    MaxEndHints internal immutable noHints = MaxEndHintsImpl.create();

    function setUp() public {
        drips = IDrips(address(new ManagedProxy(new Drips(10), address(this))));

        caller = new Caller();

        // Make AddressDriver's driver ID non-0 to test if it's respected by AddressDriver
        drips.registerDriver(address(1));
        drips.registerDriver(address(1));
        AddressDriver addressDriverLogic =
            new AddressDriver(drips, address(caller), drips.nextDriverId());
        addressDriver = AddressDriver(address(new ManagedProxy(addressDriverLogic, address(2))));
        drips.registerDriver(address(addressDriver));

        dripsDataStore = new DripsDataStore();

        AddressDriverDataProxy dataProxyLogic =
            new AddressDriverDataProxy(addressDriver, dripsDataStore, caller);
        dataProxy = AddressDriverDataProxy(address(new ManagedProxy(dataProxyLogic, address(2))));

        caller.authorize(address(dataProxy));

        thisId = addressDriver.calcAccountId(address(this));

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(addressDriver), type(uint256).max);
    }

    function testSetStreams() public {
        uint128 amt = 5;

        // Top-up
        StreamReceiver[] memory receivers = new StreamReceiver[](1);
        receivers[0] = StreamReceiver(
            123, StreamConfigImpl.create(0, DripsLib.minAmtPerSec(drips.cycleSecs()), 0, 0)
        );
        bytes32 hash = dripsDataStore.storeStreams(receivers);
        uint256 balance = erc20.balanceOf(address(this));

        int128 balanceDelta = dataProxy.setStreams(erc20, int128(amt), hash, noHints, address(this));

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance after top-up");
        (bytes32 streamsHash,,, uint128 streamsBalance,) = drips.streamsState(thisId, erc20);
        assertEq(streamsHash, hash, "Invalid streams hash after top-up");
        assertEq(streamsBalance, amt, "Invalid streams balance after top-up");
        assertEq(balanceDelta, int128(amt), "Invalid streams balance delta after top-up");

        // Withdraw
        balance = erc20.balanceOf(user);

        balanceDelta = dataProxy.setStreams(erc20, -int128(amt), 0, noHints, user);

        assertEq(erc20.balanceOf(user), balance + amt, "Invalid balance after withdrawal");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance after withdrawal");
        (streamsHash,,, streamsBalance,) = drips.streamsState(thisId, erc20);
        assertEq(streamsHash, 0, "Invalid streams hash after withdrawal");
        assertEq(streamsBalance, 0, "Invalid streams balance after withdrawal");
        assertEq(balanceDelta, -int128(amt), "Invalid streams balance delta after withdrawal");
    }

    function testSetStreamsTrustsForwarder() public {
        uint128 amt = 5;
        uint256 balance = erc20.balanceOf(address(this));
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(dataProxy),
            data: abi.encodeCall(dataProxy.setStreams, (erc20, int128(amt), 0, noHints, address(this))),
            value: 0
        });

        caller.callBatched(calls);

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance");
        (,,, uint128 streamsBalance,) = drips.streamsState(thisId, erc20);
        assertEq(streamsBalance, amt, "Invalid streams balance");
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(123, 1);
        bytes32 hash = dripsDataStore.storeSplits(receivers);

        dataProxy.setSplits(hash);

        assertEq(drips.splitsHash(thisId), hash, "Invalid splits hash");
    }

    function testSetSplitsTrustsForwarder() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(123, 1);
        bytes32 hash = dripsDataStore.storeSplits(receivers);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(dataProxy),
            data: abi.encodeCall(dataProxy.setSplits, hash),
            value: 0
        });

        caller.callBatched(calls);

        assertEq(drips.splitsHash(thisId), hash, "Invalid splits hash");
    }

    function testEmitAccountMetadata() public {
        AccountMetadata[] memory accountMetadata = new AccountMetadata[](1);
        accountMetadata[0] = AccountMetadata("key", "value");
        bytes32 hash = dripsDataStore.storeAccountMetadata(accountMetadata);
        dataProxy.emitAccountMetadata(hash);
    }

    function testEmitAccountMetadataTrustsForwarder() public {
        AccountMetadata[] memory accountMetadata = new AccountMetadata[](1);
        accountMetadata[0] = AccountMetadata("key", "value");
        bytes32 hash = dripsDataStore.storeAccountMetadata(accountMetadata);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(dataProxy),
            data: abi.encodeCall(dataProxy.emitAccountMetadata, hash),
            value: 0
        });
        caller.callBatched(calls);
    }

    function notDelegatedReverts() internal returns (AddressDriverDataProxy dataProxy_) {
        dataProxy_ = AddressDriverDataProxy(dataProxy.implementation());
        vm.expectRevert("Function must be called through delegatecall");
    }

    function testSetStreamsMustBeDelegated() public {
        notDelegatedReverts().setStreams(erc20, 0, 0, noHints, user);
    }

    function testSetSplitsMustBeDelegated() public {
        notDelegatedReverts().setSplits(0);
    }

    function testEmitAccountMetadataMustBeDelegated() public {
        notDelegatedReverts().emitAccountMetadata(0);
    }
}
