// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NativeTokenUnwrapper} from "src/NativeTokenUnwrapper.sol";
import {DummyWrappedNativeToken, IWrappedNativeToken} from "src/IWrappedNativeToken.sol";

contract NativeTokenUnwrapperTest is Test {
    IWrappedNativeToken internal wrappedNativeToken;
    NativeTokenUnwrapper internal nativeTokenUnwrapper;
    address payable immutable recipient = payable(address(0x1234));

    function setUp() public {
        wrappedNativeToken = new DummyWrappedNativeToken();
        nativeTokenUnwrapper = new NativeTokenUnwrapper(wrappedNativeToken);
    }

    function unwrap(uint256 amount) public {
        wrappedNativeToken.deposit{value: amount}();
        wrappedNativeToken.transfer(address(nativeTokenUnwrapper), amount);

        assertUnwrapperBalance(amount);
        assertRecipientBalance(0);

        uint256 unwrappedAmount = nativeTokenUnwrapper.unwrap(recipient);

        assertEq(unwrappedAmount, amount, "Invalid unwrapped amount");
        assertUnwrapperBalance(0);
        assertRecipientBalance(amount);
    }

    function assertRecipientBalance(uint256 expectedBalance) internal {
        assertEq(recipient.balance, expectedBalance, "Invalid recipient balance");
    }

    function assertUnwrapperBalance(uint256 expectedBalance) internal {
        uint256 actualBalance = wrappedNativeToken.balanceOf(address(nativeTokenUnwrapper));
        assertEq(actualBalance, expectedBalance, "Invalid unwrapper balance");
    }

    function testUnwrap() public {
        unwrap(123);
    }

    function testUnwrapZero() public {
        unwrap(0);
    }
}
