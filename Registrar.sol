// SPDX-License-Identifier: GPL-3.0-only
// solhint-disable no-empty-blocks
pragma solidity ^0.7.5;

import "@ensdomains/ens/contracts/ENS.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

contract Registrar {
    /// The ENS registry.
    ENS public immutable ens;

    /// The price oracle.
    address public oracleAddress;

    /// The Rad/Eth exchange.
    address public exchangeAddress;

    /// The Radicle ERC20 token.
    ERC20Burnable public immutable rad;

    /// The namehash of the node, eg. namehash("radicle.eth").
    bytes32 public immutable domain;

    /// Registration fee in *USD*.
    uint256 public registrationFeeUsd = 10;

    /// Registration fee in *Radicle* (uRads).
    uint256 public registrationFeeRad = 1e18;

    /// The contract admin who can set fees.
    address public admin;

    /// @notice A name was registered.
    event NameRegistered(bytes32 indexed label, address indexed owner);

    /// Protects admin-only functions.
    modifier adminOnly {
        require(msg.sender == admin, "Only the admin can perform this action");
        _;
    }

    constructor(
        ENS _ens,
        bytes32 domainNameHash,
        address _oracleAddress,
        address _exchangeAddress,
        ERC20Burnable _rad,
        address adminAddress
    ) {
        ens = _ens;
        oracleAddress = _oracleAddress;
        exchangeAddress = _exchangeAddress;
        rad = _rad;
        domain = domainNameHash;
        admin = adminAddress;
    }

    /// Register a subdomain using ether.
    function registerEth(string memory, address) public payable {
        revert("Registrar::registerEth: Registration using ETH is not yet available");
    }

    /// Register a subdomain using radicle tokens.
    function registerRad(string memory name, address owner) public {
        uint256 fee = registrationFeeRad;

        require(rad.balanceOf(msg.sender) >= fee, "Transaction includes registration fee");
        require(valid(name), "Name must be valid");

        _register(keccak256(bytes(name)), owner);

        rad.burnFrom(msg.sender, fee);
    }

    function _register(bytes32 label, address owner) private {
        bytes32 node = namehash(domain, label);

        require(!ens.recordExists(node), "Registrar::_register: name must be available");

        ens.setSubnodeOwner(domain, label, owner);

        emit NameRegistered(label, owner);
    }

    /// Check whether a name is valid.
    function valid(string memory name) public pure returns (bool) {
        uint256 len = bytes(name).length;
        return len > 0 && len <= 32;
    }

    /// Check whether a name is available for registration.
    function available(string memory name) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        bytes32 node = namehash(domain, label);

        return valid(name) && !ens.recordExists(node);
    }

    /// Get the "namehash" of a label.
    function namehash(bytes32 parent, bytes32 label) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(parent, label));
    }

    /// Registration fee in ether.
    function registrationFeeEth() public pure returns (uint256) {
        revert("Registrar::registrationFeeEth: Registration using ETH is not yet available");
    }

    // ADMIN FUNCTIONS

    /// Set the USD registration fee.
    function setUsdRegistrationFee(uint256 fee) public adminOnly {
        registrationFeeUsd = fee;
    }

    /// Set the radicle registration fee.
    function setRadRegistrationFee(uint256 fee) public adminOnly {
        registrationFeeRad = fee;
    }

    /// Set the price oracle.
    function setPriceOracle(address _oracleAddress) public adminOnly {
        require(
            oracleAddress != address(0),
            "Registrar::setPriceOracle: oracle address cannot be zero"
        );
        oracleAddress = _oracleAddress;
    }

    /// Set the exchange.
    function setExchange(address _exchangeAddress) public adminOnly {
        require(
            exchangeAddress != address(0),
            "Registrar::setExchange: exchange address cannot be zero"
        );
        exchangeAddress = _exchangeAddress;
    }

    /// Set the owner of the domain.
    function setDomainOwner(address newOwner) public adminOnly {
        ens.setOwner(domain, newOwner);
    }

    /// Set a new admin
    function setAdmin(address _admin) public adminOnly {
        admin = _admin;
    }
}
