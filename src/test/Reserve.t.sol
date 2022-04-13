// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;
import "ds-test/test.sol";

import {Reserve} from "../Reserve.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ReserveUser {
    Reserve public reserve;

    function setReserve(Reserve reserve_) public {
        reserve = reserve_;
    }

    function approveReserve(IERC20 token, uint256 amt) public {
        token.approve(address(reserve), amt);
    }

    function withdraw(
        IERC20 token,
        ReserveUser to,
        uint256 amt
    ) public {
        reserve.withdraw(token, address(to), amt);
    }

    function deposit(
        IERC20 token,
        ReserveUser from,
        uint256 amt
    ) public {
        reserve.deposit(token, address(from), amt);
    }

    function forceWithdraw(
        IERC20 token,
        ReserveUser to,
        uint256 amt
    ) public {
        reserve.forceWithdraw(token, address(to), amt);
    }

    function addUser(address user) public {
        reserve.addUser(user);
    }

    function removeUser(address user) public {
        reserve.removeUser(user);
    }
}

contract ReserveTest is DSTest {
    Reserve public reserve;
    ReserveUser public user;
    ReserveUser public nonUser;
    ReserveUser public owner;
    ReserveUser public depositor;
    IERC20 public token;

    string public constant ERROR_NOT_USER = "Reserve: caller is not the user";
    string public constant ERROR_NOT_OWNER = "Ownable: caller is not the owner";
    string public constant ERROR_WITHDRAWAL_BALANCE = "Reserve: withdrawal over balance";

    function setUp() public {
        user = new ReserveUser();
        nonUser = new ReserveUser();
        owner = new ReserveUser();
        depositor = new ReserveUser();
        reserve = new Reserve(address(owner));

        owner.setReserve(reserve);
        user.setReserve(reserve);
        nonUser.setReserve(reserve);
        depositor.setReserve(reserve);
        owner.addUser(address(user));

        token = new ERC20PresetFixedSupply("token", "token", 30, address(this));
        token.transfer(address(depositor), 10);
    }

    function deposit(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser from,
        uint256 amt
    ) public {
        uint256 withdrawable = reserve.withdrawable(forToken);
        uint256 reserveBalance = forToken.balanceOf(address(reserve));
        uint256 userBalance = forToken.balanceOf(address(from));
        from.approveReserve(forToken, amt);

        reserveUser.deposit(forToken, from, amt);

        string memory details = "after deposit";
        assertUserBalance(forToken, from, userBalance - amt, details);
        assertWithdrawable(forToken, withdrawable + amt, details);
        assertReserveBalance(forToken, reserveBalance + amt, details);
    }

    function assertDepositReverts(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser from,
        uint256 amt,
        string memory expectedReason
    ) public {
        from.approveReserve(forToken, amt);
        try reserveUser.deposit(forToken, from, amt) {
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
        uint256 withdrawable = reserve.withdrawable(forToken);
        uint256 reserveBalance = forToken.balanceOf(address(reserve));
        uint256 userBalance = forToken.balanceOf(address(to));

        reserveUser.withdraw(forToken, to, amt);

        string memory details = "after withdrawal";
        assertUserBalance(forToken, to, userBalance + amt, details);
        assertWithdrawable(forToken, withdrawable - amt, details);
        assertReserveBalance(forToken, reserveBalance - amt, details);
    }

    function assertWithdrawReverts(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser to,
        uint256 amt,
        string memory expectedReason
    ) public {
        try reserveUser.withdraw(forToken, to, amt) {
            assertTrue(false, "Withdraw hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid withdrawal revert reason");
        }
    }

    function forceWithdraw(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser to,
        uint256 amt
    ) public {
        uint256 withdrawable = reserve.withdrawable(forToken);
        uint256 reserveBalance = forToken.balanceOf(address(reserve));
        uint256 userBalance = forToken.balanceOf(address(to));

        reserveUser.forceWithdraw(forToken, to, amt);

        string memory details = "after force withdrawal";
        assertUserBalance(forToken, to, userBalance + amt, details);
        assertWithdrawable(forToken, withdrawable, details);
        assertReserveBalance(forToken, reserveBalance - amt, details);
    }

    function assertForceWithdrawReverts(
        ReserveUser reserveUser,
        IERC20 forToken,
        ReserveUser to,
        uint256 amt,
        string memory expectedReason
    ) public {
        try reserveUser.forceWithdraw(forToken, to, amt) {
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

    function assertWithdrawable(
        IERC20 forToken,
        uint256 expected,
        string memory details
    ) public {
        uint256 actual = reserve.withdrawable(forToken);
        assertEq(actual, expected, concat("Invalid withdrawable ", details));
    }

    function assertReserveBalance(
        IERC20 forToken,
        uint256 expected,
        string memory details
    ) public {
        uint256 actual = forToken.balanceOf(address(reserve));
        assertEq(actual, expected, concat("Invalid reserve ", details));
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

    function testUserDepositsAndWithdraws() public {
        deposit(user, token, depositor, 1);
        withdraw(user, token, depositor, 1);
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

    function testForceWithdraw() public {
        deposit(user, token, depositor, 1);
        forceWithdraw(owner, token, depositor, 1);
    }

    function testRejectNotOwnerForceWithdrawing() public {
        deposit(user, token, depositor, 1);
        assertForceWithdrawReverts(user, token, depositor, 1, ERROR_NOT_OWNER);
        assertForceWithdrawReverts(nonUser, token, depositor, 1, ERROR_NOT_OWNER);
    }

    function testForceWithdrawOverWithdrawable() public {
        deposit(user, token, depositor, 1);
        token.transfer(address(reserve), 1);
        forceWithdraw(owner, token, depositor, 2);
    }

    function testTokensDontMix() public {
        IERC20 otherToken = new ERC20PresetFixedSupply("other", "other", 2, address(depositor));
        uint256 tokenBalance = token.balanceOf(address(depositor));

        deposit(user, token, depositor, 1);

        string memory details = "of the other token after token deposit";
        assertUserBalance(otherToken, depositor, 2, details);
        assertWithdrawable(otherToken, 0, details);
        assertReserveBalance(otherToken, 0, details);

        deposit(user, otherToken, depositor, 2);

        details = "of token after the other token deposit";
        assertUserBalance(token, depositor, tokenBalance - 1, details);
        assertWithdrawable(token, 1, details);
        assertReserveBalance(token, 1, details);

        withdraw(user, token, depositor, 1);

        details = "of the other token after token withdrawal";
        assertUserBalance(otherToken, depositor, 0, details);
        assertWithdrawable(otherToken, 2, details);
        assertReserveBalance(otherToken, 2, details);

        withdraw(user, otherToken, depositor, 2);

        details = "of token after the other token withdrawal";
        assertUserBalance(token, depositor, tokenBalance, details);
        assertWithdrawable(token, 0, details);
        assertReserveBalance(token, 0, details);
    }
}
