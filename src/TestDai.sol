// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.7.5;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract Dai is ERC20 {
    bytes32 private immutable domainSeparator;
    bytes32 private immutable typehash;
    mapping(address => uint256) public nonces;

    constructor() ERC20("DAI Stablecoin", "DAI") {
        // TODO replace with `block.chainid` after upgrade to Solidity 0.8
        uint256 chainId;
        // solhint-disable no-inline-assembly
        assembly {
            chainId := chainid()
        }
        domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name())),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
        typehash = keccak256(
            "Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)"
        );
        _mint(msg.sender, 10**9 * 10**18); // 1 billion DAI, 18 decimals
    }

    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 message = keccak256(abi.encode(typehash, holder, spender, nonce, expiry, allowed));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, message));
        address signer = ecrecover(digest, v, r, s);
        require(holder == signer, "Invalid signature");
        require(nonce == nonces[holder]++, "Invalid nonce");
        require(expiry == 0 || expiry > block.timestamp, "Signature expired");
        uint256 amount = allowed ? type(uint256).max : 0;
        _approve(holder, spender, amount);
    }
}
