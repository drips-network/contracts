// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {ILayerZeroReceiver, Origin} from "layer-zero/interfaces/ILayerZeroReceiver.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

/// @notice Description of a call.
/// @param target The called address.
/// @param data The calldata to be used for the call.
/// @param value The value of the call.
struct Call {
    address target;
    bytes data;
    uint256 value;
}

function runCalls(Call[] memory calls) {
    for (uint256 i = 0; i < calls.length; i++) {
        Call memory call = calls[i];
        Address.functionCallWithValue(call.target, call.data, call.value);
    }
}

contract BridgedGovernor is UUPSUpgradeable, /* Initializable, */ ILayerZeroReceiver {
    address public immutable endpoint;
    uint32 public immutable ownerEid;
    bytes32 public immutable owner;

    uint64 internal _lastNonce;

    constructor(address endpoint_, uint32 ownerEid_, bytes32 owner_) {
        // slither-disable-next-line missing-zero-check
        endpoint = endpoint_;
        ownerEid = ownerEid_;
        owner = owner_;
    }

    // function initialize() public initializer {
    //     _lastNonce = 1;
    //     // Init at the endpoint
    // }

    function allowInitializePath(Origin calldata origin) public view returns (bool) {
        return origin.srcEid == ownerEid && origin.sender == owner;
    }

    function nextNonce(uint32 eid, bytes32 sender) public view returns (uint64 nextNonce_) {
        if (eid == ownerEid && sender == owner) nextNonce_ = _lastNonce + 1;
    }

    function lzReceive(
        Origin calldata origin,
        bytes32, /* guid */
        bytes calldata message,
        address, /* executor */
        bytes calldata /* extraData */
    ) public payable {
        // require(_getInitializedVersion() != 0, "Not initialized");
        require(msg.sender == endpoint, "Must be called by the endpoint");
        require(origin.srcEid == ownerEid, "Invalid message source chain");
        require(origin.sender == owner, "Invalid message sender");
        require(origin.nonce == _lastNonce + 1, "Invalid message nonce");
        // slither-disable-next-line events-maths
        _lastNonce = origin.nonce;
        runCalls(abi.decode(message, (Call[])));
        // Call[] memory calls = abi.decode(message, (Call[]));
        // for (uint256 i = 0; i < calls.length; i++) {
        //     Call memory call = calls[i];
        //     Address.functionCallWithValue(call.target, call.data, call.value);
        // }
    }

    function _authorizeUpgrade(address /* newImplementation */ ) internal view override {
        require(msg.sender == address(this), "Only upgradeable by self");
    }
}

contract BridgedGovernorProxy is ERC1967Proxy {
    constructor(BridgedGovernor logic, Call[] memory calls) ERC1967Proxy(address(logic), "") {
        runCalls(calls);
        // for (uint256 i = 0; i < calls.length; i++) {
        //     Call memory call = calls[i];
        //     Address.functionCallWithValue(call.target, call.data, call.value);
        // }
    }
}

// - Make upgradeable
// - Make initializable
// - Deploy on testnet

// The bridging cost is unknown - needs approve-and-emit
// DAO -> portal.approve(full payload)
// ??? funds L1+L2 -> portal -> LZ -> portal2 (execute)

// Portal has its own funds to pay for the bridging
// If it doesn't have enough, reverting won't burn the vote

// LZ ETH endpoint
// https://etherscan.io/address/0x1a44076050125825900e736c501f859c50fe728c#code

// The chain-chain path must have identical configurations on both sides
// onlyOwner on L1 to change the config + sends the message to L2

// What happens when a message isn't delivered?
// Each message must have a nonce included in the voted payload.
// Need a public `resend` function. May be using the owned ETH, may be accepting the caller's.

// Current executor impl: 0x1e45f27f0e96e9757cff938f2c9d697aa8279c85

// lzReceiver:
// - msg.sender is endpoint
// struct Origin {
//     uint32 srcEid; == ETH
//     bytes32 sender; == Radworks
//     uint64 nonce; == in-app tracked
// }

// - What is precrime? Nobody knows.
// - Sender without a smart contract

// L1Gov:

// // function execute(payload)

// function send(nonce, payload, chain, receiver)
//     onlyDao
//     sentDate[hash] = now + 1 day
//     if(estimate <= this.balance) then _send

// function resend(nonce, payload, chain, receiver)
//     require(sentDate[hash] <=  now)
//     require(estimate >= msg.value)
//     _send

// upgradeable (only DAO)

// DAO is approved on LZ

// L2Gov:
// function execute(nonce, payload)

// TO config just `execute` on LZEndpoint

// // function setConfig(...)
// //     require(msg.sender == this)

// upgradeable (only self)
