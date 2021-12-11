// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;
import "ds-test/test.sol";

import {ERC20Reserve} from "../ERC20Reserve.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20ReserveTest is DSTest {
    IERC20 public erc20;
    address public self;

    function setUp() public {
        self = address(this);
        erc20 = new ERC20PresetFixedSupply("test", "test", 100 ether, self);
    }

    function depositWithdraw(ERC20Reserve reserve) public {
        address reserve_ = address(reserve);
        erc20.approve(reserve_, type(uint256).max);
        uint256 depositAmt = 10 ether;
        reserve.deposit(depositAmt);
        assertEq(erc20.balanceOf(reserve_), depositAmt);
        assertEq(reserve.balance(), depositAmt);

        uint256 preBalance = erc20.balanceOf(self);

        uint256 withdrawAmt = 2 ether;
        reserve.withdraw(withdrawAmt);
        assertEq(erc20.balanceOf(reserve_), depositAmt - withdrawAmt);
        assertEq(reserve.balance(), depositAmt - withdrawAmt);
        assertEq(preBalance + withdrawAmt, erc20.balanceOf(self));
    }

    function testDepositAndWithdraw() public {
        ERC20Reserve reserve = new ERC20Reserve(erc20, self, self);
        depositWithdraw(reserve);
    }

    function testNotOwner() public {
        address owner = address(0xA);
        ERC20Reserve reserve = new ERC20Reserve(erc20, owner, self);
        depositWithdraw(reserve);
    }

    function testFailNotUserButOwner() public {
        address user = address(0xA);
        ERC20Reserve reserve = new ERC20Reserve(erc20, self, user);
        depositWithdraw(reserve);
    }

    function testChangeUser() public {
        address user = address(0xA);
        ERC20Reserve reserve = new ERC20Reserve(erc20, self, user);
        reserve.setUser(self);
        depositWithdraw(reserve);
    }

    function testFailNoPermissions() public {
        ERC20Reserve reserve = new ERC20Reserve(erc20, address(0xA), address(0xA));
        depositWithdraw(reserve);
    }
}
