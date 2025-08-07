// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Caller} from "src/Caller.sol";
import {RepoDriver} from "src/RepoDriver.sol";
import {
    AccountMetadata,
    StreamConfigImpl,
    Drips,
    StreamsHistory,
    StreamReceiver,
    SplitsReceiver
} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {console, StdAssertions, Test, Vm} from "forge-std/Test.sol";
import {
    ERC20,
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

contract RepoDriverTest is Test {
    Drips internal drips;
    Caller internal caller;
    RepoDriver internal driver;
    IERC20 internal erc20;

    bytes32 internal chain = "chain";
    bytes32 internal otherChain = "other chain";
    Vm.Wallet internal oracle = vm.createWallet("oracle");
    Vm.Wallet internal otherOracle = vm.createWallet("other oracle");
    address internal admin = address(bytes20("admin"));
    address internal otherAdmin = address(bytes20("other admin"));
    address internal user = address(bytes20("user"));
    address internal otherUser = address(bytes20("other user"));
    uint256 internal accountId;
    uint256 internal accountId1;
    uint256 internal accountId2;
    uint256 internal accountIdUser;

    bytes internal constant ERROR_NOT_OWNER = "Caller is not the account owner";

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, admin, "")));

        caller = new Caller();

        // Make RepoDriver's driver ID non-0 to test if it's respected by RepoDriver
        drips.registerDriver(address(1));
        drips.registerDriver(address(1));

        RepoDriver driverLogic = new RepoDriver(drips, address(caller), drips.nextDriverId(), chain);
        bytes memory initCalldata = abi.encodeCall(RepoDriver.updateLitOracle, (oracle.addr));
        driver = RepoDriver(payable(new ManagedProxy(driverLogic, admin, initCalldata)));
        drips.registerDriver(address(driver));

        accountId = updateOwnerByLit(0, "this/name1", address(this), 1);
        accountId1 = updateOwnerByLit(0, "this/name2", address(this), 1);
        accountId2 = updateOwnerByLit(0, "this/name3", address(this), 1);
        accountIdUser = updateOwnerByLit(0, "user/name", user, 1);

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(driver), type(uint256).max);
        erc20.transfer(user, erc20.totalSupply() / 100);
        vm.prank(user);
        erc20.approve(address(driver), type(uint256).max);
    }

    function noMetadata() internal pure returns (AccountMetadata[] memory accountMetadata) {
        accountMetadata = new AccountMetadata[](0);
    }

    function someMetadata() internal pure returns (AccountMetadata[] memory accountMetadata) {
        accountMetadata = new AccountMetadata[](1);
        accountMetadata[0] = AccountMetadata("key", "value");
    }

    function signPayload(
        Vm.Wallet memory wallet,
        bytes32 chain_,
        uint8 sourceId,
        bytes memory name,
        address owner,
        uint32 timestamp
    ) internal pure returns (bytes32 r, bytes32 vs) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version)"),
                keccak256("DripsOwnership"),
                keccak256("1")
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "DripsOwnership(bytes32 chain,uint8 sourceId,"
                    "bytes name,address owner,uint32 timestamp)"
                ),
                chain_,
                sourceId,
                keccak256(name),
                owner,
                timestamp
            )
        );
        return vm.signCompact(wallet.privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    }

    function updateOwnerByLit(uint8 sourceId, bytes memory name, address owner, uint32 timestamp)
        internal
        returns (uint256 accountId_)
    {
        (bytes32 r, bytes32 vs) = signPayload(oracle, chain, sourceId, name, owner, timestamp);
        return updateOwnerByLit(sourceId, name, owner, timestamp, r, vs);
    }

    function updateOwnerByLit(
        uint8 sourceId,
        bytes memory name,
        address owner,
        uint32 timestamp,
        bytes32 r,
        bytes32 vs
    ) internal returns (uint256 accountId_) {
        accountId_ = driver.updateOwnerByLit(sourceId, name, owner, timestamp, r, vs);
        assertEq(driver.ownerOf(accountId_), owner, "Invalid account owner");
        assertAccountId(sourceId, name, accountId_);
    }

    function assertAccountId(uint8 sourceId, bytes memory name, uint256 expectedAccountId)
        internal
        view
    {
        uint256 actualAccountId = driver.calcAccountId(sourceId, name);
        assertEq(bytes32(actualAccountId), bytes32(expectedAccountId), "Invalid account ID");
    }

    function testCalcAccountId() public view {
        bytes memory name3 = "a/b";
        bytes memory name27 = "abcdefghijklm/nopqrstuvwxyz";
        bytes memory name28 = "abcdefghijklm/nopqrstuvwxyz_";

        // The lookup of the hex values for the manual inspection of the test
        assertEq(driver.driverId(), 0x00000002, "Invalid driver ID hex representation");
        assertEq(bytes3(name3), bytes3(0x612f62), "Invalid 3 byte name hex representation");
        assertEq(
            bytes27(name27),
            bytes27(0x6162636465666768696a6b6c6d2f6e6f707172737475767778797a),
            "Invalid 27 byte name hex representation"
        );
        assertEq(
            keccak256(name28),
            0x14ef39e0dc_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866,
            "Invalid 28 byte name hash"
        );

        assertAccountId(
            0, name3, 0x00000002_00_612f62000000000000000000000000000000000000000000000000
        );
        assertAccountId(
            0, name27, 0x00000002_00_6162636465666768696a6b6c6d2f6e6f707172737475767778797a
        );
        assertAccountId(
            0, name28, 0x00000002_01_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866
        );
        assertAccountId(
            1, name3, 0x00000002_02_612f62000000000000000000000000000000000000000000000000
        );
        assertAccountId(
            1, name27, 0x00000002_02_6162636465666768696a6b6c6d2f6e6f707172737475767778797a
        );
        assertAccountId(
            1, name28, 0x00000002_03_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866
        );
        assertAccountId(
            2, name3, 0x00000002_04_612f62000000000000000000000000000000000000000000000000
        );
        assertAccountId(
            2, name27, 0x00000002_04_6162636465666768696a6b6c6d2f6e6f707172737475767778797a
        );
        assertAccountId(
            2, name28, 0x00000002_05_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866
        );
        assertAccountId(
            127, name3, 0x00000002_fe_612f62000000000000000000000000000000000000000000000000
        );
        assertAccountId(
            127, name27, 0x00000002_fe_6162636465666768696a6b6c6d2f6e6f707172737475767778797a
        );
        assertAccountId(
            127, name28, 0x00000002_ff_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866
        );
    }

    function testCalcAccountIdRevertsWhenSourceIdTooHigh() public {
        vm.expectRevert("Source ID too high");
        driver.calcAccountId(128, "name");
    }

    function testEmitAccountId() public {
        uint8 sourceId = 1;
        bytes memory name = "name";

        uint256 accountId_ = driver.emitAccountId(sourceId, name);

        assertAccountId(sourceId, name, accountId_);
    }

    function testUpdateLitOracle() public {
        assertEq(driver.litOracle(), oracle.addr, "Invalid oracle before the update");
        vm.prank(admin);
        driver.updateLitOracle(otherOracle.addr);
        assertEq(driver.litOracle(), otherOracle.addr, "Invalid oracle after the update");
    }

    function testUpdateLitOracleRevertsWhenNotCalledByTheAdmin() public {
        vm.expectRevert("Caller not the admin");
        driver.updateLitOracle(otherAdmin);
    }

    function testUpdateOwnerByLit() public {
        uint8 sourceId = 1;
        bytes memory name = "name";
        uint32 timestamp = 1;
        (bytes32 r, bytes32 vs) = signPayload(oracle, chain, sourceId, name, user, timestamp);
        updateOwnerByLit(sourceId, name, user, timestamp, r, vs);
    }

    function testUpdateOwnerByLitRevertsWhenSignatureInvalid() public {
        uint8 sourceId = 1;
        bytes memory name = "name";
        uint32 timestamp = 1;
        (bytes32 r, bytes32 vs) = signPayload(oracle, chain, sourceId, name, user, timestamp);

        // Invalid source ID
        expectSignatureInvalid(sourceId + 1, name, user, timestamp, r, vs);
        // Invalid name
        expectSignatureInvalid(sourceId, bytes.concat(name, "!"), user, timestamp, r, vs);
        // Invalid new owner
        expectSignatureInvalid(sourceId, name, otherUser, timestamp, r, vs);
        // Invalid timestamp
        expectSignatureInvalid(sourceId, name, user, timestamp + 1, r, vs);
        // // Invalid R
        expectSignatureInvalid(sourceId, name, user, timestamp, r ^ bytes32(uint256(0x01)), vs);
        // // Invalid VS
        expectSignatureInvalid(sourceId, name, user, timestamp, r, vs ^ bytes32(uint256(0x0100)));
        // Invalid oracle
        (r, vs) = signPayload(otherOracle, chain, sourceId, name, user, timestamp);
        expectSignatureInvalid(sourceId, name, user, timestamp, r, vs);
        // Invalid chain
        (r, vs) = signPayload(oracle, otherChain, sourceId, name, user, timestamp);
        expectSignatureInvalid(sourceId, name, user, timestamp, r, vs);
    }

    function expectSignatureInvalid(
        uint8 sourceId,
        bytes memory name,
        address owner,
        uint32 timestamp,
        bytes32 r,
        bytes32 vs
    ) internal {
        vm.expectRevert("Invalid Lit oracle signature");
        driver.updateOwnerByLit(sourceId, name, owner, timestamp, r, vs);
    }

    function testUpdateOwnerByLitWhenSignatureNewerThanCurrentlyUsed() public {
        uint8 sourceId = 1;
        bytes memory name = "name";
        uint32 timestamp = 2;
        updateOwnerByLit(sourceId, name, user, timestamp);

        updateOwnerByLit(sourceId, name, otherUser, timestamp + 1);
    }

    function testUpdateOwnerByLitRevertsWhenSignatureAsOldAsCurrentlyUsed() public {
        uint8 sourceId = 1;
        bytes memory name = "name";
        uint32 timestamp = 2;
        updateOwnerByLit(sourceId, name, user, timestamp);

        (bytes32 r, bytes32 vs) = signPayload(oracle, chain, sourceId, name, otherUser, timestamp);
        vm.expectRevert("Payload obsolete");
        driver.updateOwnerByLit(sourceId, name, otherUser, timestamp, r, vs);
    }

    function testUpdateOwnerByLitRevertsWhenSignatureOlderThanCurrentlyUsed() public {
        uint8 sourceId = 1;
        bytes memory name = "name";
        uint32 timestamp = 2;
        updateOwnerByLit(sourceId, name, user, timestamp);

        timestamp--;
        (bytes32 r, bytes32 vs) = signPayload(oracle, chain, sourceId, name, otherUser, timestamp);
        vm.expectRevert("Payload obsolete");
        driver.updateOwnerByLit(sourceId, name, otherUser, timestamp, r, vs);
    }

    function testUpdateOwnerByLitUsingRealOracleResponse() public {
        vm.prank(admin);
        driver.updateLitOracle(0xB032D1391AD387D2CDDAA855B32dB957E178503C);
        updateOwnerByLit(
            0,
            "CodeSandwich/Not-dogdy-AT-ALL",
            0x0123456789abcDEF0123456789abCDef01234567,
            1754398879,
            0x28decba6e911311664cbc601c72e6d8701c7ec5ecff82732bc7e7dd4d2e0eed4,
            0x5dd612af3d39922a105320458d7f7452ae00ab2d828ff4969f64abe63c8bd6b9
        );
    }

    function testCollect() public {
        uint128 amt = 5;
        driver.give(accountId1, accountId2, erc20, amt);
        drips.split(accountId2, erc20, new SplitsReceiver[](0));
        uint256 balance = erc20.balanceOf(address(this));
        uint128 collected = driver.collect(accountId2, erc20, address(this));
        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(address(this)), balance + amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance");
    }

    function testCollectTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        driver.give(accountId1, accountId2, erc20, amt);
        drips.split(accountId2, erc20, new SplitsReceiver[](0));
        address transferTo = address(bytes20("recipient"));
        uint128 collected = driver.collect(accountId2, erc20, transferTo);
        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance");
    }

    function testCollectRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.collect(accountIdUser, erc20, address(this));
    }

    function testGive() public {
        uint128 amt = 5;
        uint256 balance = erc20.balanceOf(address(this));
        driver.give(accountId1, accountId2, erc20, amt);
        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance");
        assertEq(drips.splittable(accountId2, erc20), amt, "Invalid received amount");
    }

    function testGiveRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.give(accountIdUser, accountId, erc20, 5);
    }

    function testSetStreams() public {
        uint128 amt = 5;
        // Top-up
        StreamReceiver[] memory receivers = new StreamReceiver[](1);
        receivers[0] =
            StreamReceiver(accountId2, StreamConfigImpl.create(0, drips.minAmtPerSec(), 0, 0));
        uint256 balance = erc20.balanceOf(address(this));
        int128 realBalanceDelta = driver.setStreams(
            accountId1, erc20, new StreamReceiver[](0), int128(amt), receivers, 0, 0, address(this)
        );
        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance after top-up");
        (,,, uint128 streamsBalance,) = drips.streamsState(accountId1, erc20);
        assertEq(streamsBalance, amt, "Invalid streams balance after top-up");
        assertEq(realBalanceDelta, int128(amt), "Invalid streams balance delta after top-up");
        (bytes32 streamsHash,,,,) = drips.streamsState(accountId1, erc20);
        assertEq(streamsHash, drips.hashStreams(receivers), "Invalid streams hash after top-up");
        // Withdraw
        balance = erc20.balanceOf(address(user));
        realBalanceDelta = driver.setStreams(
            accountId1, erc20, receivers, -int128(amt), receivers, 0, 0, address(user)
        );
        assertEq(erc20.balanceOf(address(user)), balance + amt, "Invalid balance after withdrawal");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance after withdrawal");
        (,,, streamsBalance,) = drips.streamsState(accountId1, erc20);
        assertEq(streamsBalance, 0, "Invalid streams balance after withdrawal");
        assertEq(realBalanceDelta, -int128(amt), "Invalid streams balance delta after withdrawal");
    }

    function testSetStreamsDecreasingBalanceTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        StreamReceiver[] memory receivers = new StreamReceiver[](0);
        driver.setStreams(accountId, erc20, receivers, int128(amt), receivers, 0, 0, address(this));
        address transferTo = address(bytes20("recipient"));
        int128 realBalanceDelta = driver.setStreams(
            accountId, erc20, receivers, -int128(amt), receivers, 0, 0, transferTo
        );
        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance");
        (,,, uint128 streamsBalance,) = drips.streamsState(accountId1, erc20);
        assertEq(streamsBalance, 0, "Invalid streams balance");
        assertEq(realBalanceDelta, -int128(amt), "Invalid streams balance delta");
    }

    function testSetStreamsRevertsWhenNotAccountOwner() public {
        StreamReceiver[] memory noReceivers = new StreamReceiver[](0);
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setStreams(accountIdUser, erc20, noReceivers, 0, noReceivers, 0, 0, address(this));
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(accountId2, 1);
        driver.setSplits(accountId, receivers);
        bytes32 actual = drips.splitsHash(accountId);
        bytes32 expected = drips.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testSetSplitsRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setSplits(accountIdUser, new SplitsReceiver[](0));
    }

    function testEmitAccountMetadata() public {
        driver.emitAccountMetadata(accountId, someMetadata());
    }

    function testEmitAccountMetadataRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.emitAccountMetadata(accountIdUser, someMetadata());
    }

    function testForwarderIsTrusted() public {
        vm.prank(user);
        caller.authorize(address(this));
        assertEq(drips.splittable(accountId, erc20), 0, "Invalid splittable before give");
        uint128 amt = 10;
        bytes memory giveData =
            abi.encodeWithSelector(driver.give.selector, accountIdUser, accountId, erc20, amt);
        caller.callAs(user, address(driver), giveData);
        assertEq(drips.splittable(accountId, erc20), amt, "Invalid splittable after give");
    }

    modifier canBePausedTest() {
        vm.prank(admin);
        driver.pause();
        vm.expectRevert("Contract paused");
        _;
    }

    function testCollectCanBePaused() public canBePausedTest {
        driver.collect(0, erc20, user);
    }

    function testGiveCanBePaused() public canBePausedTest {
        driver.give(0, 0, erc20, 0);
    }

    function testSetStreamsCanBePaused() public canBePausedTest {
        driver.setStreams(0, erc20, new StreamReceiver[](0), 0, new StreamReceiver[](0), 0, 0, user);
    }

    function testSetSplitsCanBePaused() public canBePausedTest {
        driver.setSplits(0, new SplitsReceiver[](0));
    }

    function testEmitAccountMetadataCanBePaused() public canBePausedTest {
        driver.emitAccountMetadata(0, noMetadata());
    }
}
