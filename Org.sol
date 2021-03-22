// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

contract Org {
    /// A project anchor under an org.
    struct Project {
        bytes32 rev; // Project revision hash
        bytes32 hash; // Project state (eg. HEAD commit) hash
    }

    /// Org owner/admin.
    address public owner;

    /// Index of projects under this org, keyed by project identifier.
    /// The values represent offsets into the `projects` array.
    mapping(bytes32 => Project) public projects;

    // ~ Events ~

    /// A project was anchored.
    event ProjectAnchored(bytes32 id, bytes32 rev, bytes32 hash);

    /// A project was removed.
    event ProjectRemoved(bytes32 id);

    /// The org owner changed.
    event OwnerChanged(address newOwner);

    /// Construct a new org instance, by providing an owner address.
    constructor(address _owner) {
        owner = _owner;
    }

    /// Check whether a project exists.
    function projectExists(bytes32 id) public view returns (bool) {
        return projects[id].hash != bytes32(0);
    }

    // ~ All functions below should use the `ownerOnly` modifier ~

    /// Functions that can only be called by the contract owner.
    modifier ownerOnly {
        require(msg.sender == owner, "Only the org owner can perform this action");
        _;
    }

    /// Set the org owner.
    function setOwner(address newOwner) public ownerOnly {
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    /// Anchor a project state on chain, by providing a revision and hash. This method
    /// should be used for adding new projects to the org, as well as updating
    /// existing ones.
    function anchorProject(
        bytes32 id,
        bytes32 rev,
        bytes32 hash
    ) public ownerOnly {
        require(hash != bytes32(0), "The project hash must not be the zero hash");

        Project storage proj = projects[id];

        proj.rev = rev;
        proj.hash = hash;

        emit ProjectAnchored(id, rev, hash);
    }

    /// Remove a project from the org.
    function removeProject(bytes32 id) public ownerOnly {
        delete projects[id];
        emit ProjectRemoved(id);
    }
}
