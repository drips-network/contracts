// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "@ensdomains/ens/contracts/ENS.sol";

/// This registrar is taken from the ENSBaseRegistrar.
contract DummyEnsRegistry is ENS {
    struct Record {
        address owner;
        address resolver;
        uint64 ttl;
    }

    mapping(bytes32 => Record) private records;
    mapping(address => mapping(address => bool)) private operators;

    modifier authorised(bytes32 node) {
        address owner = records[node].owner;
        require(
            owner == msg.sender || operators[owner][msg.sender],
            "Only the owner is allowed to perform this operation"
        );
        _;
    }

    constructor() public {
        records[0x0].owner = msg.sender;
    }

    function setRecord(
        bytes32 node,
        address _owner,
        address _resolver,
        uint64 _ttl
    ) external override {
        setOwner(node, _owner);
        _setResolverAndTTL(node, _resolver, _ttl);
    }

    function setSubnodeRecord(
        bytes32 node,
        bytes32 label,
        address _owner,
        address _resolver,
        uint64 _ttl
    ) external override {
        bytes32 subnode = setSubnodeOwner(node, label, _owner);
        _setResolverAndTTL(subnode, _resolver, _ttl);
    }

    function setOwner(bytes32 node, address _owner)
        public
        override
        authorised(node)
    {
        _setOwner(node, _owner);
        emit Transfer(node, _owner);
    }

    function setSubnodeOwner(
        bytes32 node,
        bytes32 label,
        address _owner
    ) public override authorised(node) returns (bytes32) {
        bytes32 subnode = keccak256(abi.encodePacked(node, label));
        _setOwner(subnode, _owner);
        emit NewOwner(node, label, _owner);
        return subnode;
    }

    function setResolver(bytes32 node, address _resolver)
        public
        override
        authorised(node)
    {
        emit NewResolver(node, _resolver);
        records[node].resolver = _resolver;
    }

    function setTTL(bytes32 node, uint64 _ttl)
        public
        override
        authorised(node)
    {
        emit NewTTL(node, _ttl);
        records[node].ttl = _ttl;
    }

    function setApprovalForAll(address operator, bool approved)
        external
        override
    {
        operators[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function owner(bytes32 node) public override view returns (address) {
        address addr = records[node].owner;
        if (addr == address(this)) {
            return address(0x0);
        }

        return addr;
    }

    function resolver(bytes32 node) public override view returns (address) {
        return records[node].resolver;
    }

    function ttl(bytes32 node) public override view returns (uint64) {
        return records[node].ttl;
    }

    function recordExists(bytes32 node) public override view returns (bool) {
        return records[node].owner != address(0x0);
    }

    function isApprovedForAll(address _owner, address operator)
        external
        override
        view
        returns (bool)
    {
        return operators[_owner][operator];
    }

    function _setOwner(bytes32 node, address _owner) internal {
        records[node].owner = _owner;
    }

    function _setResolverAndTTL(
        bytes32 node,
        address _resolver,
        uint64 _ttl
    ) internal {
        if (_resolver != records[node].resolver) {
            records[node].resolver = _resolver;
            emit NewResolver(node, _resolver);
        }

        if (_ttl != records[node].ttl) {
            records[node].ttl = _ttl;
            emit NewTTL(node, _ttl);
        }
    }
}
