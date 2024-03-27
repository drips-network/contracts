// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {DripsDataStore, NFTDriver, NFTDriverDataProxy} from "src/dataStore/NFTDriverDataProxy.sol";
import {Call, Caller} from "src/Caller.sol";
import {
    AccountMetadata, StreamConfigImpl, Drips, StreamReceiver, SplitsReceiver
} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";
import {
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract NFTDriverDataProxyTest is Test {
    Drips internal drips;
    Caller internal caller;
    NFTDriver internal driver;
    DripsDataStore internal dripsDataStore;
    NFTDriverDataProxy internal dataProxy;
    IERC20 internal erc20;

    address internal user = address(1);
    uint256 internal tokenId;
    bytes32 internal someMetadataHash;

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this))));

        caller = new Caller();

        // Make NFTDriver's driver ID non-0 to test if it's respected by NFTDriver
        drips.registerDriver(address(1));
        drips.registerDriver(address(1));
        NFTDriver driverLogic = new NFTDriver(drips, address(caller), drips.nextDriverId());
        driver = NFTDriver(address(new ManagedProxy(driverLogic, address(2))));
        drips.registerDriver(address(driver));

        dripsDataStore = new DripsDataStore();

        NFTDriverDataProxy dataProxyLogic = new NFTDriverDataProxy(driver, dripsDataStore, caller);
        dataProxy = NFTDriverDataProxy(address(new ManagedProxy(dataProxyLogic, address(2))));

        caller.authorize(address(dataProxy));

        tokenId = driver.mint(address(this), new AccountMetadata[](0));

        AccountMetadata[] memory someMetadata = new AccountMetadata[](1);
        someMetadata[0] = AccountMetadata("key", "value");
        someMetadataHash = dripsDataStore.storeAccountMetadata(someMetadata);

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(driver), type(uint256).max);
    }

    function assertTokenDoesNotExist(uint256 nonExistentTokenId) internal {
        vm.expectRevert("ERC721: invalid token ID");
        driver.ownerOf(nonExistentTokenId);
    }

    function testMintIncreasesTokenId() public {
        uint256 nextTokenId = driver.nextTokenId();
        assertTokenDoesNotExist(nextTokenId);

        uint256 newTokenId = dataProxy.mint(user, someMetadataHash);

        assertEq(newTokenId, nextTokenId, "Invalid new tokenId");
        assertEq(driver.nextTokenId(), newTokenId + 1, "Invalid next tokenId");
        assertEq(driver.ownerOf(newTokenId), user, "Invalid token owner");
    }

    function testSafeMintIncreasesTokenId() public {
        uint256 nextTokenId = driver.nextTokenId();
        assertTokenDoesNotExist(nextTokenId);

        uint256 newTokenId = dataProxy.safeMint(user, someMetadataHash);

        assertEq(newTokenId, nextTokenId, "Invalid new tokenId");
        assertEq(driver.nextTokenId(), newTokenId + 1, "Invalid next tokenId");
        assertEq(driver.ownerOf(newTokenId), user, "Invalid token owner");
    }

    function testMintWithSaltUsesUpSalt() public {
        uint64 salt = 123;
        uint256 newTokenId = driver.calcTokenIdWithSalt(address(this), salt);
        assertFalse(driver.isSaltUsed(address(this), salt), "Salt already used");
        assertTokenDoesNotExist(newTokenId);

        uint256 mintedTokenId = dataProxy.mintWithSalt(salt, user, someMetadataHash);

        assertEq(mintedTokenId, newTokenId, "Invalid new tokenId");
        assertTrue(driver.isSaltUsed(address(this), salt), "Salt not used");
        assertEq(driver.ownerOf(newTokenId), user, "Invalid token owner");
    }

    function testSafeMintWithSaltUsesUpSalt() public {
        uint64 salt = 123;
        uint256 newTokenId = driver.calcTokenIdWithSalt(address(this), salt);
        assertFalse(driver.isSaltUsed(address(this), salt), "Salt already used");
        assertTokenDoesNotExist(newTokenId);

        uint256 mintedTokenId = dataProxy.safeMintWithSalt(salt, user, someMetadataHash);

        assertEq(mintedTokenId, newTokenId, "Invalid new tokenId");
        assertTrue(driver.isSaltUsed(address(this), salt), "Salt not used");
        assertEq(driver.ownerOf(newTokenId), user, "Invalid token owner");
    }

    function testSetStreams() public {
        uint128 amt = 5;

        // Top-up
        StreamReceiver[] memory receivers = new StreamReceiver[](1);
        receivers[0] = StreamReceiver(123, StreamConfigImpl.create(0, drips.minAmtPerSec(), 0, 0));
        bytes32 hash = dripsDataStore.storeStreams(receivers);
        uint256 balance = erc20.balanceOf(address(this));

        int128 balanceDelta =
            dataProxy.setStreams(tokenId, erc20, int128(amt), hash, 0, 0, address(this));

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance after top-up");
        (bytes32 streamsHash,,, uint128 streamsBalance,) = drips.streamsState(tokenId, erc20);
        assertEq(streamsHash, hash, "Invalid streams hash after top-up");
        assertEq(streamsBalance, amt, "Invalid streams balance after top-up");
        assertEq(balanceDelta, int128(amt), "Invalid streams balance delta after top-up");

        // Withdraw
        balance = erc20.balanceOf(address(user));

        balanceDelta = dataProxy.setStreams(tokenId, erc20, -int128(amt), 0, 0, 0, address(user));

        assertEq(erc20.balanceOf(address(user)), balance + amt, "Invalid balance after withdrawal");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance after withdrawal");
        (streamsHash,,, streamsBalance,) = drips.streamsState(tokenId, erc20);
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
                dataProxy.setStreams, (tokenId, erc20, int128(amt), 0, 0, 0, address(this))
            ),
            value: 0
        });

        caller.callBatched(calls);

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance");
        (,,, uint128 streamsBalance,) = drips.streamsState(tokenId, erc20);
        assertEq(streamsBalance, amt, "Invalid streams balance");
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(123, 1);
        bytes32 hash = dripsDataStore.storeSplits(receivers);

        dataProxy.setSplits(tokenId, hash);

        assertEq(drips.splitsHash(tokenId), hash, "Invalid splits hash");
    }

    function testSetSplitsTrustsForwarder() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(123, 1);
        bytes32 hash = dripsDataStore.storeSplits(receivers);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(dataProxy),
            data: abi.encodeCall(dataProxy.setSplits, (tokenId, hash)),
            value: 0
        });

        caller.callBatched(calls);

        assertEq(drips.splitsHash(tokenId), hash, "Invalid splits hash");
    }

    function testEmitAccountMetadata() public {
        dataProxy.emitAccountMetadata(tokenId, someMetadataHash);
    }

    function testEmitAccountMetadataTrustsForwarder() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(dataProxy),
            data: abi.encodeCall(dataProxy.emitAccountMetadata, (tokenId, someMetadataHash)),
            value: 0
        });
        caller.callBatched(calls);
    }

    function notDelegatedReverts() internal returns (NFTDriverDataProxy dataProxy_) {
        dataProxy_ = NFTDriverDataProxy(dataProxy.implementation());
        vm.expectRevert("Function must be called through delegatecall");
    }

    function testMintMustBeDelegated() public {
        notDelegatedReverts().mint(user, 0);
    }

    function testSafeMintMustBeDelegated() public {
        notDelegatedReverts().safeMint(user, 0);
    }

    function testMintWithSaltMustBeDelegated() public {
        notDelegatedReverts().mintWithSalt(0, user, 0);
    }

    function testSafeMintWithSaltMustBeDelegated() public {
        notDelegatedReverts().safeMintWithSalt(0, user, 0);
    }

    function testSetStreamsMustBeDelegated() public {
        notDelegatedReverts().setStreams(0, erc20, 0, 0, 0, 0, user);
    }

    function testSetSplitsMustBeDelegated() public {
        notDelegatedReverts().setSplits(0, 0);
    }

    function testEmitAccountMetadataMustBeDelegated() public {
        notDelegatedReverts().emitAccountMetadata(0, 0);
    }
}
