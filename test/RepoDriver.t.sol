// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.19;

import {Caller} from "src/Caller.sol";
import {Forge, RepoDriver} from "src/RepoDriver.sol";
import {
    DripsConfigImpl,
    DripsHub,
    DripsHistory,
    DripsReceiver,
    SplitsReceiver,
    UserMetadata
} from "src/DripsHub.sol";
import {ManagedProxy} from "src/Managed.sol";
import {BufferChainlink, CBORChainlink} from "chainlink/Chainlink.sol";
import {ERC677ReceiverInterface} from "chainlink/interfaces/ERC677ReceiverInterface.sol";
import {OperatorInterface} from "chainlink/interfaces/OperatorInterface.sol";
import {LinkTokenInterface} from "chainlink/interfaces/LinkTokenInterface.sol";
import {console2, Test} from "forge-std/Test.sol";
import {
    ERC20,
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

using CBORChainlink for BufferChainlink.buffer;

contract TestLinkToken is ERC20("", "") {
    function mint(address receiver, uint256 amount) public {
        _mint(receiver, amount);
    }

    function transferAndCall(address to, uint256 value, bytes calldata data)
        external
        returns (bool success)
    {
        super.transfer(to, value);
        ERC677ReceiverInterface(to).onTokenTransfer(msg.sender, value, data);
        return true;
    }
}

contract MockDummy {
    fallback() external payable {
        revert("Call not mocked");
    }
}

contract RepoDriverTest is Test {
    DripsHub internal dripsHub;
    Caller internal caller;
    RepoDriver internal driver;
    uint256 internal driverNonce;
    IERC20 internal erc20;

    address internal admin = address(1);
    address internal user = address(2);
    uint256 internal userId;
    uint256 internal userId1;
    uint256 internal userId2;
    uint256 internal userIdUser;

    bytes internal constant ERROR_NOT_OWNER = "Caller is not the user owner";

    uint256 internal constant CHAIN_ID_MAINNET = 1;
    uint256 internal constant CHAIN_ID_GOERLI = 5;
    uint256 internal constant CHAIN_ID_SEPOLIA = 11155111;

    function setUp() public {
        DripsHub hubLogic = new DripsHub(10);
        dripsHub = DripsHub(address(new ManagedProxy(hubLogic, address(this))));

        caller = new Caller();

        // Make RepoDriver's driver ID non-0 to test if it's respected by RepoDriver
        dripsHub.registerDriver(address(1));
        dripsHub.registerDriver(address(1));
        deployDriver(CHAIN_ID_MAINNET);

        userId = initialUpdateOwner(address(this), "this/repo1");
        userId1 = initialUpdateOwner(address(this), "this/repo2");
        userId2 = initialUpdateOwner(address(this), "this/repo3");
        userIdUser = initialUpdateOwner(user, "user/repo");

        erc20 = new ERC20PresetFixedSupply("test", "test", type(uint136).max, address(this));
        erc20.approve(address(driver), type(uint256).max);
        erc20.transfer(user, erc20.totalSupply() / 100);
        vm.prank(user);
        erc20.approve(address(driver), type(uint256).max);
    }

    function deployDriver(uint256 chainId) public {
        vm.chainId(chainId);
        uint32 driverId = dripsHub.registerDriver(address(this));
        RepoDriver driverLogic = new RepoDriver(dripsHub, address(caller), driverId);
        driver = RepoDriver(address(new ManagedProxy(driverLogic, admin)));
        dripsHub.updateDriverAddress(driverId, address(driver));
        driverNonce = 0;
        updateAnyApiOperator(OperatorInterface(address(new MockDummy())), keccak256("job ID"), 2);

        TestLinkToken linkToken = TestLinkToken(address(driver.linkToken()));
        vm.etch(address(linkToken), address(new TestLinkToken()).code);
        linkToken.mint(address(this), 100);
        linkToken.mint(address(driver), 100);
    }

    function noMetadata() internal pure returns (UserMetadata[] memory userMetadata) {
        userMetadata = new UserMetadata[](0);
    }

    function someMetadata() internal pure returns (UserMetadata[] memory userMetadata) {
        userMetadata = new UserMetadata[](1);
        userMetadata[0] = UserMetadata("key", "value");
    }

    function updateAnyApiOperator(OperatorInterface operator, bytes32 jobId, uint96 defaultFee)
        internal
    {
        vm.prank(admin);
        driver.updateAnyApiOperator(operator, jobId, defaultFee);
        (OperatorInterface newOperator, bytes32 newJobId, uint96 newDefaultFee) =
            driver.anyApiOperator();
        require(newOperator == operator, "Invalid operator after the update");
        require(newJobId == jobId, "Invalid job ID after the update");
        require(newDefaultFee == defaultFee, "Invalid default fee after the update");
    }

    function initialUpdateOwner(address owner, string memory name)
        internal
        returns (uint256 ownedUserId)
    {
        Forge forge = Forge.GitHub;
        updateOwner(
            forge,
            bytes(name),
            owner,
            string.concat("https://raw.githubusercontent.com/", name, "/HEAD/FUNDING.json"),
            "drips,ethereum,ownedBy"
        );
        return driver.calcUserId(forge, bytes(name));
    }

    function updateOwner(
        Forge forge,
        bytes memory name,
        address owner,
        string memory url,
        string memory path
    ) internal {
        bytes32 requestId = requestUpdateOwner(forge, name, url, path);
        updateOwnerByAnyApi(requestId, owner);
        assertOwner(forge, name, owner);
    }

    function requestUpdateOwner(
        Forge forge,
        bytes memory name,
        string memory url,
        string memory path
    ) internal returns (bytes32 requestId) {
        (OperatorInterface operator,, uint96 fee) = driver.anyApiOperator();
        LinkTokenInterface linkToken = driver.linkToken();
        uint256 driverBalance = linkToken.balanceOf(address(driver));
        uint256 operatorBalance = linkToken.balanceOf(address(operator));

        mockOperatorRequest(url, path, driverNonce, fee);
        driver.requestUpdateOwner(forge, name);
        vm.clearMockedCalls();

        assertEq(
            linkToken.balanceOf(address(driver)), driverBalance - fee, "Invalid driver balance"
        );
        assertEq(
            linkToken.balanceOf(address(operator)),
            operatorBalance + fee,
            "Invalid operator balance"
        );
        return calcRequestId(driverNonce++);
    }

    function mockOperatorRequest(string memory url, string memory path, uint256 nonce, uint256 fee)
        internal
    {
        (OperatorInterface operator, bytes32 jobId,) = driver.anyApiOperator();

        BufferChainlink.buffer memory buffer;
        buffer = BufferChainlink.init(buffer, 256);
        buffer.encodeString("get");
        buffer.encodeString(url);
        buffer.encodeString("path");
        buffer.encodeString(path);

        vm.mockCall(
            address(operator),
            abi.encodeCall(
                ERC677ReceiverInterface.onTokenTransfer,
                (
                    address(driver),
                    fee,
                    abi.encodeCall(
                        OperatorInterface.operatorRequest,
                        (
                            address(0),
                            0,
                            jobId,
                            RepoDriver.updateOwnerByAnyApi.selector,
                            nonce,
                            2,
                            buffer.buf
                        )
                        )
                )
            ),
            ""
        );
    }

    function updateOwnerByAnyApi(bytes32 requestId, address owner) internal {
        (OperatorInterface operator,,) = driver.anyApiOperator();
        vm.prank(address(operator));
        driver.updateOwnerByAnyApi(requestId, abi.encodePacked(owner));
    }

    function assertOwner(Forge forge, bytes memory name, address expectedOwner) internal {
        uint256 repoUserId = driver.calcUserId(forge, name);
        assertEq(driver.ownerOf(repoUserId), expectedOwner, "Invalid user owner");
    }

    function calcRequestId(uint256 nonce) internal view returns (bytes32 requestId) {
        return keccak256(abi.encodePacked(address(driver), nonce));
    }

    function testUserIdsDoNotCollideBetweenForges() public {
        bytes memory name = "me/repo";
        uint256 userIdGitHub = driver.calcUserId(Forge.GitHub, name);
        uint256 userIdGitLab = driver.calcUserId(Forge.GitLab, name);
        assertFalse(userIdGitHub == userIdGitLab, "User IDs collide");
    }

    function testCalcUserId() public {
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

        assertUserId(
            Forge.GitHub,
            name3,
            0x00000002_00_612f62000000000000000000000000000000000000000000000000
        );
        assertUserId(
            Forge.GitHub,
            name27,
            0x00000002_00_6162636465666768696a6b6c6d2f6e6f707172737475767778797a
        );
        assertUserId(
            Forge.GitHub,
            name28,
            0x00000002_01_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866
        );
        assertUserId(
            Forge.GitLab,
            name3,
            0x00000002_02_612f62000000000000000000000000000000000000000000000000
        );
        assertUserId(
            Forge.GitLab,
            name27,
            0x00000002_02_6162636465666768696a6b6c6d2f6e6f707172737475767778797a
        );
        assertUserId(
            Forge.GitLab,
            name28,
            0x00000002_03_9b20b0f16f6d0e523b42684b6f3881fa3c23115048bc6643c2f866
        );
    }

    function assertUserId(Forge forge, bytes memory name, uint256 expectedUserId) internal {
        uint256 actualUserId = driver.calcUserId(forge, name);
        assertEq(bytes32(actualUserId), bytes32(expectedUserId), "Invalid user ID");
    }

    function testDeploymentOnUnknownChainReverts() public {
        vm.chainId(1234567890);
        vm.expectRevert("Unsupported chain");
        new RepoDriver(dripsHub, address(caller), 0);
    }

    function testUpdateOwnerGitHubMainnet() public {
        updateOwner(
            Forge.GitHub,
            "me/repo",
            user,
            "https://raw.githubusercontent.com/me/repo/HEAD/FUNDING.json",
            "drips,ethereum,ownedBy"
        );
    }

    function testUpdateOwnerGitLabMainnet() public {
        updateOwner(
            Forge.GitLab,
            "me/repo",
            user,
            "https://gitlab.com/me/repo/-/raw/HEAD/FUNDING.json",
            "drips,ethereum,ownedBy"
        );
    }

    function testUpdateOwnerGitHubGoerli() public {
        deployDriver(CHAIN_ID_GOERLI);
        updateOwner(
            Forge.GitHub,
            "me/repo",
            user,
            "https://raw.githubusercontent.com/me/repo/HEAD/FUNDING.json",
            "drips,goerli,ownedBy"
        );
    }

    function testUpdateOwnerGitHubSepolia() public {
        deployDriver(CHAIN_ID_SEPOLIA);
        updateOwner(
            Forge.GitHub,
            "me/repo",
            user,
            "https://raw.githubusercontent.com/me/repo/HEAD/FUNDING.json",
            "drips,sepolia,ownedBy"
        );
    }

    function testRequestUpdateOwnerRevertsWhenNotEnoughLink() public {
        uint256 balance = driver.linkToken().balanceOf(address(driver));
        (OperatorInterface operator, bytes32 jobId,) = driver.anyApiOperator();
        updateAnyApiOperator(operator, jobId, uint96(balance) + 1);
        vm.expectRevert("Link balance too low");
        driver.requestUpdateOwner(Forge.GitHub, "me/repo");
    }

    function testRequestUpdateOwnerRevertsWhenOperatorAddressIsZero() public {
        (, bytes32 jobId, uint96 fee) = driver.anyApiOperator();
        updateAnyApiOperator(OperatorInterface(address(0)), jobId, fee);
        vm.expectRevert("Operator address not set");
        driver.requestUpdateOwner(Forge.GitHub, "me/repo");
    }

    function testUpdateOwnerByAnyApiRevertsIfNotCalledByTheOperator() public {
        bytes32 requestId = requestUpdateOwner(
            Forge.GitHub,
            "me/repo",
            "https://raw.githubusercontent.com/me/repo/HEAD/FUNDING.json",
            "drips,ethereum,ownedBy"
        );
        vm.expectRevert("Callable only by the operator");
        driver.updateOwnerByAnyApi(requestId, abi.encodePacked(user));
    }

    function testUpdateOwnerByAnyApiRevertsIfUnknownRequestId() public {
        (OperatorInterface operator,,) = driver.anyApiOperator();
        vm.prank(address(operator));
        vm.expectRevert("Unknown request ID");
        driver.updateOwnerByAnyApi(keccak256("requestId"), abi.encodePacked(user));
    }

    function testUpdateOwnerByAnyApiRevertsIfReusedRequestId() public {
        bytes32 requestId = requestUpdateOwner(
            Forge.GitHub,
            "me/repo",
            "https://raw.githubusercontent.com/me/repo/HEAD/FUNDING.json",
            "drips,ethereum,ownedBy"
        );
        (OperatorInterface operator,,) = driver.anyApiOperator();

        vm.prank(address(operator));
        driver.updateOwnerByAnyApi(requestId, abi.encodePacked(user));

        vm.prank(address(operator));
        vm.expectRevert("Unknown request ID");
        driver.updateOwnerByAnyApi(requestId, abi.encodePacked(user));
    }

    function testUpdateOwnerByAnyApiRevertsIfOwnerIsNotAddress() public {
        bytes32 requestId = requestUpdateOwner(
            Forge.GitHub,
            "me/repo",
            "https://raw.githubusercontent.com/me/repo/HEAD/FUNDING.json",
            "drips,ethereum,ownedBy"
        );
        (OperatorInterface operator,,) = driver.anyApiOperator();

        vm.prank(address(operator));
        vm.expectRevert("Invalid owner length");
        driver.updateOwnerByAnyApi(requestId, abi.encodePacked(user, uint8(0)));
    }

    function testOnTokenTransfer() public {
        (OperatorInterface operator,,) = driver.anyApiOperator();
        LinkTokenInterface linkToken = driver.linkToken();
        uint256 thisBalance = linkToken.balanceOf(address(this));
        uint256 operatorBalance = linkToken.balanceOf(address(operator));
        uint256 fee = thisBalance / 2;

        mockOperatorRequest(
            "https://raw.githubusercontent.com/me/repo/HEAD/FUNDING.json",
            "drips,ethereum,ownedBy",
            driverNonce,
            fee
        );
        linkToken.transferAndCall(
            address(driver),
            fee,
            abi.encodeCall(driver.requestUpdateOwner, (Forge.GitHub, "me/repo"))
        );

        assertEq(linkToken.balanceOf(address(this)), thisBalance - fee, "Invalid this balance");
        assertEq(
            linkToken.balanceOf(address(operator)),
            operatorBalance + fee,
            "Invalid operator balance"
        );
        updateOwnerByAnyApi(calcRequestId(driverNonce), user);
    }

    function testOnTokenTransferRevertsIfNotLinkIsReceived() public {
        TestLinkToken notLinkToken = new TestLinkToken();
        notLinkToken.mint(address(this), 1);
        vm.expectRevert("Callable only by the Link token");
        notLinkToken.transferAndCall(
            address(driver), 1, abi.encodeCall(driver.requestUpdateOwner, (Forge.GitHub, "me/repo"))
        );
    }

    function testOnTokenTransferRevertsIfPayloadIsNotCalldata() public {
        LinkTokenInterface linkToken = driver.linkToken();
        vm.expectRevert("Data not a valid calldata");
        linkToken.transferAndCall(address(driver), 1, "abc");
    }

    function testOnTokenTransferRevertsIfPayloadHasInvalidSelector() public {
        LinkTokenInterface linkToken = driver.linkToken();
        vm.expectRevert("Data not requestUpdateOwner");
        linkToken.transferAndCall(
            address(driver),
            1,
            abi.encodeWithSelector(driver.updateOwnerByAnyApi.selector, Forge.GitHub, "me/repo")
        );
    }

    function testOnTokenTransferRevertsIfPayloadIsNotValidCalldata() public {
        LinkTokenInterface linkToken = driver.linkToken();
        vm.expectRevert(bytes(""));
        linkToken.transferAndCall(
            address(driver),
            1,
            abi.encodeWithSelector(driver.requestUpdateOwner.selector, "me/repo")
        );
    }

    function testCollect() public {
        uint128 amt = 5;
        driver.give(userId1, userId2, erc20, amt);
        dripsHub.split(userId2, erc20, new SplitsReceiver[](0));
        uint256 balance = erc20.balanceOf(address(this));
        uint128 collected = driver.collect(userId2, erc20, address(this));
        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(address(this)), balance + amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(dripsHub)), 0, "Invalid DripsHub balance");
    }

    function testCollectTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        driver.give(userId1, userId2, erc20, amt);
        dripsHub.split(userId2, erc20, new SplitsReceiver[](0));
        address transferTo = address(1234);
        uint128 collected = driver.collect(userId2, erc20, transferTo);
        assertEq(collected, amt, "Invalid collected");
        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(dripsHub)), 0, "Invalid DripsHub balance");
    }

    function testCollectRevertsWhenNotUserOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.collect(userIdUser, erc20, address(this));
    }

    function testGive() public {
        uint128 amt = 5;
        uint256 balance = erc20.balanceOf(address(this));
        driver.give(userId1, userId2, erc20, amt);
        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(dripsHub)), amt, "Invalid DripsHub balance");
        assertEq(dripsHub.splittable(userId2, erc20), amt, "Invalid received amount");
    }

    function testGiveRevertsWhenNotUserOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.give(userIdUser, userId, erc20, 5);
    }

    function testSetDrips() public {
        uint128 amt = 5;
        // Top-up
        DripsReceiver[] memory receivers = new DripsReceiver[](1);
        receivers[0] =
            DripsReceiver(userId2, DripsConfigImpl.create(0, dripsHub.minAmtPerSec(), 0, 0));
        uint256 balance = erc20.balanceOf(address(this));
        int128 realBalanceDelta = driver.setDrips(
            userId1, erc20, new DripsReceiver[](0), int128(amt), receivers, 0, 0, address(this)
        );
        assertEq(erc20.balanceOf(address(this)), balance - amt, "Invalid balance after top-up");
        assertEq(erc20.balanceOf(address(dripsHub)), amt, "Invalid DripsHub balance after top-up");
        (,,, uint128 dripsBalance,) = dripsHub.dripsState(userId1, erc20);
        assertEq(dripsBalance, amt, "Invalid drips balance after top-up");
        assertEq(realBalanceDelta, int128(amt), "Invalid drips balance delta after top-up");
        (bytes32 dripsHash,,,,) = dripsHub.dripsState(userId1, erc20);
        assertEq(dripsHash, dripsHub.hashDrips(receivers), "Invalid drips hash after top-up");
        // Withdraw
        balance = erc20.balanceOf(address(user));
        realBalanceDelta =
            driver.setDrips(userId1, erc20, receivers, -int128(amt), receivers, 0, 0, address(user));
        assertEq(erc20.balanceOf(address(user)), balance + amt, "Invalid balance after withdrawal");
        assertEq(erc20.balanceOf(address(dripsHub)), 0, "Invalid DripsHub balance after withdrawal");
        (,,, dripsBalance,) = dripsHub.dripsState(userId1, erc20);
        assertEq(dripsBalance, 0, "Invalid drips balance after withdrawal");
        assertEq(realBalanceDelta, -int128(amt), "Invalid drips balance delta after withdrawal");
    }

    function testSetDripsDecreasingBalanceTransfersFundsToTheProvidedAddress() public {
        uint128 amt = 5;
        DripsReceiver[] memory receivers = new DripsReceiver[](0);
        driver.setDrips(userId, erc20, receivers, int128(amt), receivers, 0, 0, address(this));
        address transferTo = address(1234);
        int128 realBalanceDelta =
            driver.setDrips(userId, erc20, receivers, -int128(amt), receivers, 0, 0, transferTo);
        assertEq(erc20.balanceOf(transferTo), amt, "Invalid balance");
        assertEq(erc20.balanceOf(address(dripsHub)), 0, "Invalid DripsHub balance");
        (,,, uint128 dripsBalance,) = dripsHub.dripsState(userId1, erc20);
        assertEq(dripsBalance, 0, "Invalid drips balance");
        assertEq(realBalanceDelta, -int128(amt), "Invalid drips balance delta");
    }

    function testSetDripsRevertsWhenNotUserOwner() public {
        DripsReceiver[] memory noReceivers = new DripsReceiver[](0);
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setDrips(userIdUser, erc20, noReceivers, 0, noReceivers, 0, 0, address(this));
    }

    function testSetSplits() public {
        SplitsReceiver[] memory receivers = new SplitsReceiver[](1);
        receivers[0] = SplitsReceiver(userId2, 1);
        driver.setSplits(userId, receivers);
        bytes32 actual = dripsHub.splitsHash(userId);
        bytes32 expected = dripsHub.hashSplits(receivers);
        assertEq(actual, expected, "Invalid splits hash");
    }

    function testSetSplitsRevertsWhenNotUserOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.setSplits(userIdUser, new SplitsReceiver[](0));
    }

    function testEmitUserMetadata() public {
        driver.emitUserMetadata(userId, someMetadata());
    }

    function testEmitUserMetadataRevertsWhenNotUserOwner() public {
        vm.expectRevert(ERROR_NOT_OWNER);
        driver.emitUserMetadata(userIdUser, someMetadata());
    }

    function testForwarderIsTrusted() public {
        vm.prank(user);
        caller.authorize(address(this));
        assertEq(dripsHub.splittable(userId, erc20), 0, "Invalid splittable before give");
        uint128 amt = 10;
        bytes memory giveData =
            abi.encodeWithSelector(driver.give.selector, userIdUser, userId, erc20, amt);
        caller.callAs(user, address(driver), giveData);
        assertEq(dripsHub.splittable(userId, erc20), amt, "Invalid splittable after give");
    }

    modifier canBePausedTest() {
        vm.prank(admin);
        driver.pause();
        vm.expectRevert("Contract paused");
        _;
    }

    function testUpdateAnyApiOperatorCanBePaused() public canBePausedTest {
        driver.updateAnyApiOperator(OperatorInterface(address(0)), 0, 0);
    }

    function testRequestUpdateOwnerCanBePaused() public canBePausedTest {
        driver.requestUpdateOwner(Forge.GitHub, "");
    }

    function testOnTokenTransferCanBePaused() public canBePausedTest {
        driver.onTokenTransfer(address(0), 0, "");
    }

    function testUpdateOwnerByAnyApiCanBePaused() public canBePausedTest {
        driver.updateOwnerByAnyApi(0, "");
    }

    function testCollectCanBePaused() public canBePausedTest {
        driver.collect(0, erc20, user);
    }

    function testGiveCanBePaused() public canBePausedTest {
        driver.give(0, 0, erc20, 0);
    }

    function testSetDripsCanBePaused() public canBePausedTest {
        driver.setDrips(0, erc20, new DripsReceiver[](0), 0, new DripsReceiver[](0), 0, 0, user);
    }

    function testSetSplitsCanBePaused() public canBePausedTest {
        driver.setSplits(0, new SplitsReceiver[](0));
    }

    function testEmitUserMetadataCanBePaused() public canBePausedTest {
        driver.emitUserMetadata(0, noMetadata());
    }
}
