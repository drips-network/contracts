// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.12;

import "@ensdomains/ens/contracts/ENS.sol";

import "./PriceOracle.sol";

contract Registrar {
    /// The ENS registry.
    ENS public ens;

    /// The price oracle.
    PriceOracle public oracle;

    /// The namehash of the domain this registrar owns(eg. radicle.eth).
    bytes32 public rootNode;

    /// Registration fee in *USD*.
    uint256 public constant REGISTRATION_FEE = 10;

    constructor(
        address ensAddress,
        bytes32 _rootNode,
        address oracleAddress
    ) public {
        ens = ENS(ensAddress);
        oracle = PriceOracle(oracleAddress);
        rootNode = _rootNode;
    }

    /// Register a subdomain.
    function register(string memory name, address owner) public payable {
        uint256 fee = registrationFee();

        require(msg.value >= fee, "Transaction includes registration fee");
        require(valid(name), "Name must be valid");

        _register(keccak256(bytes(name)), owner);

        // Return change.
        if (msg.value > fee) {
            msg.sender.transfer(msg.value - fee);
        }
    }

    function _register(bytes32 label, address owner) private {
        bytes32 node = namehash(rootNode, label);

        require(!ens.recordExists(node), "Record must not already exist");

        ens.setSubnodeOwner(rootNode, label, owner);
    }

    /// Check whether a name is valid.
    function valid(string memory name) public pure returns (bool) {
        // FIXME(cloudhead): This is only correct for ASCII.
        return bytes(name).length >= 3;
    }

    /// Check whether a name is available for registration.
    function available(string memory name) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        bytes32 node = namehash(rootNode, label);

        return valid(name) && !ens.recordExists(node);
    }

    /// Get the "namehash" of a label.
    function namehash(bytes32 parent, bytes32 label)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(parent, label));
    }

    /// Registration fee in `wei`.
    function registrationFee() public view returns (uint256) {
        int256 ethUsd = oracle.latestPrice();

        require(ethUsd > 0, "Price of ether must be positive");

        return REGISTRATION_FEE / uint256(ethUsd);
    }
}
