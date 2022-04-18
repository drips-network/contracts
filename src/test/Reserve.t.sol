// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;
import "ds-test/test.sol";

import {IReservePlugin, Reserve} from "../Reserve.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ReserveUser {
    Reserve public reserve;

    function setReserve(Reserve reserve_) public {
        reserve = reserve_;
    }

    function approveReserve(IERC20 token, uint256 amt) public {
        token.approve(address(reserve), amt);
    }

    function setPlugin(IERC20 token, IReservePlugin plugin) public {
        reserve.setPlugin(token, plugin);
    }

    function deposit(
        IERC20 token,
        address from,
        uint256 amt
    ) public {
        reserve.deposit(token, from, amt);
    }

    function withdraw(
        IERC20 token,
        address to,
        uint256 amt
    ) public {
        reserve.withdraw(token, to, amt);
    }

    function forceWithdraw(
        IERC20 token,
        IReservePlugin plugin,
        address to,
        uint256 amt
    ) public {
        reserve.forceWithdraw(token, plugin, to, amt);
    }

    function setDeposited(IERC20 token, uint256 amt) public {
        reserve.setDeposited(token, amt);
    }

    function addUser(address user) public {
        reserve.addUser(user);
    }

    function removeUser(address user) public {
        reserve.removeUser(user);
    }
}

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

contract ReserveTest is DSTest {
    Reserve public reserve;
    IReservePlugin public noPlugin;
    TestReservePlugin public plugin1;
    TestReservePlugin public plugin2;
    ReserveUser public user;
    ReserveUser public nonUser;
    ReserveUser public owner;
    ReserveUser public depositor;
    IERC20 public token;
    IERC20 public otherToken;

    string public constant ERROR_NOT_USER = "Reserve: caller is not the user";
    string public constant ERROR_NOT_OWNER = "Ownable: caller is not the owner";
    string public constant ERROR_DEPOSIT_SELF = "Reserve: deposition from self";
    string public constant ERROR_WITHDRAWAL_BALANCE = "Reserve: withdrawal over balance";

    function setUp() public {
        user = new ReserveUser();
        nonUser = new ReserveUser();
        owner = new ReserveUser();
        depositor = new ReserveUser();
        reserve = new Reserve(address(owner));
        noPlugin = reserve.NO_PLUGIN();
        plugin1 = new TestReservePlugin();
        plugin2 = new TestReservePlugin();

        owner.setReserve(reserve);
        user.setReserve(reserve);
        nonUser.setReserve(reserve);
        depositor.setReserve(reserve);
        owner.addUser(address(user));

        token = new ERC20PresetFixedSupply("token", "token", 30, address(this));
        otherToken = new ERC20PresetFixedSupply("otherToken", "otherToken", 30, address(this));
        token.transfer(address(depositor), 10);
        otherToken.transfer(address(depositor), 2);
    }

    function setPlugin(
        ReserveUser reserveUser,
        IERC20 forToken,
        IReservePlugin plugin
    ) public {
        reserveUser.setPlugin(forToken, plugin);
        assertEq(address(reserve.plugins(forToken)), address(plugin), "New plugin not set");
    }

    function deposit(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser from,
        uint256 amt
    ) public {
        uint256 deposited = reserve.deposited(forToken);
        uint256 userBalance = forToken.balanceOf(address(from));
        from.approveReserve(forToken, amt);

        reserveUser.deposit(forToken, address(from), amt);

        string memory details = "after deposit";
        assertUserBalance(forToken, from, userBalance - amt, details);
        assertDeposited(forToken, deposited + amt, details);
    }

    function assertDepositReverts(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser from,
        uint256 amt,
        string memory expectedReason
    ) public {
        from.approveReserve(forToken, amt);
        try reserveUser.deposit(forToken, address(from), amt) {
            assertTrue(false, "Deposit hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid deposit revert reason");
        }
        from.approveReserve(forToken, 0);
    }

    function withdraw(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser to,
        uint256 amt
    ) public {
        uint256 deposited = reserve.deposited(forToken);
        uint256 userBalance = forToken.balanceOf(address(to));

        reserveUser.withdraw(forToken, address(to), amt);

        string memory details = "after withdrawal";
        assertUserBalance(forToken, to, userBalance + amt, details);
        assertDeposited(forToken, deposited - amt, details);
    }

    function assertWithdrawReverts(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser to,
        uint256 amt,
        string memory expectedReason
    ) public {
        try reserveUser.withdraw(forToken, address(to), amt) {
            assertTrue(false, "Withdraw hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid withdrawal revert reason");
        }
    }

    function forceWithdraw(
        ReserveUser reserveUser,
        IERC20 forToken,
        IReservePlugin plugin,
        ReserveUser to,
        uint256 amt
    ) public {
        uint256 deposited = reserve.deposited(forToken);
        uint256 reserveBalance = forToken.balanceOf(address(reserve));
        uint256 userBalance = forToken.balanceOf(address(to));

        reserveUser.forceWithdraw(forToken, plugin, address(to), amt);

        string memory details = "after force withdrawal";
        assertUserBalance(forToken, to, userBalance + amt, details);
        assertDeposited(forToken, deposited, details);
        assertReserveBalance(forToken, reserveBalance - amt, details);
    }

    function assertForceWithdrawReverts(
        ReserveUser reserveUser,
        IERC20 forToken,
        IReservePlugin plugin,
        ReserveUser to,
        uint256 amt,
        string memory expectedReason
    ) public {
        try reserveUser.forceWithdraw(forToken, plugin, address(to), amt) {
            assertTrue(false, "Force withdraw hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid force withdrawal revert reason");
        }
    }

    function assertUserBalance(
        IERC20 forToken,
        ReserveUser forUser,
        uint256 expected,
        string memory details
    ) public {
        uint256 actual = forToken.balanceOf(address(forUser));
        assertEq(actual, expected, concat("Invalid user balance ", details));
    }

    function assertDeposited(
        IERC20 forToken,
        uint256 expected,
        string memory details
    ) public {
        uint256 actual = reserve.deposited(forToken);
        assertEq(actual, expected, concat("Invalid deposited ", details));
    }

    function assertReserveBalance(
        IERC20 forToken,
        uint256 expected,
        string memory details
    ) public {
        uint256 actual = forToken.balanceOf(address(reserve));
        assertEq(actual, expected, concat("Invalid reserve ", details));
    }

    function assertPluginDeposited(
        TestReservePlugin plugin,
        IERC20 forToken,
        uint256 expected
    ) public {
        assertEq(plugin.deposited(forToken), expected, "Invalid plugin deposited");
    }

    function assertPluginBalance(
        TestReservePlugin plugin,
        IERC20 forToken,
        uint256 expected
    ) public {
        assertEq(forToken.balanceOf(address(plugin)), expected, "Invalid plugin balance");
    }

    function concat(string memory str1, string memory str2) public pure returns (string memory) {
        return string(bytes.concat(bytes(str1), bytes(str2)));
    }

    function addUser(ReserveUser currOwner, ReserveUser addedUser) public {
        address userAddr = address(addedUser);
        currOwner.addUser(userAddr);
        assertTrue(reserve.isUser(userAddr), "User not added");
    }

    function assertAddUserReverts(
        ReserveUser currOwner,
        ReserveUser addedUser,
        string memory expectedReason
    ) public {
        try currOwner.addUser(address(addedUser)) {
            assertTrue(false, "AddUser hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid addUser revert reason");
        }
    }

    function removeUser(ReserveUser currOwner, ReserveUser removedUser) public {
        address userAddr = address(removedUser);
        currOwner.removeUser(userAddr);
        assertTrue(!reserve.isUser(userAddr), "User not removed");
    }

    function assertRemoveUserReverts(
        ReserveUser currOwner,
        ReserveUser removedUser,
        string memory expectedReason
    ) public {
        try currOwner.removeUser(address(removedUser)) {
            assertTrue(false, "RemoveUser hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid removeUser revert reason");
        }
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
        try user.setPlugin(token, plugin1) {
            assertTrue(false, "SetPlugin hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid setPlugin revert reason");
        }
    }

    function testUserDepositsAndWithdraws() public {
        deposit(user, token, depositor, 1);
        withdraw(user, token, depositor, 1);
    }

    function testDepositFromReserveReverts() public {
        token.transfer(address(reserve), 1);
        try user.deposit(token, address(reserve), 1) {
            assertTrue(false, "Deposit hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_DEPOSIT_SELF, "Invalid deposit revert reason");
        }
    }

    function testDepositFromPluginReverts() public {
        setPlugin(owner, token, plugin1);
        token.transfer(address(plugin1), 1);
        try user.deposit(token, address(plugin1), 1) {
            assertTrue(false, "Deposit hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_DEPOSIT_SELF, "Invalid deposit revert reason");
        }
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
        owner.setDeposited(token, 3);
        assertDeposited(token, 3, "after setting deposited");
        assertReserveBalance(token, 2, "after setting deposited");
    }

    function testRejectNotOwnerForceSettingDeposited() public {
        try user.setDeposited(token, 2) {
            assertTrue(false, "SetDeposited hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid setDeposited revert reason");
        }
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

        owner.forceWithdraw(token, plugin1, beneficiary, 2);

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

        owner.forceWithdraw(token, plugin1, beneficiary, 2);

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
        uint256 tokenBalance = token.balanceOf(address(depositor));

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
