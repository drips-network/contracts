// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Caller} from "src/Caller.sol";
import {RepoDriver, RepoSubAccountDriver} from "src/RepoSubAccountDriver.sol";
import {
    AccountMetadata,
    StreamConfigImpl,
    Drips,
    StreamsHistory,
    StreamReceiver,
    SplitsReceiver
} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {console, Test} from "forge-std/Test.sol"; // TODO remove console
import {
    ERC20,
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

contract FakeRepoDriver {
    Drips public immutable drips;
    uint32 public immutable driverId;

    constructor(Drips drips_, uint32 driverId_) {
        drips = drips_;
        driverId = driverId_;
    }

    mapping(uint256 accountId => address owner) public ownerOf;

    function calcAccountId(bytes28 accountIdCore) public view returns (uint256 accountId) {
        return uint256(driverId) << 224 | uint224(accountIdCore);
    }

    function setOwnerOf(uint256 accountId, address owner) public {
        ownerOf[accountId] = owner;
    }
}

contract RepoSubAccountDriverTest is Test {
    Drips internal drips;
    Caller internal caller;
    FakeRepoDriver internal repoDriver;
    RepoSubAccountDriver internal driver;
    IERC20 internal erc20;

    uint256 internal accountId;
    uint256 internal accountParentId;
    uint256 internal unownedAccountId;
    uint256 internal unownedAccountParentId;

    bytes internal constant ERROR_NOT_OWNER = "Caller is not the account owner";

    function setUp() public {
        // This value is good for testing account ID translations.
        // 3 (RepoSubAccountDriver ID) is binary `011` and 5 (FakeRepoDriver ID) is `101`.
        uint32 driverId = 3;
        uint32 repoDriverId = 5;

        caller = new Caller();

        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this), "")));
        repoDriver = new FakeRepoDriver(drips, repoDriverId);

        RepoSubAccountDriver driverLogic = new RepoSubAccountDriver(
            RepoDriver(payable(address(repoDriver))), address(caller), driverId
        );
        driver = RepoSubAccountDriver(
            payable(new ManagedProxy(driverLogic, address(bytes20("admin")), ""))
        );

        while (drips.nextDriverId() != driverId) {
            drips.registerDriver(address(1));
        }
        drips.registerDriver(address(driver));

        accountParentId = repoDriver.calcAccountId("account");
        accountId = driver.calcAccountId(accountParentId);
        repoDriver.setOwnerOf(accountParentId, address(this));

        unownedAccountParentId = repoDriver.calcAccountId("unowned account");
        unownedAccountId = driver.calcAccountId(unownedAccountParentId);

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(driver), type(uint256).max);
    }

    function someMetadata() internal pure returns (AccountMetadata[] memory accountMetadata) {
        accountMetadata = new AccountMetadata[](1);
        accountMetadata[0] = AccountMetadata("key", "value");
    }

    function testCalcAccountIdWorksBothWays() public view {
        assertEq(driver.calcAccountId(accountId), accountParentId, "Invalid parent account ID");
    }

    function testAccountOwnershipIsCopiedFromTheParent() public {
        assertEq(driver.ownerOf(accountId), address(this), "Invalid initial account owner");
        address newOwner = address(bytes20("new owner"));
        repoDriver.setOwnerOf(accountParentId, newOwner);
        assertEq(driver.ownerOf(accountId), newOwner, "Invalid final account owner");
    }

    function testCollect() public {
        uint128 amt = 5;
        driver.give(accountId, accountId, erc20, amt);
        drips.split(accountId, erc20, new SplitsReceiver[](0));
        uint256 balance = erc20.balanceOf(address(this));
        uint128 collected = driver.collect(accountId, erc20, address(this));
        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(address(this)), balance + amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance");
    }

    function testCollectTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        driver.give(accountId, accountId, erc20, amt);
        drips.split(accountId, erc20, new SplitsReceiver[](0));
        address transferTo = address(bytes20("recipient"));
        uint128 collected = driver.collect(accountId, erc20, transferTo);
        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance");
    }

    function testCollectRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.collect(unownedAccountId, erc20, address(this));
    }

    function testGive() public {
        uint128 amt = 5;
        uint256 balance = erc20.balanceOf(address(this));
        driver.give(accountId, unownedAccountId, erc20, amt);
        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance");
        assertEq(drips.splittable(unownedAccountId, erc20), amt, "Invalid received amount");
    }

    function testGiveRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.give(unownedAccountId, accountId, erc20, 5);
    }

    function testSetStreams() public {
        uint128 amt = 5;
        // Top-up
        StreamReceiver[] memory receivers = new StreamReceiver[](1);
        receivers[0] =
            StreamReceiver(unownedAccountId, StreamConfigImpl.create(0, drips.minAmtPerSec(), 0, 0));
        uint256 balance = erc20.balanceOf(address(this));
        int128 realBalanceDelta = driver.setStreams(
            accountId, erc20, new StreamReceiver[](0), int128(amt), receivers, 0, 0, address(this)
        );
        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance after top-up");
        (,,, uint128 streamsBalance,) = drips.streamsState(accountId, erc20);
        assertEq(streamsBalance, amt, "Invalid streams balance after top-up");
        assertEq(realBalanceDelta, int128(amt), "Invalid streams balance delta after top-up");
        (bytes32 streamsHash,,,,) = drips.streamsState(accountId, erc20);
        assertEq(streamsHash, drips.hashStreams(receivers), "Invalid streams hash after top-up");
        // Withdraw
        address transferTo = address(bytes20("recipient"));
        balance = erc20.balanceOf(transferTo);
        realBalanceDelta = driver.setStreams(
            accountId, erc20, receivers, -int128(amt), receivers, 0, 0, transferTo
        );
        assertEq(erc20.balanceOf(transferTo), balance + amt, "Invalid balance after withdrawal");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance after withdrawal");
        (,,, streamsBalance,) = drips.streamsState(accountId, erc20);
        assertEq(streamsBalance, 0, "Invalid streams balance after withdrawal");
        assertEq(realBalanceDelta, -int128(amt), "Invalid streams balance delta after withdrawal");
    }

    function testSetStreamsRevertsWhenNotAccountOwner() public {
        StreamReceiver[] memory noReceivers = new StreamReceiver[](0);
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setStreams(unownedAccountId, erc20, noReceivers, 0, noReceivers, 0, 0, address(this));
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(unownedAccountId, 1);
        driver.setSplits(accountId, receivers);
        bytes32 actual = drips.splitsHash(accountId);
        bytes32 expected = drips.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testSetSplitsRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setSplits(unownedAccountId, new SplitsReceiver[](0));
    }

    function testEmitAccountMetadata() public {
        driver.emitAccountMetadata(accountId, someMetadata());
    }

    function testEmitAccountMetadataRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.emitAccountMetadata(unownedAccountId, someMetadata());
    }

    function testForwarderIsTrusted() public {
        address user = address(bytes20("user"));
        repoDriver.setOwnerOf(unownedAccountParentId, user);
        vm.prank(user);
        caller.authorize(address(this));
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(accountId, 1);

        bytes memory setSplitsData =
            abi.encodeWithSelector(driver.setSplits.selector, unownedAccountId, receivers);
        caller.callAs(user, address(driver), setSplitsData);

        bytes32 actual = drips.splitsHash(unownedAccountId);
        bytes32 expected = drips.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    modifier canBePausedTest() {
        vm.prank(driver.admin());
        driver.pause();
        vm.expectRevert("Contract paused");
        _;
    }

    function testCollectCanBePaused() public canBePausedTest {
        driver.collect(0, erc20, address(0));
    }

    function testGiveCanBePaused() public canBePausedTest {
        driver.give(0, 0, erc20, 0);
    }

    function testSetStreamsCanBePaused() public canBePausedTest {
        driver.setStreams(
            0, erc20, new StreamReceiver[](0), 0, new StreamReceiver[](0), 0, 0, address(0)
        );
    }

    function testSetSplitsCanBePaused() public canBePausedTest {
        driver.setSplits(0, new SplitsReceiver[](0));
    }

    function testEmitAccountMetadataCanBePaused() public canBePausedTest {
        driver.emitAccountMetadata(0, someMetadata());
    }
}
