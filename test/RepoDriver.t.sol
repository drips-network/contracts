// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Caller} from "src/Caller.sol";
import {
    Forge,
    FunctionsConfig,
    IERC677Receiver,
    IFunctionsConfig,
    IFunctionsRouter,
    LinkTokenInterface,
    RepoDriver
} from "src/RepoDriver.sol";
import {
    AccountMetadata,
    StreamConfigImpl,
    Drips,
    StreamsHistory,
    StreamReceiver,
    SplitsReceiver
} from "src/Drips.sol";
import {ManagedProxy} from "src/Managed.sol";
import {MockLinkToken} from "chainlink/mocks/MockLinkToken.sol";
import {console2, Test} from "forge-std/Test.sol";
import {
    ERC20,
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract MockDummy {
    fallback() external payable {
        revert("Call not mocked");
    }
}

contract RepoDriverTest is Test {
    Drips internal drips;
    Caller internal caller;
    RepoDriver internal driver;
    IFunctionsConfig internal functionsConfig;
    IERC20 internal erc20;

    address internal admin = address(1);
    address internal user = address(2);
    uint256 internal accountId;
    uint256 internal otherAccountId;
    uint256 internal userAccountId;
    Forge internal accountForge = Forge.GitHub;
    bytes internal accountName = "this/repo";

    bytes internal constant ERROR_NOT_OWNER = "Caller is not the account owner";

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this))));

        caller = new Caller();

        functionsConfig = new FunctionsConfig(1234);
        vm.etch(address(linkToken()), address(new MockLinkToken()).code);
        MockLinkToken(address(linkToken())).setBalance(address(this), 100);
        vm.etch(functionsRouter(), address(new MockDummy()).code);

        // Make RepoDriver's driver ID non-0 to test if it's respected by RepoDriver
        drips.registerDriver(address(1));
        drips.registerDriver(address(1));
        RepoDriver driverLogic =
            new RepoDriver(drips, address(caller), drips.nextDriverId(), functionsConfig);
        driver = RepoDriver(address(new ManagedProxy(driverLogic, admin)));
        drips.registerDriver(address(driver));
        assertEq(
            address(driver.functionsConfig()),
            address(functionsConfig),
            "Invalid initial Functions functionsConfig"
        );

        accountId = updateOwner(accountForge, accountName, address(this));
        otherAccountId = updateOwner(Forge.GitLab, "this/other", address(this));
        userAccountId = updateOwner(Forge.GitHub, "user/repo", user);

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(driver), type(uint256).max);
        erc20.transfer(user, erc20.totalSupply() / 100);
        vm.prank(user);
        erc20.approve(address(driver), type(uint256).max);
    }

    function linkToken() internal view returns (LinkTokenInterface linkToken_) {
        (linkToken_,,) = functionsConfig.subscription();
    }

    function functionsRouter() internal view returns (address functionsRouter_) {
        (, IFunctionsRouter functionsRouterRaw,) = functionsConfig.subscription();
        return address(functionsRouterRaw);
    }

    function subscriptionId() internal view returns (uint64 subscriptionId_) {
        (,, subscriptionId_) = functionsConfig.subscription();
    }

    function noMetadata() internal pure returns (AccountMetadata[] memory accountMetadata) {
        accountMetadata = new AccountMetadata[](0);
    }

    function someMetadata() internal pure returns (AccountMetadata[] memory accountMetadata) {
        accountMetadata = new AccountMetadata[](1);
        accountMetadata[0] = AccountMetadata("key", "value");
    }

    function updateOwner(Forge forge, bytes memory name, address owner)
        internal
        returns (uint256 accountId_)
    {
        bytes32 requestId;
        (accountId_, requestId) = requestUpdateOwner(forge, name);
        handleOracleFulfillment(requestId, forge, name, owner);
    }

    function requestUpdateOwner(Forge forge, bytes memory name)
        internal
        returns (uint256 accountId_, bytes32 requestId)
    {
        requestId = mockSendRequest(forge, name);
        accountId_ = driver.requestUpdateOwner(forge, name);
        vm.clearMockedCalls();
        assertEq(accountId_, driver.calcAccountId(forge, name), "Invalid returned account ID");
    }

    function mockSendRequest(Forge forge, bytes memory name) internal returns (bytes32 requestId) {
        (bytes memory data, uint16 dataVersion, uint32 callbackGasLimit, bytes32 donId) =
            functionsConfig.buildRequest(forge, name);
        bytes memory expectedData = abi.encodeCall(
            IFunctionsRouter.sendRequest,
            (subscriptionId(), data, dataVersion, callbackGasLimit, donId)
        );
        requestId = bytes32(gasleft());
        vm.mockCall(functionsRouter(), expectedData, abi.encode(requestId));
        vm.expectCall(functionsRouter(), expectedData);
    }

    function handleOracleFulfillment(
        bytes32 requestId,
        Forge forge,
        bytes memory name,
        address owner
    ) internal {
        vm.prank(functionsRouter());
        driver.handleOracleFulfillment(requestId, abi.encode(owner), "");
        assertOwner(forge, name, owner);
    }

    function mockFundSubscription(uint256 amt) internal {
        bytes memory expectedData = abi.encodeCall(
            IERC677Receiver.onTokenTransfer, (address(driver), amt, abi.encode(subscriptionId()))
        );
        vm.mockCall(functionsRouter(), expectedData, "");
        vm.expectCall(functionsRouter(), expectedData);
    }

    function assertOwner(Forge forge, bytes memory name, address expectedOwner) internal {
        assertOwner(driver.calcAccountId(forge, name), expectedOwner);
    }

    function assertOwner(uint256 accountId_, address expectedOwner) internal {
        assertEq(driver.ownerOf(accountId_), expectedOwner, "Invalid account owner");
    }

    function assertRouterBalance(uint256 amt) internal {
        assertEq(linkToken().balanceOf(functionsRouter()), amt, "Invalid router balance");
    }

    function fundSubscriptionCalldata() internal pure returns (bytes memory data) {
        data = abi.encodeCall(RepoDriver.fundSubscription, ());
    }

    function requestUpdateOwnerCalldata(Forge forge, bytes memory name)
        internal
        pure
        returns (bytes memory data)
    {
        data = abi.encodeCall(RepoDriver.requestUpdateOwner, (forge, name));
    }

    function testAccountIdsDoNotCollideBetweenForges() public {
        bytes memory name = "me/repo";
        uint256 accountIdGitHub = driver.calcAccountId(Forge.GitHub, name);
        uint256 accountIdGitLab = driver.calcAccountId(Forge.GitLab, name);
        assertFalse(accountIdGitHub == accountIdGitLab, "Account IDs collide");
    }

    function testCalcAccountId() public {
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
            0x14ef39e0dc9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866,
            "Invalid 28 byte name hash"
        );

        assertAccountId(
            Forge.GitHub,
            name3,
            0x00000002_00_612f62000000000000000000000000000000000000000000000000
        );
        assertAccountId(
            Forge.GitHub,
            name27,
            0x00000002_00_6162636465666768696a6b6c6d2f6e6f707172737475767778797a
        );
        assertAccountId(
            Forge.GitHub,
            name28,
            0x00000002_01_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866
        );
        assertAccountId(
            Forge.GitLab,
            name3,
            0x00000002_02_612f62000000000000000000000000000000000000000000000000
        );
        assertAccountId(
            Forge.GitLab,
            name27,
            0x00000002_02_6162636465666768696a6b6c6d2f6e6f707172737475767778797a
        );
        assertAccountId(
            Forge.GitLab,
            name28,
            0x00000002_03_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866
        );
    }

    function assertAccountId(Forge forge, bytes memory name, uint256 expectedAccountId) internal {
        uint256 actualAccountId = driver.calcAccountId(forge, name);
        assertEq(bytes32(actualAccountId), bytes32(expectedAccountId), "Invalid account ID");
    }

    function testFundSubscription() public {
        uint256 amt = 10;
        linkToken().transfer(address(driver), amt);
        mockFundSubscription(amt);
        driver.fundSubscription();
        assertRouterBalance(amt);
    }

    function testFundSubscriptionDoesNothingWhenBalanceIsZero() public {
        driver.fundSubscription();
        assertRouterBalance(0);
    }

    function testOnTokenTransferForFundSubscription() public {
        runOnTokenTransferFundSubscriptionTest(10, 7);
    }

    function testOnTokenTransferForFundSubscriptionWhenBalanceIsZero() public {
        runOnTokenTransferFundSubscriptionTest(0, 10);
    }

    function testOnTokenTransferForFundSubscriptionWhenAmountIsZero() public {
        runOnTokenTransferFundSubscriptionTest(10, 0);
    }

    function runOnTokenTransferFundSubscriptionTest(uint256 amtDriver, uint256 amtTransfer)
        public
    {
        uint256 amt = amtDriver + amtTransfer;
        linkToken().transfer(address(driver), amtDriver);
        mockFundSubscription(amt);
        linkToken().transferAndCall(address(driver), amtTransfer, fundSubscriptionCalldata());
        assertRouterBalance(amt);
    }

    function testOnTokenTransferForFundSubscriptionDoesNothingWhenValueAndBalanceAreZero() public {
        linkToken().transferAndCall(address(driver), 0, fundSubscriptionCalldata());
        assertRouterBalance(0);
    }

    function testOnTokenTransferForRequestUpdateOwner() public {
        runOnTokenTransferRequestUpdateOwnerTest(10, 7);
    }

    function testOnTokenTransferForRequestUpdateOwnerWhenBalanceIsZero() public {
        runOnTokenTransferRequestUpdateOwnerTest(0, 10);
    }

    function testOnTokenTransferForRequestUpdateOwnerWhenAmountIsZero() public {
        runOnTokenTransferRequestUpdateOwnerTest(10, 0);
    }

    function runOnTokenTransferRequestUpdateOwnerTest(uint256 amtDriver, uint256 amtTransfer)
        public
    {
        uint256 amt = amtDriver + amtTransfer;
        Forge forge = Forge.GitHub;
        bytes memory name = "this/newRepo";
        linkToken().transfer(address(driver), amtDriver);
        mockFundSubscription(amt);
        bytes32 requestId = mockSendRequest(forge, name);

        linkToken().transferAndCall(
            address(driver), amtTransfer, requestUpdateOwnerCalldata(forge, name)
        );

        assertRouterBalance(amt);
        handleOracleFulfillment(requestId, forge, name, address(9876));
    }

    function testOnTokenTransferForRequestUpdateOwnerWhenValueAndBalanceAreZero() public {
        Forge forge = Forge.GitHub;
        bytes memory name = "this/newRepo";
        bytes32 requestId = mockSendRequest(forge, name);

        linkToken().transferAndCall(address(driver), 0, requestUpdateOwnerCalldata(forge, name));

        assertRouterBalance(0);
        handleOracleFulfillment(requestId, forge, name, address(9876));
    }

    function testOnTokenTransferRevertsWhenNotCalledByLinkToken() public {
        vm.expectRevert("Callable only by the Link token");
        driver.onTokenTransfer(address(0), 0, "");
    }

    function testOnTokenTransferRevertsWhenDataIsNotCalldata() public {
        LinkTokenInterface linkToken_ = linkToken();
        vm.expectRevert("Data not a valid calldata");
        linkToken_.transferAndCall(address(driver), 0, "");
    }

    function testOnTokenTransferRevertsWhenWhenDataIsNotSupported() public {
        LinkTokenInterface linkToken_ = linkToken();
        vm.expectRevert("Data not a supported calldata");
        linkToken_.transferAndCall(address(driver), 0, abi.encodeCall(driver.functionsConfig, ()));
    }

    function testHandleOracleFulfillmentUpdatesOwner() public {
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        address owner = address(1234567890);
        vm.prank(functionsRouter());
        driver.handleOracleFulfillment(requestId, abi.encode(owner), "");
        assertOwner(accountId, owner);
    }

    function testHandleOracleFulfillmentAcceptsMaxAddress() public {
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        address owner = address(type(uint160).max);
        vm.prank(functionsRouter());
        driver.handleOracleFulfillment(requestId, abi.encode(owner), "");
        assertOwner(accountId, owner);
    }

    function testHandleOracleFulfillmentAcceptsZeroAddress() public {
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        address owner = address(0);
        vm.prank(functionsRouter());
        driver.handleOracleFulfillment(requestId, abi.encode(owner), "");
        assertOwner(accountId, owner);
    }

    function testHandleOracleFulfillmentTreatsOutOfBoundAddressAsZero() public {
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        vm.prank(functionsRouter());
        driver.handleOracleFulfillment(requestId, abi.encode(uint256(type(uint160).max) + 1), "");
        assertOwner(accountId, address(0));
    }

    function testHandleOracleFulfillmentTreatsErrorAsZeroAddress() public {
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        vm.prank(functionsRouter());
        driver.handleOracleFulfillment(requestId, "", "Error");
        assertOwner(accountId, address(0));
    }

    function testHandleOracleFulfillmentRevertsWhenNotCalledByFunctionsRouter() public {
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        vm.expectRevert("Callable only by the router");
        driver.handleOracleFulfillment(requestId, abi.encode(address(0)), "");
    }

    function testHandleOracleFulfillmentRevertsWhenResponseTooShort() public {
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        vm.prank(functionsRouter());
        vm.expectRevert("Invalid response length");
        driver.handleOracleFulfillment(requestId, new bytes(31), "");
    }

    function testHandleOracleFulfillmentRevertsWhenResponseTooLong() public {
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        vm.prank(functionsRouter());
        vm.expectRevert("Invalid response length");
        driver.handleOracleFulfillment(requestId, new bytes(33), "");
    }

    function testUpdateFunctionsConfigRevertsWhenNotCalledByAdmin() public {
        IFunctionsConfig newConfig = new FunctionsConfig(9876);
        vm.expectRevert("Caller not the admin");
        driver.updateFunctionsConfig(newConfig);
    }

    function testUpdateFunctionsConfigIsRespectedByFunctionsConfig() public {
        updateFunctionsConfig();
        assertEq(
            address(driver.functionsConfig()), address(functionsConfig), "Invalid FunctionsConfig"
        );
    }

    function testUpdateFunctionsConfigIsRespectedByFundSubscription() public {
        updateFunctionsConfig();
        uint256 amt = 10;
        linkToken().transfer(address(driver), amt);
        mockFundSubscription(amt);
        expectCallSubscription();
        driver.fundSubscription();
    }

    function testUpdateFunctionsConfigIsRespectedByRequestUpdateOwner() public {
        updateFunctionsConfig();
        mockSendRequest(accountForge, accountName);
        expectCallSubscription();
        expectCallBuildRequest(accountForge, accountName);
        driver.requestUpdateOwner(accountForge, accountName);
    }

    function testUpdateFunctionsConfigIsRespectedByOnTokenTransferForFundSubscription() public {
        updateFunctionsConfig();
        LinkTokenInterface linkToken_ = linkToken();
        uint256 amt = 10;
        mockFundSubscription(amt);
        expectCallSubscription();
        linkToken_.transferAndCall(address(driver), amt, fundSubscriptionCalldata());
    }

    function testUpdateFunctionsConfigIsRespectedByOnTokenTransferForRequestUpdateOwner() public {
        updateFunctionsConfig();
        LinkTokenInterface linkToken_ = linkToken();
        uint256 amt = 10;
        mockFundSubscription(amt);
        mockSendRequest(accountForge, accountName);
        expectCallSubscription();
        expectCallBuildRequest(accountForge, accountName);
        linkToken_.transferAndCall(
            address(driver), amt, requestUpdateOwnerCalldata(accountForge, accountName)
        );
    }

    function testUpdateFunctionsConfigIsRespectedByHandleOracleFulfillment() public {
        updateFunctionsConfig();
        (, bytes32 requestId) = requestUpdateOwner(accountForge, accountName);
        vm.prank(functionsRouter());
        expectCallSubscription();
        driver.handleOracleFulfillment(requestId, abi.encode(address(1234567890)), "");
    }

    function updateFunctionsConfig() internal {
        bytes memory data = abi.encodeWithSignature("Error(string)", "Old FUnctionsConfig called");
        vm.mockCallRevert(address(functionsConfig), "", data);
        functionsConfig = new FunctionsConfig(9876);
        vm.prank(admin);
        driver.updateFunctionsConfig(functionsConfig);
    }

    function expectCallSubscription() internal {
        vm.expectCall(address(functionsConfig), abi.encodeCall(IFunctionsConfig.subscription, ()));
    }

    function expectCallBuildRequest(Forge forge, bytes memory name) internal {
        vm.expectCall(
            address(functionsConfig), abi.encodeCall(IFunctionsConfig.buildRequest, (forge, name))
        );
    }

    function testCollect() public {
        uint128 amt = 5;
        driver.give(accountId, otherAccountId, erc20, amt);
        drips.split(otherAccountId, erc20, new SplitsReceiver[](0));
        uint256 balance = erc20.balanceOf(address(this));
        uint128 collected = driver.collect(otherAccountId, erc20, address(this));
        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(address(this)), balance + amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance");
    }

    function testCollectTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        driver.give(accountId, otherAccountId, erc20, amt);
        drips.split(otherAccountId, erc20, new SplitsReceiver[](0));
        address transferTo = address(1234);
        uint128 collected = driver.collect(otherAccountId, erc20, transferTo);
        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance");
    }

    function testCollectRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.collect(userAccountId, erc20, address(this));
    }

    function testGive() public {
        uint128 amt = 5;
        uint256 balance = erc20.balanceOf(address(this));
        driver.give(accountId, otherAccountId, erc20, amt);
        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance");
        assertEq(drips.splittable(otherAccountId, erc20), amt, "Invalid received amount");
    }

    function testGiveRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.give(userAccountId, accountId, erc20, 5);
    }

    function testSetStreams() public {
        uint128 amt = 5;

        // Top-up
        StreamReceiver[] memory receivers = new StreamReceiver[](1);
        receivers[0] =
            StreamReceiver(otherAccountId, StreamConfigImpl.create(0, drips.minAmtPerSec(), 0, 0));
        uint256 balance = erc20.balanceOf(address(this));
        int128 realBalanceDelta = driver.setStreams(
            accountId, erc20, new StreamReceiver[](0), int128(amt), receivers, 0, 0, address(this)
        );
        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(erc20.balanceOf(address(drips)), amt, "Invalid Drips balance after top-up");
        (bytes32 streamsHash,,, uint128 streamsBalance,) = drips.streamsState(accountId, erc20);
        assertEq(streamsHash, drips.hashStreams(receivers), "Invalid streams hash after top-up");
        assertEq(streamsBalance, amt, "Invalid streams balance after top-up");
        assertEq(realBalanceDelta, int128(amt), "Invalid streams balance delta after top-up");

        // Withdraw
        balance = erc20.balanceOf(address(user));
        realBalanceDelta = driver.setStreams(
            accountId, erc20, receivers, -int128(amt), receivers, 0, 0, address(user)
        );
        assertEq(erc20.balanceOf(address(user)), balance + amt, "Invalid balance after withdrawal");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance after withdrawal");
        (,,, streamsBalance,) = drips.streamsState(accountId, erc20);
        assertEq(streamsBalance, 0, "Invalid streams balance after withdrawal");
        assertEq(realBalanceDelta, -int128(amt), "Invalid streams balance delta after withdrawal");
    }

    function testSetStreamsDecreasingBalanceTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        StreamReceiver[] memory receivers = new StreamReceiver[](0);
        driver.setStreams(accountId, erc20, receivers, int128(amt), receivers, 0, 0, address(this));
        address transferTo = address(1234);
        int128 realBalanceDelta = driver.setStreams(
            accountId, erc20, receivers, -int128(amt), receivers, 0, 0, transferTo
        );
        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(drips)), 0, "Invalid Drips balance");
        (,,, uint128 streamsBalance,) = drips.streamsState(accountId, erc20);
        assertEq(streamsBalance, 0, "Invalid streams balance");
        assertEq(realBalanceDelta, -int128(amt), "Invalid streams balance delta");
    }

    function testSetStreamsRevertsWhenNotAccountOwner() public {
        StreamReceiver[] memory noReceivers = new StreamReceiver[](0);
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setStreams(userAccountId, erc20, noReceivers, 0, noReceivers, 0, 0, address(this));
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(otherAccountId, 1);
        driver.setSplits(accountId, receivers);
        bytes32 actual = drips.splitsHash(accountId);
        bytes32 expected = drips.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testSetSplitsRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setSplits(userAccountId, new SplitsReceiver[](0));
    }

    function testEmitAccountMetadata() public {
        driver.emitAccountMetadata(accountId, someMetadata());
    }

    function testEmitAccountMetadataRevertsWhenNotAccountOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.emitAccountMetadata(userAccountId, someMetadata());
    }

    function testForwarderIsTrusted() public {
        vm.prank(user);
        caller.authorize(address(this));
        assertEq(drips.splittable(accountId, erc20), 0, "Invalid splittable before give");
        uint128 amt = 10;
        bytes memory giveData =
            abi.encodeWithSelector(driver.give.selector, userAccountId, accountId, erc20, amt);
        caller.callAs(user, address(driver), giveData);
        assertEq(drips.splittable(accountId, erc20), amt, "Invalid splittable after give");
    }

    modifier canBePausedTest() {
        vm.prank(admin);
        driver.pause();
        vm.expectRevert("Contract paused");
        _;
    }

    function testOnTokenTransferCanBePaused() public canBePausedTest {
        driver.onTokenTransfer(address(0), 0, "");
    }

    function testFundSubscriptionCanBePaused() public canBePausedTest {
        driver.fundSubscription();
    }

    function testRequestUpdateOwnerCanBePaused() public canBePausedTest {
        driver.requestUpdateOwner(Forge.GitHub, "");
    }

    function testHandleOracleFulfillmentCanBePaused() public canBePausedTest {
        driver.handleOracleFulfillment(0, "", "");
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
