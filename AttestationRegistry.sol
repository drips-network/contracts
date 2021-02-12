// spdx-license-identifier: MIT
pragma solidity ^0.7.5;

contract AttestationRegistry {
    struct Attestation {
        bytes32 id; // Holds up to a 256-bit hash
        bytes32 revision; // Holds up to a 256-bit hash
        bytes32 publicKey; // Holds an ed25519 key
        bytes1[64] signature; // Holds an ed25519 signature
    }

    /// The set of recorded attestations. Maps between an Ethereum address
    /// and an attestation.
    mapping(address => Attestation) public attestations;

    /// Create a new attestation. Overwrites any existing attestation by
    /// the sender.
    function attest(
        bytes32 id,
        bytes32 revision,
        bytes32 publicKey,
        bytes1[64] calldata signature
    ) public {
        attestations[msg.sender].id = id;
        attestations[msg.sender].revision = revision;
        attestations[msg.sender].publicKey = publicKey;
        attestations[msg.sender].signature = signature;
    }

    /// Revoke any attestation made by the sender.
    function revokeAttestation() public {
        delete attestations[msg.sender];
    }
}
