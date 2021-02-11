// SPDX-License-Identifier: GPL-3.0-only
// solhint-disable no-empty-blocks
pragma solidity ^0.7.5;

import "@ensdomains/ens/contracts/ENS.sol";
import "./Governance/RadicleToken.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// commitments are kept in a seperate contract to allow the state to be reused
// between different versions of the registrar
contract Commitments {
    address public owner;
    modifier auth {
        require(msg.sender == owner, "Commitments: unauthorized");
        _;
    }
    event SetOwner(address usr);

    /// Mapping from the commitment to the block number in which the commitment was made
    mapping(bytes32 => uint256) public commited;

    constructor() {
        owner = msg.sender;
    }

    function setOwner(address usr) external auth {
        owner = usr;
        emit SetOwner(usr);
    }

    function commit(bytes32 commitment) external auth {
        commited[commitment] = block.number;
    }
}

contract Registrar {
    // --- DATA ---

    /// The ENS registry.
    ENS public immutable ens;

    /// The Radicle ERC20 token.
    RadicleToken public immutable rad;

    /// @notice EIP-712 name for this contract
    string public constant NAME = "Registrar";

    /// The commitment storage contract
    Commitments public immutable commitments = new Commitments();

    /// The namehash of the `eth` TLD in the ENS registry, eg. namehash("eth").
    bytes32 public constant ETH_NODE = keccak256(abi.encodePacked(bytes32(0), keccak256("eth")));

    /// The namehash of the node in the `eth` TLD, eg. namehash("radicle.eth").
    bytes32 public immutable radNode;

    /// The token ID for the node in the `eth` TLD, eg. sha256("radicle").
    uint256 public immutable tokenId;

    /// The minimum number of blocks that must have passed between a commitment and name registration
    uint256 public minCommitmentAge;

    /// Registration fee in *Radicle* (uRads).
    uint256 public registrationFeeRad = 1e18;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant COMMIT_TYPEHASH =
        keccak256("Commit(bytes32 commitment,uint256 nonce,uint256 expiry,uint256 submissionFee)");

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    // --- LOGS ---

    /// @notice A name was registered.
    event NameRegistered(string indexed name, bytes32 indexed label, address indexed owner);

    /// @notice A commitment was made
    event CommitmentMade(bytes32 commitment, uint256 blockNumber);

    /// @notice The contract admin was changed
    event AdminChanged(address newAdmin);

    /// @notice The registration fee was changed
    event RegistrationRadFeeChanged(uint256 amt);

    /// @notice The ownership of the domain was changed
    event DomainOwnershipChanged(address newOwner);

    /// @notice The resolver changed
    event ResolverChanged(address resolver);

    /// @notice The ttl changed
    event TTLChanged(uint64 amt);

    /// @notice The minimum age for a commitment was changed
    event MinCommitmentAgeChanged(uint256 amt);

    // --- AUTH ---

    /// The contract admin who can set fees.
    address public admin;

    /// Protects admin-only functions.
    modifier adminOnly {
        require(msg.sender == admin, "Registrar: only the admin can perform this action");
        _;
    }

    // --- INIT ---

    constructor(
        ENS _ens,
        RadicleToken _rad,
        address _admin,
        uint256 _minCommitmentAge,
        bytes32 _radNode,
        uint256 _tokenId
    ) {
        ens = _ens;
        rad = _rad;
        admin = _admin;
        minCommitmentAge = _minCommitmentAge;
        radNode = _radNode;
        tokenId = _tokenId;
    }

    // --- USER FACING METHODS ---

    /// Commit to a future name registration
    function commit(bytes32 commitment) public {
        _commit(msg.sender, commitment);
    }

    /// Commit to a future name and submit permit in the same transaction
    function commitWithPermit(
        bytes32 commitment,
        address owner,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        rad.permit(owner, address(this), value, deadline, v, r, s);
        _commit(msg.sender, commitment);
    }

    /// Commit to a future name with a 712-signed message
    function commitBySig(
        bytes32 commitment,
        uint256 nonce,
        uint256 expiry,
        uint256 submissionFee,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator =
            keccak256(
                abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), getChainId(), address(this))
            );
        bytes32 structHash =
            keccak256(abi.encode(COMMIT_TYPEHASH, commitment, nonce, expiry, submissionFee));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Registrar::commitBySig: invalid signature");
        require(nonce == nonces[signatory]++, "Registrar::commitBySig: invalid nonce");
        require(block.timestamp <= expiry, "Registrar::commitBySig: signature expired");
        rad.transferFrom(signatory, msg.sender, submissionFee);
        _commit(signatory, commitment);
    }

    /// Commit to a future name with a 712-signed message and submit permit in the same transaction
    function commitBySigWithPermit(
        bytes32 commitment,
        uint256 nonce,
        uint256 expiry,
        uint256 submissionFee,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address owner,
        uint256 value,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS
    ) public {
        rad.permit(owner, address(this), value, deadline, permitV, permitR, permitS);
        commitBySig(commitment, nonce, expiry, submissionFee, v, r, s);
    }

    function _commit(address payer, bytes32 commitment) internal {
        require(commitments.commited(commitment) == 0, "Registrar::commit: already commited");

        rad.burnFrom(payer, registrationFeeRad);
        commitments.commit(commitment);

        emit CommitmentMade(commitment, block.number);
    }

    /// Register a subdomain
    function register(
        string calldata name,
        address owner,
        uint256 salt
    ) external {
        bytes32 label = keccak256(bytes(name));
        bytes32 commitment = keccak256(abi.encodePacked(name, owner, salt));
        uint256 commited = commitments.commited(commitment);

        require(valid(name), "Registrar::register: invalid name");
        require(available(name), "Registrar::register: name has already been registered");
        require(commited != 0, "Registrar::register: must commit before registration");
        require(
            commited + minCommitmentAge < block.number,
            "Registrar::register: commitment too new"
        );

        ens.setSubnodeRecord(radNode, label, owner, ens.resolver(radNode), ens.ttl(radNode));

        emit NameRegistered(name, label, owner);
    }

    /// Check whether a name is valid.
    function valid(string memory name) public pure returns (bool) {
        uint256 len = bytes(name).length;
        return len > 0 && len <= 32;
    }

    /// Check whether a name is available for registration.
    function available(string memory name) public view returns (bool) {
        bytes32 label = keccak256(bytes(name));
        bytes32 node = namehash(radNode, label);
        return ens.owner(node) == address(0);
    }

    /// Get the "namehash" of a label.
    function namehash(bytes32 parent, bytes32 label) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(parent, label));
    }

    // --- ADMIN METHODS ---

    /// Set the owner of the domain.
    function setDomainOwner(address newOwner) public adminOnly {
        IERC721 ethRegistrar = IERC721(ens.owner(ETH_NODE));

        ens.setOwner(radNode, newOwner);
        ethRegistrar.transferFrom(address(this), newOwner, tokenId);
        commitments.setOwner(newOwner);

        emit DomainOwnershipChanged(newOwner);
    }

    /// Set a new resolver for radicle.eth.
    function setDomainResolver(address resolver) public adminOnly {
        ens.setResolver(radNode, resolver);
        emit ResolverChanged(resolver);
    }

    /// Set a new ttl for radicle.eth
    function setDomainTTL(uint64 ttl) public adminOnly {
        ens.setTTL(radNode, ttl);
        emit TTLChanged(ttl);
    }

    /// Set the minimum commitment age
    function setMinCommitmentAge(uint256 amt) public adminOnly {
        minCommitmentAge = amt;
        emit MinCommitmentAgeChanged(amt);
    }

    /// Set a new registration fee
    function setRadRegistrationFee(uint256 amt) public adminOnly {
        registrationFeeRad = amt;
        emit RegistrationRadFeeChanged(amt);
    }

    /// Set a new admin
    function setAdmin(address newAdmin) public adminOnly {
        admin = newAdmin;
        emit AdminChanged(newAdmin);
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        // solhint-disable no-inline-assembly
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
