// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Caller} from "../Caller.sol";
import {NFTDriver} from "../NFTDriver.sol";
import {
    DripsConfigImpl, DripsHub, DripsHistory, DripsReceiver, SplitsReceiver
} from "../DripsHub.sol";
import {Reserve} from "../Reserve.sol";
import {Proxy} from "../Upgradeable.sol";
import {Test} from "forge-std/Test.sol";
import {
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract NFTDriverTest is Test {
    DripsHub internal dripsHub;
    Caller internal caller;
    NFTDriver internal driver;
    IERC20 internal erc20;

    address internal user;
    uint256 internal tokenId;
    uint256 internal tokenId1;
    uint256 internal tokenId2;
    uint256 internal tokenIdUser;

    bytes internal constant ERROR_INVALID_TOKEN = "ERC721: invalid token ID";
    bytes internal constant ERROR_NOT_OWNER = "ERC721: caller is not token owner or approved";

    function setUp() public {
        Reserve reserve = new Reserve(address(this));
        DripsHub hubLogic = new DripsHub(10, reserve);
        dripsHub = DripsHub(address(new Proxy(hubLogic, address(this))));
        reserve.addUser(address(dripsHub));

        caller = new Caller();

        // Make NFTDriver's driver ID non-0 to test if it's respected by NFTDriver
        dripsHub.registerDriver(address(0));
        dripsHub.registerDriver(address(0));
        uint32 nftDriverId = dripsHub.registerDriver(address(this));
        NFTDriver driverLogic = new NFTDriver(dripsHub, address(caller), nftDriverId);
        driver = NFTDriver(address(new Proxy(driverLogic, address(0xDEAD))));
        dripsHub.updateDriverAddress(nftDriverId, address(driver));

        user = address(1);
        tokenId = driver.mint(address(this));
        tokenId1 = driver.mint(address(this));
        tokenId2 = driver.mint(address(this));
        tokenIdUser = driver.mint(user);

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(driver), type(uint256).max);
        erc20.transfer(user, erc20.totalSupply() / 100);
        vm.prank(user);
        erc20.approve(address(driver), type(uint256).max);
    }

    function testApproveLetsUseIdentity() public {
        vm.prank(user);
        driver.approve(address(this), tokenIdUser);
        driver.collect(tokenIdUser, erc20, address(user));
    }

    function testApproveAllLetsUseIdentity() public {
        vm.prank(user);
        driver.setApprovalForAll(address(this), true);
        driver.collect(tokenIdUser, erc20, address(user));
    }

    function testMintIncreasesTokenId() public {
        uint256 nextTokenId = driver.nextTokenId();
        vm.expectRevert(ERROR_INVALID_TOKEN);
        driver.ownerOf(nextTokenId);

        uint256 newTokenId = driver.mint(user);

        assertEq(newTokenId, nextTokenId, "Invalid new tokenId");
        assertEq(driver.nextTokenId(), newTokenId + 1, "Invalid next tokenId");
        assertEq(driver.ownerOf(newTokenId), user, "Invalid token owner");
    }

    function testSafeMintIncreasesTokenId() public {
        uint256 nextTokenId = driver.nextTokenId();
        vm.expectRevert(ERROR_INVALID_TOKEN);
        driver.ownerOf(nextTokenId);

        uint256 newTokenId = driver.safeMint(user);

        assertEq(newTokenId, nextTokenId, "Invalid new tokenId");
        assertEq(driver.nextTokenId(), newTokenId + 1, "Invalid next tokenId");
        assertEq(driver.ownerOf(newTokenId), user, "Invalid token owner");
    }

    function testSqueezeDrips() public {
        uint128 amt = 5;
        DripsReceiver[] memory receivers = new DripsReceiver[](1);
        receivers[0] = DripsReceiver(tokenId2, DripsConfigImpl.create(amt * 10 ** 18, 0, 0));
        driver.setDrips(
            tokenId1, erc20, new DripsReceiver[](0), int128(amt), receivers, address(this)
        );
        DripsHistory[] memory history = new DripsHistory[](1);
        history[0] = DripsHistory({
            dripsHash: 0,
            receivers: receivers,
            updateTime: uint32(block.timestamp),
            maxEnd: uint32(block.timestamp + 1)
        });
        skip(1);

        (uint128 squeezedAmt, uint32 nextSqueezed) =
            driver.squeezeDrips(tokenId2, erc20, tokenId1, 0, history);

        assertEq(squeezedAmt, amt, "Invalid squeezed amount");
        assertEq(nextSqueezed, block.timestamp, "Invalid next squeezed");
        assertEq(dripsHub.splittable(tokenId2, erc20), amt, "Invalid splittable amount");
    }

    function testSqueezeDripsRevertsWhenNotTokenHolder() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.squeezeDrips(tokenIdUser, erc20, tokenId, 0, new DripsHistory[](0));
    }

    function testCollect() public {
        uint128 amt = 5;
        driver.give(tokenId1, tokenId2, erc20, amt);
        dripsHub.split(tokenId2, erc20, new SplitsReceiver[](0));
        uint256 balance = erc20.balanceOf(address(this));

        uint128 collected = driver.collect(tokenId2, erc20, address(this));

        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(address(this)), balance + amt, "Invalid balance");
    }

    function testCollectRevertsWhenNotTokenHolder() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.collect(tokenIdUser, erc20, address(this));
    }

    function testGive() public {
        uint128 amt = 5;
        uint256 balance = erc20.balanceOf(address(this));

        driver.give(tokenId1, tokenId2, erc20, amt);

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(dripsHub.splittable(tokenId2, erc20), amt, "Invalid received amount");
    }

    function testGiveRevertsWhenNotTokenHolder() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.give(tokenIdUser, tokenId, erc20, 5);
    }

    function testSetDrips() public {
        uint128 amt = 5;

        // Top-up

        DripsReceiver[] memory receivers = new DripsReceiver[](1);
        receivers[0] = DripsReceiver(tokenId2, DripsConfigImpl.create(1, 0, 0));
        uint256 balance = erc20.balanceOf(address(this));

        (uint128 newBalance, int128 realBalanceDelta) = driver.setDrips(
            tokenId1, erc20, new DripsReceiver[](0), int128(amt), receivers, address(this)
        );

        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(newBalance, amt, "Invalid drips balance after top-up");
        assertEq(realBalanceDelta, int128(amt), "Invalid drips balance delta after top-up");
        (bytes32 dripsHash,,,,) = dripsHub.dripsState(tokenId1, erc20);
        assertEq(dripsHash, dripsHub.hashDrips(receivers), "Invalid drips hash after top-up");

        // Withdraw
        balance = erc20.balanceOf(address(user));

        (newBalance, realBalanceDelta) =
            driver.setDrips(tokenId1, erc20, receivers, -int128(amt), receivers, address(user));

        assertEq(erc20.balanceOf(address(user)), balance + amt, "Invalid balance after withdrawal");
        assertEq(newBalance, 0, "Invalid drips balance after withdrawal");
        assertEq(realBalanceDelta, -int128(amt), "Invalid drips balance delta after withdrawal");
    }

    function testSetDripsRevertsWhenNotTokenHolder() public {
        DripsReceiver[] memory noReceivers = new DripsReceiver[](0);
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setDrips(tokenIdUser, erc20, noReceivers, 0, noReceivers, address(this));
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(tokenId2, 1);

        driver.setSplits(tokenId, receivers);

        bytes32 actual = dripsHub.splitsHash(tokenId);
        bytes32 expected = dripsHub.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testSetSplitsRevertsWhenNotTokenHolder() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setSplits(tokenIdUser, new SplitsReceiver[](0));
    }

    function testForwarderIsTrustedInErc721Calls() public {
        vm.prank(user);
        caller.authorize(address(this));
        assertEq(driver.ownerOf(tokenIdUser), user, "Invalid token owner before transfer");

        bytes memory transferFromData =
            abi.encodeWithSelector(driver.transferFrom.selector, user, address(this), tokenIdUser);
        caller.callAs(user, address(driver), transferFromData);

        assertEq(driver.ownerOf(tokenIdUser), address(this), "Invalid token owner after transfer");
    }

    function testForwarderIsTrustedInDriverCalls() public {
        vm.prank(user);
        caller.authorize(address(this));
        assertEq(dripsHub.splittable(tokenId, erc20), 0, "Invalid splittable before give");
        uint128 amt = 10;

        bytes memory giveData =
            abi.encodeWithSelector(driver.give.selector, tokenIdUser, tokenId, erc20, amt);
        caller.callAs(user, address(driver), giveData);

        assertEq(dripsHub.splittable(tokenId, erc20), amt, "Invalid splittable after give");
    }
}
