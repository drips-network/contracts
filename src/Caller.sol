// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {ICaller, Call} from "./ICaller.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {ECDSA, EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";
import {ERC2771Context} from "openzeppelin-contracts/metatx/ERC2771Context.sol";
import {EnumerableSet} from "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

using EnumerableSet for EnumerableSet.AddressSet;

/// @notice The implementation of `ICaller`, see its documentation for more details.
contract Caller is ICaller, EIP712("Caller", "1"), ERC2771Context(address(this)) {
    /// @inheritdoc ICaller
    uint256 public constant MAX_NONCE_INCREASE = 10 ** 9;
    /// @inheritdoc ICaller
    mapping(address sender => uint256) public nonce;

    string internal constant CALL_SIGNED_TYPE_NAME = "CallSigned("
        "address sender,address target,bytes data,uint256 value,uint256 nonce,uint256 deadline)";
    bytes32 internal immutable callSignedTypeHash = keccak256(bytes(CALL_SIGNED_TYPE_NAME));
    /// @notice Each sender's set of address authorized to make calls on its behalf.
    mapping(address sender => AddressSetClearable) internal _authorized;

    /// @notice A clearable set of addresses.
    /// @param clears Number of performed clears. Increase to clear.
    /// @param addressSets The set of addresses.
    /// Always use the set under the key equal to the current value of `clears`.
    struct AddressSetClearable {
        uint256 clears;
        mapping(uint256 clears => EnumerableSet.AddressSet) addressSets;
    }

    /// @inheritdoc ICaller
    function authorize(address user) public {
        address sender = _msgSender();
        require(_getAuthorizedSet(sender).add(user), "Address already is authorized");
        emit Authorized(sender, user);
    }

    /// @inheritdoc ICaller
    function unauthorize(address user) public {
        address sender = _msgSender();
        require(_getAuthorizedSet(sender).remove(user), "Address is not authorized");
        emit Unauthorized(sender, user);
    }

    /// @inheritdoc ICaller
    function unauthorizeAll() public {
        address sender = _msgSender();
        _authorized[sender].clears++;
        emit UnauthorizedAll(sender);
    }

    /// @inheritdoc ICaller
    function isAuthorized(address sender, address user) public view returns (bool authorized) {
        return _getAuthorizedSet(sender).contains(user);
    }

    /// @inheritdoc ICaller
    function allAuthorized(address sender) public view returns (address[] memory authorized) {
        return _getAuthorizedSet(sender).values();
    }

    /// @inheritdoc ICaller
    function callAs(address sender, address target, bytes calldata data)
        public
        payable
        returns (bytes memory returnData)
    {
        address authorized = _msgSender();
        require(isAuthorized(sender, authorized), "Not authorized");
        emit CalledAs(sender, authorized);
        return _call(sender, target, data, msg.value);
    }

    /// @inheritdoc ICaller
    function callSigned(
        address sender,
        address target,
        bytes calldata data,
        uint256 deadline,
        bytes32 r,
        bytes32 vs
    ) public payable returns (bytes memory returnData) {
        // slither-disable-next-line timestamp
        require(block.timestamp <= deadline, "Execution deadline expired");
        uint256 currNonce = nonce[sender]++;
        bytes32 executeHash = keccak256(
            abi.encode(
                callSignedTypeHash, sender, target, keccak256(data), msg.value, currNonce, deadline
            )
        );
        address signer = ECDSA.recover(_hashTypedDataV4(executeHash), r, vs);
        require(signer == sender, "Invalid signature");
        emit CalledSigned(sender, currNonce);
        return _call(sender, target, data, msg.value);
    }

    /// @inheritdoc ICaller
    function setNonce(uint256 newNonce) public {
        address sender = _msgSender();
        uint256 currNonce = nonce[sender];
        require(newNonce > currNonce, "Nonce not increased");
        require(newNonce <= currNonce + MAX_NONCE_INCREASE, "Nonce increased by too much");
        nonce[sender] = newNonce;
        emit NonceSet(sender, newNonce);
    }

    /// @inheritdoc ICaller
    function callBatched(Call[] calldata calls)
        public
        payable
        returns (bytes[] memory returnData)
    {
        returnData = new bytes[](calls.length);
        address sender = _msgSender();
        for (uint256 i = 0; i < calls.length; i++) {
            Call calldata call = calls[i];
            returnData[i] = _call(sender, call.target, call.data, call.value);
        }
    }

    /// @notice Gets the set of addresses authorized to make calls on behalf of `sender`.
    /// @param sender The authorizing address.
    /// @return authorizedSet The set of authorized addresses.
    function _getAuthorizedSet(address sender)
        internal
        view
        returns (EnumerableSet.AddressSet storage authorizedSet)
    {
        AddressSetClearable storage authorized = _authorized[sender];
        return authorized.addressSets[authorized.clears];
    }

    /// @notice Makes a call on behalf of the `sender`.
    /// Reverts if the call reverts or the called address is not a smart contract.
    /// @param sender The sender to be set as the message sender of the call as per ERC-2771.
    /// @param target The called address.
    /// @param data The calldata to be used for the call.
    /// @param value The value of the call.
    /// @return returnData The data returned by the call.
    function _call(address sender, address target, bytes calldata data, uint256 value)
        internal
        returns (bytes memory returnData)
    {
        // Encode the message sender as per ERC-2771
        return Address.functionCallWithValue(target, bytes.concat(data, bytes20(sender)), value);
    }
}
