// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

import "@ensdomains/ens/contracts/ENS.sol";

import "./PriceOracle.sol";
import "./Exchange.sol";
import "./Rad.sol";

contract Registrar {
    /// The ENS registry.
    ENS public immutable ens;

    /// The price oracle.
    PriceOracle public immutable oracle;

    /// The Rad/Eth exchange.
    Exchange public immutable exchange;

    /// The Rad ERC20 token.
    Rad public immutable rad;

    /// The namehash of the domain this registrar owns(eg. radicle.eth).
    bytes32 public immutable rootNode;

    /// Registration fee in *USD*.
    uint256 public constant REGISTRATION_FEE_USD = 10;

    /// Registration fee in *Radicle*.
    uint256 public constant REGISTRATION_FEE_RAD = 1;

    constructor(
        address ensAddress,
        bytes32 _rootNode,
        address oracleAddress,
        address exchangeAddress,
        address radAddress
    ) {
        ens = ENS(ensAddress);
        oracle = PriceOracle(oracleAddress);
        exchange = Exchange(exchangeAddress);
        rad = Rad(radAddress);
        rootNode = _rootNode;
    }

    function initialize() public {
        oracle.updatePrices();
    }

    /// Register a subdomain using ether.
    function registerEth(string memory name, address owner) public payable {
        // Make sure the oracle has up-to-date pricing information.
        oracle.updatePrices();

        uint256 fee = registrationFee();

        require(msg.value >= fee, "Transaction includes registration fee");
        require(valid(name), "Name must be valid");

        _register(keccak256(bytes(name)), owner);

        // Swap n' burn.
        uint256 swapped = exchange.swapEthForRad{value: fee}(address(this));
        require(swapped > 0, "Must burn a positive amount of Rad");

        rad.burn(swapped);

        // Return change.
        if (msg.value > fee) {
            msg.sender.transfer(msg.value - fee);
        }
    }

    /// Register a subdomain using radicle tokens.
    function registerRad(string memory name, address owner) public payable {
        uint256 fee = REGISTRATION_FEE_RAD;

        require(rad.balanceOf(msg.sender) >= fee, "Transaction includes registration fee");
        require(valid(name), "Name must be valid");

        _register(keccak256(bytes(name)), owner);

        rad.burn(fee);
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
    function namehash(bytes32 parent, bytes32 label) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(parent, label));
    }

    /// Registration fee in `wei`.
    function registrationFee() public view returns (uint256) {
        // Convert USD fee into ETH.
        return oracle.consultUsdEth(REGISTRATION_FEE_USD);
    }
}
