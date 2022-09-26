// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {IReservePlugin, Reserve} from "../Reserve.sol";
import {
    IERC20,
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract TestReservePlugin is IReservePlugin {
    mapping(IERC20 => uint256) public deposited;

    function afterStart(IERC20 token, uint256 amt) public override {
        afterDeposition(token, amt);
    }

    function afterDeposition(IERC20 token, uint256 amt) public override {
        deposited[token] += amt;
    }

    function beforeWithdrawal(IERC20 token, uint256 amt) public override {
        deposited[token] -= amt;
        token.approve(msg.sender, amt);
    }

    function beforeEnd(IERC20 token, uint256 amt) public override {
        beforeWithdrawal(token, amt);
    }
}

contract ReserveTest is Test {
    Reserve public reserve;
    IReservePlugin public noPlugin;
    TestReservePlugin public plugin1;
    TestReservePlugin public plugin2;
    address public user;
    address public nonUser;
    address public owner;
    address public depositor;
    IERC20 public token;
    IERC20 public otherToken;

    bytes public constant ERROR_NOT_USER = "Reserve: caller is not the user";
    bytes public constant ERROR_NOT_OWNER = "Ownable: caller is not the owner";
    bytes public constant ERROR_DEPOSIT_SELF = "Reserve: deposition from self";
    bytes public constant ERROR_WITHDRAWAL_BALANCE = "Reserve: withdrawal over balance";

    function setUp() public {
        user = address(1);
        nonUser = address(2);
        owner = address(3);
        depositor = address(4);
        reserve = new Reserve(owner);
        noPlugin = reserve.NO_PLUGIN();
        plugin1 = new TestReservePlugin();
        plugin2 = new TestReservePlugin();

        vm.prank(owner);
        reserve.addUser(user);

        token = new ERC20PresetFixedSupply("token", "token", 30, address(this));
        otherToken = new ERC20PresetFixedSupply("otherToken", "otherToken", 30, address(this));
        token.transfer(depositor, 10);
        otherToken.transfer(depositor, 2);
    }

    function approveReserve(address approver, IERC20 forToken, uint256 amt) public {
        vm.prank(approver);
        forToken.approve(address(reserve), amt);
    }

    function setPlugin(address reserveUser, IERC20 forToken, IReservePlugin plugin) public {
        vm.prank(reserveUser);
        reserve.setPlugin(forToken, plugin);
        assertEq(address(reserve.plugins(forToken)), address(plugin), "New plugin not set");
    }

    function deposit(address reserveUser, IERC20 forToken, address from, uint256 amt) public {
        uint256 deposited = reserve.deposited(forToken);
        uint256 userBalance = forToken.balanceOf(from);
        approveReserve(from, forToken, amt);

        vm.prank(reserveUser);
        reserve.deposit(forToken, from, amt);

        string memory details = "after deposit";
        assertUserBalance(forToken, from, userBalance - amt, details);
        assertDeposited(forToken, deposited + amt, details);
    }

    function assertDepositReverts(
        address reserveUser,
        IERC20 forToken,
        address from,
        uint256 amt,
        bytes memory expectedReason
    ) public {
        approveReserve(from, forToken, amt);
        vm.expectRevert(expectedReason);
        vm.prank(reserveUser);
        reserve.deposit(forToken, from, amt);
        approveReserve(from, forToken, 0);
    }

    function withdraw(address reserveUser, IERC20 forToken, address to, uint256 amt) public {
        uint256 deposited = reserve.deposited(forToken);
        uint256 userBalance = forToken.balanceOf(to);

        vm.prank(reserveUser);
        reserve.withdraw(forToken, to, amt);

        string memory details = "after withdrawal";
        assertUserBalance(forToken, to, userBalance + amt, details);
        assertDeposited(forToken, deposited - amt, details);
    }

    function assertWithdrawReverts(
        address reserveUser,
        IERC20 forToken,
        address to,
        uint256 amt,
        bytes memory expectedReason
    ) public {
        vm.prank(reserveUser);
        vm.expectRevert(expectedReason);
        reserve.withdraw(forToken, to, amt);
    }

    function forceWithdraw(
        address reserveUser,
        IERC20 forToken,
        IReservePlugin plugin,
        address to,
        uint256 amt
    ) public {
        uint256 deposited = reserve.deposited(forToken);
        uint256 reserveBalance = forToken.balanceOf(address(reserve));
        uint256 userBalance = forToken.balanceOf(to);

        vm.prank(reserveUser);
        reserve.forceWithdraw(forToken, plugin, to, amt);

        string memory details = "after force withdrawal";
        assertUserBalance(forToken, to, userBalance + amt, details);
        assertDeposited(forToken, deposited, details);
        assertReserveBalance(forToken, reserveBalance - amt, details);
    }

    function assertForceWithdrawReverts(
        address reserveUser,
        IERC20 forToken,
        IReservePlugin plugin,
        address to,
        uint256 amt,
        bytes memory expectedReason
    ) public {
        vm.prank(reserveUser);
        vm.expectRevert(expectedReason);
        reserve.forceWithdraw(forToken, plugin, to, amt);
    }

    function assertUserBalance(
        IERC20 forToken,
        address forUser,
        uint256 expected,
        string memory details
    ) public {
        uint256 actual = forToken.balanceOf(forUser);
        assertEq(actual, expected, concat("Invalid user balance ", details));
    }

    function assertDeposited(IERC20 forToken, uint256 expected, string memory details) public {
        uint256 actual = reserve.deposited(forToken);
        assertEq(actual, expected, concat("Invalid deposited ", details));
    }

    function assertReserveBalance(IERC20 forToken, uint256 expected, string memory details)
        public
    {
        uint256 actual = forToken.balanceOf(address(reserve));
        assertEq(actual, expected, concat("Invalid reserve ", details));
    }

    function assertPluginDeposited(TestReservePlugin plugin, IERC20 forToken, uint256 expected)
        public
    {
        assertEq(plugin.deposited(forToken), expected, "Invalid plugin deposited");
    }

    function assertPluginBalance(TestReservePlugin plugin, IERC20 forToken, uint256 expected)
        public
    {
        assertEq(forToken.balanceOf(address(plugin)), expected, "Invalid plugin balance");
    }

    function concat(string memory str1, string memory str2) public pure returns (string memory) {
        return string(bytes.concat(bytes(str1), bytes(str2)));
    }

    function addUser(address currOwner, address addedUser) public {
        vm.prank(currOwner);
        reserve.addUser(addedUser);
        assertTrue(reserve.isUser(addedUser), "User not added");
    }

    function assertAddUserReverts(address currOwner, address addedUser, bytes memory expectedReason)
        public
    {
        vm.expectRevert(expectedReason);
        vm.prank(currOwner);
        reserve.addUser(addedUser);
    }

    function removeUser(address currOwner, address removedUser) public {
        vm.prank(currOwner);
        reserve.removeUser(removedUser);
        assertTrue(!reserve.isUser(removedUser), "User not removed");
    }

    function assertRemoveUserReverts(
        address currOwner,
        address removedUser,
        bytes memory expectedReason
    ) public {
        vm.prank(currOwner);
        vm.expectRevert(expectedReason);
        reserve.removeUser(removedUser);
    }

    function testPluginCanBeSet() public {
        deposit(user, token, depositor, 3);
        setPlugin(owner, token, plugin1);
        withdraw(user, token, depositor, 3);
    }

    function testPluginCanBeChanged() public {
        setPlugin(owner, token, plugin1);
        deposit(user, token, depositor, 3);
        setPlugin(owner, token, plugin2);
        withdraw(user, token, depositor, 3);
    }

    function testPluginCanBeRemoved() public {
        setPlugin(owner, token, plugin1);
        deposit(user, token, depositor, 3);
        setPlugin(owner, token, noPlugin);
        withdraw(user, token, depositor, 3);
    }

    function testSettingPluginsMovesOnlyDepositedFunds() public {
        deposit(user, token, depositor, 3);
        token.transfer(address(reserve), 1);
        // Set plugin1
        assertReserveBalance(token, 4, "before setting the plugin");
        setPlugin(owner, token, plugin1);
        assertReserveBalance(token, 1, "after setting the plugin");
        assertPluginDeposited(plugin1, token, 3);
        assertPluginBalance(plugin1, token, 3);
        // Side top-up of plugin1
        token.transfer(address(plugin1), 2);
        assertPluginBalance(plugin1, token, 5);
        // Set plugin2
        setPlugin(owner, token, plugin2);
        assertPluginDeposited(plugin1, token, 0);
        assertPluginBalance(plugin1, token, 2);
        assertPluginDeposited(plugin2, token, 3);
        assertPluginBalance(plugin2, token, 3);
        // Side top-up of plugin2
        token.transfer(address(plugin2), 5);
        assertPluginBalance(plugin2, token, 8);
        // Unset plugin2
        setPlugin(owner, token, noPlugin);
        assertPluginDeposited(plugin2, token, 0);
        assertPluginBalance(plugin2, token, 5);
        assertDeposited(token, 3, "after unsetting the plugin");
        assertReserveBalance(token, 4, "after unsetting the plugin");
    }

    function testRejectsNotOwnerSettingDrips() public {
        vm.prank(user);
        vm.expectRevert(ERROR_NOT_OWNER);
        reserve.setPlugin(token, plugin1);
    }

    function testUserDepositsAndWithdraws() public {
        deposit(user, token, depositor, 1);
        withdraw(user, token, depositor, 1);
    }

    function testDepositFromReserveReverts() public {
        token.transfer(address(reserve), 1);
        vm.prank(user);
        vm.expectRevert(ERROR_DEPOSIT_SELF);
        reserve.deposit(token, address(reserve), 1);
    }

    function testDepositFromPluginReverts() public {
        setPlugin(owner, token, plugin1);
        token.transfer(address(plugin1), 1);
        vm.prank(user);
        vm.expectRevert(ERROR_DEPOSIT_SELF);
        reserve.deposit(token, address(plugin1), 1);
    }

    function testRejectsWithdrawalOverBalance() public {
        deposit(user, token, depositor, 1);
        assertWithdrawReverts(user, token, depositor, 2, ERROR_WITHDRAWAL_BALANCE);
    }

    function testRejectsNonUserDepositing() public {
        assertDepositReverts(owner, token, depositor, 1, ERROR_NOT_USER);
        assertDepositReverts(nonUser, token, depositor, 1, ERROR_NOT_USER);
    }

    function testRejectsNonUserWithdrawing() public {
        deposit(user, token, depositor, 1);
        assertWithdrawReverts(owner, token, depositor, 1, ERROR_NOT_USER);
        assertWithdrawReverts(nonUser, token, depositor, 1, ERROR_NOT_USER);
    }

    function testAddUser() public {
        addUser(owner, nonUser);
        deposit(nonUser, token, depositor, 1);
        withdraw(nonUser, token, depositor, 1);
    }

    function testRejectNotOwnerAddingUser() public {
        assertAddUserReverts(user, nonUser, ERROR_NOT_OWNER);
        assertAddUserReverts(nonUser, nonUser, ERROR_NOT_OWNER);
    }

    function testRemoveUser() public {
        deposit(user, token, depositor, 1);
        removeUser(owner, user);
        assertDepositReverts(user, token, depositor, 1, ERROR_NOT_USER);
        assertWithdrawReverts(user, token, depositor, 1, ERROR_NOT_USER);
    }

    function testRejectNotOwnerRemovingUser() public {
        assertRemoveUserReverts(user, user, ERROR_NOT_OWNER);
        assertRemoveUserReverts(nonUser, user, ERROR_NOT_OWNER);
    }

    function testSetDeposited() public {
        deposit(user, token, depositor, 2);
        vm.prank(owner);
        reserve.setDeposited(token, 3);
        assertDeposited(token, 3, "after setting deposited");
        assertReserveBalance(token, 2, "after setting deposited");
    }

    function testRejectNotOwnerForceSettingDeposited() public {
        vm.prank(user);
        vm.expectRevert(ERROR_NOT_OWNER);
        reserve.setDeposited(token, 2);
    }

    function testForceWithdraw() public {
        deposit(user, token, depositor, 1);
        forceWithdraw(owner, token, noPlugin, depositor, 1);
    }

    function testForceWithdrawFromPlugin() public {
        setPlugin(owner, token, plugin1);
        deposit(user, token, depositor, 3);
        assertDeposited(token, 3, "before force withdrawal");
        assertPluginDeposited(plugin1, token, 3);
        assertPluginBalance(plugin1, token, 3);
        address beneficiary = address(0x1234);

        vm.prank(owner);
        reserve.forceWithdraw(token, plugin1, beneficiary, 2);

        assertEq(token.balanceOf(beneficiary), 2, "Invalid beneficiary balance");
        assertDeposited(token, 3, "after force withdrawal");
        assertPluginDeposited(plugin1, token, 1);
        assertPluginBalance(plugin1, token, 1);
    }

    function testForceWithdrawFromUnsetPlugin() public {
        token.transfer(address(plugin1), 3);
        plugin1.afterDeposition(token, 3);
        assertPluginDeposited(plugin1, token, 3);
        assertPluginBalance(plugin1, token, 3);
        address beneficiary = address(0x1234);

        vm.prank(owner);
        reserve.forceWithdraw(token, plugin1, beneficiary, 2);

        assertEq(token.balanceOf(beneficiary), 2, "Invalid beneficiary balance");
        assertPluginDeposited(plugin1, token, 1);
        assertPluginBalance(plugin1, token, 1);
    }

    function testRejectNotOwnerForceWithdrawing() public {
        deposit(user, token, depositor, 1);
        assertForceWithdrawReverts(user, token, noPlugin, depositor, 1, ERROR_NOT_OWNER);
        assertForceWithdrawReverts(nonUser, token, noPlugin, depositor, 1, ERROR_NOT_OWNER);
    }

    function testForceWithdrawOverDeposited() public {
        deposit(user, token, depositor, 1);
        token.transfer(address(reserve), 1);
        forceWithdraw(owner, token, noPlugin, depositor, 2);
    }

    function testTokensDontMix() public {
        uint256 tokenBalance = token.balanceOf(depositor);

        deposit(user, token, depositor, 1);

        string memory details = "of the other token after token deposit";
        assertUserBalance(otherToken, depositor, 2, details);
        assertDeposited(otherToken, 0, details);
        assertReserveBalance(otherToken, 0, details);

        deposit(user, otherToken, depositor, 2);

        details = "of token after the other token deposit";
        assertUserBalance(token, depositor, tokenBalance - 1, details);
        assertDeposited(token, 1, details);
        assertReserveBalance(token, 1, details);

        withdraw(user, token, depositor, 1);

        details = "of the other token after token withdrawal";
        assertUserBalance(otherToken, depositor, 0, details);
        assertDeposited(otherToken, 2, details);
        assertReserveBalance(otherToken, 2, details);

        withdraw(user, otherToken, depositor, 2);

        details = "of token after the other token withdrawal";
        assertUserBalance(token, depositor, tokenBalance, details);
        assertDeposited(token, 0, details);
        assertReserveBalance(token, 0, details);
    }

    function testTokensDontMixBetweenPlugins() public {
        setPlugin(owner, otherToken, plugin1);

        deposit(user, token, depositor, 3);
        deposit(user, otherToken, depositor, 2);

        assertDeposited(token, 3, "after deposit");
        assertReserveBalance(token, 3, "after deposit");
        assertPluginDeposited(plugin1, token, 0);
        assertPluginBalance(plugin1, token, 0);

        assertDeposited(otherToken, 2, "after deposit");
        assertReserveBalance(otherToken, 0, "after deposit");
        assertPluginDeposited(plugin1, otherToken, 2);
        assertPluginBalance(plugin1, otherToken, 2);

        withdraw(user, token, depositor, 1);
        withdraw(user, otherToken, depositor, 1);

        assertDeposited(token, 2, "after withdraw");
        assertReserveBalance(token, 2, "after withdraw");
        assertPluginDeposited(plugin1, token, 0);
        assertPluginBalance(plugin1, token, 0);

        assertDeposited(otherToken, 1, "after withdraw");
        assertReserveBalance(otherToken, 0, "after withdraw");
        assertPluginDeposited(plugin1, otherToken, 1);
        assertPluginBalance(plugin1, otherToken, 1);
    }
}
