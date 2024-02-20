// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {
    DripsDataStore, RepoDriver, RepoDriverDataProxy
} from "src/dataStore/RepoDriverDataProxy.sol";
import {Call, Caller} from "src/Caller.sol";
import {
    AccountMetadata,
    MaxEndHints,
    MaxEndHintsImpl,
    StreamConfigImpl,
    Drips,
    StreamReceiver,
    SplitsReceiver
} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Forge} from "src/RepoDriver.sol";
import {OperatorInterface} from "chainlink/interfaces/OperatorInterface.sol";
import {Test} from "forge-std/Test.sol";
import {
    ERC20,
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract TestLinkToken is ERC20("", "") {
    function transferAndCall(address, uint256, bytes calldata) external pure returns (bool) {
        return true;
    }
}

contract RepoDriverDataProxyTest is Test {
    Drips internal drips;
    Caller internal caller;
    RepoDriver internal driver;
    DripsDataStore internal dripsDataStore;
    RepoDriverDataProxy internal dataProxy;
    IERC20 internal erc20;

    address internal user = address(1);
    uint256 internal accountId;

    MaxEndHints internal immutable noHints = MaxEndHintsImpl.create();

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this))));

        caller = new Caller();

        // Make RepoDriver's driver ID non-0 to test if it's respected by RepoDriver
        drips.registerDriver(address(1));
        drips.registerDriver(address(1));
        RepoDriver driverLogic = new RepoDriver(drips, address(caller), drips.nextDriverId());
        driver = RepoDriver(address(new ManagedProxy(driverLogic, address(2))));
        drips.registerDriver(address(driver));
        address operator = address(1234);
        driver.initializeAnyApiOperator(OperatorInterface(operator), keccak256("job ID"), 0);
        vm.etch(address(driver.linkToken()), address(new TestLinkToken()).code);

        dripsDataStore = new DripsDataStore();

        RepoDriverDataProxy dataProxyLogic = new RepoDriverDataProxy(driver, dripsDataStore, caller);
        dataProxy = RepoDriverDataProxy(address(new ManagedProxy(dataProxyLogic, address(2))));

        caller.authorize(address(dataProxy));

        Forge forge = Forge.GitHub;
        bytes memory name = "this/repo";
        accountId = driver.calcAccountId(forge, name);
        driver.requestUpdateOwner(forge, name);
        bytes32 requestId = keccak256(abi.encodePacked(driver, uint256(0)));
        vm.prank(operator);
        driver.updateOwnerByAnyApi(requestId, abi.encodePacked(this));

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(driver), type(uint256).max);
    }

    function testSetStreams() public {
        uint128 amt = 5;

        // Top-up
        StreamReceiver[] memory receivers = new StreamReceiver[](1);
        receivers[0] = StreamReceiver(123, StreamConfigImpl.create(0, drips.minAmtPerSec(), 0, 0));
        bytes32 hash = dripsDataStore.storeStreams(receivers);
        uint256 balance = erc20.balanceOf(address(this));

        int128 balanceDelta =
            dataProxy.setStreams(accountId, erc20, int128(amt), hash, noHints, address(this));

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance after top-up");
        (bytes32 streamsHash,,, uint128 streamsBalance,) = drips.streamsState(accountId, erc20);
        assertEq(streamsHash, hash, "Invalid streams hash after top-up");
        assertEq(streamsBalance, amt, "Invalid streams balance after top-up");
        assertEq(balanceDelta, int128(amt), "Invalid streams balance delta after top-up");

        // Withdraw
        balance = erc20.balanceOf(address(user));

        balanceDelta =
            dataProxy.setStreams(accountId, erc20, -int128(amt), 0, noHints, address(user));

        assertEq(erc20.balanceOf(address(user)), balance + amt, "Invalid balance after withdrawal");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance after withdrawal");
        (streamsHash,,, streamsBalance,) = drips.streamsState(accountId, erc20);
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
            data: abi.encodeCall(
                dataProxy.setStreams, (accountId, erc20, int128(amt), 0, noHints, address(this))
            ),
            value: 0
        });

        caller.callBatched(calls);

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance");
        (,,, uint128 streamsBalance,) = drips.streamsState(accountId, erc20);
        assertEq(streamsBalance, amt, "Invalid streams balance");
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(123, 1);
        bytes32 hash = dripsDataStore.storeSplits(receivers);

        dataProxy.setSplits(accountId, hash);

        assertEq(drips.splitsHash(accountId), hash, "Invalid splits hash");
    }

    function testSetSplitsTrustsForwarder() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(123, 1);
        bytes32 hash = dripsDataStore.storeSplits(receivers);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(dataProxy),
            data: abi.encodeCall(dataProxy.setSplits, (accountId, hash)),
            value: 0
        });

        caller.callBatched(calls);

        assertEq(drips.splitsHash(accountId), hash, "Invalid splits hash");
    }

    function testEmitAccountMetadata() public {
        AccountMetadata[] memory accountMetadata = new AccountMetadata[](1);
        accountMetadata[0] = AccountMetadata("key", "value");
        bytes32 hash = dripsDataStore.storeAccountMetadata(accountMetadata);
        dataProxy.emitAccountMetadata(accountId, hash);
    }

    function testEmitAccountMetadataTrustsForwarder() public {
        AccountMetadata[] memory accountMetadata = new AccountMetadata[](1);
        accountMetadata[0] = AccountMetadata("key", "value");
        bytes32 hash = dripsDataStore.storeAccountMetadata(accountMetadata);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(dataProxy),
            data: abi.encodeCall(dataProxy.emitAccountMetadata, (accountId, hash)),
            value: 0
        });
        caller.callBatched(calls);
    }

    function notDelegatedReverts() internal returns (RepoDriverDataProxy dataProxy_) {
        dataProxy_ = RepoDriverDataProxy(dataProxy.implementation());
        vm.expectRevert("Function must be called through delegatecall");
    }

    function testSetStreamsMustBeDelegated() public {
        notDelegatedReverts().setStreams(0, erc20, 0, 0, noHints, user);
    }

    function testSetSplitsMustBeDelegated() public {
        notDelegatedReverts().setSplits(0, 0);
    }

    function testEmitAccountMetadataMustBeDelegated() public {
        notDelegatedReverts().emitAccountMetadata(0, 0);
    }
}
