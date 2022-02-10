// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;
import "ds-test/test.sol";

import {ERC20Reserve} from "../ERC20Reserve.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20ReserveUser {
    ERC20Reserve public reserve;

    function setReserve(ERC20Reserve reserve_) public {
        reserve = reserve_;
    }

    function approveReserve(IERC20 token, uint256 amt) public {
        token.approve(address(reserve), amt);
    }

    function withdraw(IERC20 token, uint256 amt) public {
        reserve.withdraw(token, amt);
    }

    function deposit(IERC20 token, uint256 amt) public {
        reserve.deposit(token, amt);
    }

    function forceWithdraw(IERC20 token, uint256 amt) public {
        reserve.forceWithdraw(token, amt);
    }

    function addUser(address user) public {
        reserve.addUser(user);
    }

    function removeUser(address user) public {
        reserve.removeUser(user);
    }
}

contract ERC20ReserveTest is DSTest {
    ERC20Reserve public reserve;
    ERC20ReserveUser public user;
    ERC20ReserveUser public nonUser;
    ERC20ReserveUser public owner;
    IERC20 public token;

    string public constant ERROR_NOT_USER = "Reserve: caller is not the user";
    string public constant ERROR_NOT_OWNER = "Ownable: caller is not the owner";
    string public constant ERROR_WITHDRAWAL_BALANCE = "Reserve: withdrawal over balance";

    function setUp() public {
        user = new ERC20ReserveUser();
        nonUser = new ERC20ReserveUser();
        owner = new ERC20ReserveUser();
        reserve = new ERC20Reserve(address(owner));

        owner.setReserve(reserve);
        user.setReserve(reserve);
        nonUser.setReserve(reserve);
        owner.addUser(address(user));

        token = new ERC20PresetFixedSupply("token", "token", 30, address(this));
        token.transfer(address(user), 10);
        token.transfer(address(nonUser), 10);
    }

    function deposit(
        ERC20ReserveUser forUser,
        IERC20 forToken,
        uint256 amt
    ) public {
        uint256 withdrawable = reserve.withdrawable(forToken);
        uint256 reserveBalance = forToken.balanceOf(address(reserve));
        uint256 userBalance = forToken.balanceOf(address(forUser));
        forUser.approveReserve(forToken, amt);

        forUser.deposit(forToken, amt);

        string memory details = "after deposit";
        assertUserBalance(forToken, forUser, userBalance - amt, details);
        assertWithdrawable(forToken, withdrawable + amt, details);
        assertReserveBalance(forToken, reserveBalance + amt, details);
    }

    function assertDepositReverts(
        ERC20ReserveUser forUser,
        IERC20 forToken,
        uint256 amt,
        string memory expectedReason
    ) public {
        forUser.approveReserve(forToken, amt);
        try forUser.deposit(forToken, amt) {
            assertTrue(false, "Deposit hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid deposit revert reason");
        }
        forUser.approveReserve(forToken, 0);
    }

    function withdraw(
        ERC20ReserveUser forUser,
        IERC20 forToken,
        uint256 amt
    ) public {
        uint256 withdrawable = reserve.withdrawable(forToken);
        uint256 reserveBalance = forToken.balanceOf(address(reserve));
        uint256 userBalance = forToken.balanceOf(address(forUser));

        forUser.withdraw(forToken, amt);

        string memory details = "after withdrawal";
        assertUserBalance(forToken, forUser, userBalance + amt, details);
        assertWithdrawable(forToken, withdrawable - amt, details);
        assertReserveBalance(forToken, reserveBalance - amt, details);
    }

    function assertWithdrawReverts(
        ERC20ReserveUser forUser,
        IERC20 forToken,
        uint256 amt,
        string memory expectedReason
    ) public {
        try forUser.withdraw(forToken, amt) {
            assertTrue(false, "Withdraw hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid withdrawal revert reason");
        }
    }

    function forceWithdraw(
        ERC20ReserveUser forUser,
        IERC20 forToken,
        uint256 amt
    ) public {
        uint256 withdrawable = reserve.withdrawable(forToken);
        uint256 reserveBalance = forToken.balanceOf(address(reserve));
        uint256 userBalance = forToken.balanceOf(address(forUser));

        forUser.forceWithdraw(forToken, amt);

        string memory details = "after force withdrawal";
        assertUserBalance(forToken, forUser, userBalance + amt, details);
        assertWithdrawable(forToken, withdrawable, details);
        assertReserveBalance(forToken, reserveBalance - amt, details);
    }

    function assertForceWithdrawReverts(
        ERC20ReserveUser forUser,
        IERC20 forToken,
        uint256 amt,
        string memory expectedReason
    ) public {
        try forUser.forceWithdraw(forToken, amt) {
            assertTrue(false, "Force withdraw hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid force withdrawal revert reason");
        }
    }

    function assertUserBalance(
        IERC20 forToken,
        ERC20ReserveUser forUser,
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

    function addUser(ERC20ReserveUser currOwner, ERC20ReserveUser addedUser) public {
        address userAddr = address(addedUser);
        currOwner.addUser(userAddr);
        assertTrue(reserve.isUser(userAddr), "User not added");
    }

    function assertAddUserReverts(
        ERC20ReserveUser currOwner,
        ERC20ReserveUser addedUser,
        string memory expectedReason
    ) public {
        try currOwner.addUser(address(addedUser)) {
            assertTrue(false, "AddUser hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid addUser revert reason");
        }
    }

    function removeUser(ERC20ReserveUser currOwner, ERC20ReserveUser removedUser) public {
        address userAddr = address(removedUser);
        currOwner.removeUser(userAddr);
        assertTrue(!reserve.isUser(userAddr), "User not removed");
    }

    function assertRemoveUserReverts(
        ERC20ReserveUser currOwner,
        ERC20ReserveUser removedUser,
        string memory expectedReason
    ) public {
        try currOwner.removeUser(address(removedUser)) {
            assertTrue(false, "RemoveUser hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, expectedReason, "Invalid removeUser revert reason");
        }
    }

    function testUserDepositsAndWithdraws() public {
        deposit(user, token, 1);
        withdraw(user, token, 1);
    }

    function testRejectsWithdrawalOverBalance() public {
        deposit(user, token, 1);
        assertWithdrawReverts(user, token, 2, ERROR_WITHDRAWAL_BALANCE);
    }

    function testRejectsNonUserDepositing() public {
        assertDepositReverts(owner, token, 1, ERROR_NOT_USER);
        assertDepositReverts(nonUser, token, 1, ERROR_NOT_USER);
    }

    function testRejectsNonUserWithdrawing() public {
        deposit(user, token, 1);
        assertWithdrawReverts(owner, token, 1, ERROR_NOT_USER);
        assertWithdrawReverts(nonUser, token, 1, ERROR_NOT_USER);
    }

    function testAddUser() public {
        addUser(owner, nonUser);
        deposit(nonUser, token, 1);
        withdraw(nonUser, token, 1);
    }

    function testRejectNotOwnerAddingUser() public {
        assertAddUserReverts(user, nonUser, ERROR_NOT_OWNER);
        assertAddUserReverts(nonUser, nonUser, ERROR_NOT_OWNER);
    }

    function testRemoveUser() public {
        deposit(user, token, 1);
        removeUser(owner, user);
        assertDepositReverts(user, token, 1, ERROR_NOT_USER);
        assertWithdrawReverts(user, token, 1, ERROR_NOT_USER);
    }

    function testRejectNotOwnerRemovingUser() public {
        assertRemoveUserReverts(user, user, ERROR_NOT_OWNER);
        assertRemoveUserReverts(nonUser, user, ERROR_NOT_OWNER);
    }

    function testForceWithdraw() public {
        deposit(user, token, 1);
        forceWithdraw(owner, token, 1);
    }

    function testRejectNotOwnerForceWithdrawing() public {
        deposit(user, token, 1);
        assertForceWithdrawReverts(user, token, 1, ERROR_NOT_OWNER);
        assertForceWithdrawReverts(nonUser, token, 1, ERROR_NOT_OWNER);
    }

    function testForceWithdrawOverWithdrawable() public {
        deposit(user, token, 1);
        token.transfer(address(reserve), 1);
        forceWithdraw(owner, token, 2);
    }

    function testTokensDontMix() public {
        IERC20 otherToken = new ERC20PresetFixedSupply("other", "other", 2, address(user));
        uint256 tokenBalance = token.balanceOf(address(user));

        deposit(user, token, 1);

        string memory details = "of the other token after token deposit";
        assertUserBalance(otherToken, user, 2, details);
        assertWithdrawable(otherToken, 0, details);
        assertReserveBalance(otherToken, 0, details);

        deposit(user, otherToken, 2);

        details = "of token after the other token deposit";
        assertUserBalance(token, user, tokenBalance - 1, details);
        assertWithdrawable(token, 1, details);
        assertReserveBalance(token, 1, details);

        withdraw(user, token, 1);

        details = "of the other token after token withdrawal";
        assertUserBalance(otherToken, user, 0, details);
        assertWithdrawable(otherToken, 2, details);
        assertReserveBalance(otherToken, 2, details);

        withdraw(user, otherToken, 2);

        details = "of token after the other token withdrawal";
        assertUserBalance(token, user, tokenBalance, details);
        assertWithdrawable(token, 0, details);
        assertReserveBalance(token, 0, details);
    }
}
