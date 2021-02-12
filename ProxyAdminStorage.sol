// spdx-license-identifier: MIT
pragma solidity ^0.7.5;

contract ProxyAdminStorage {
    /// Administrator for this contract
    address public admin;

    /// Pending administrator for this contract
    address public pendingAdmin;

    /// Active implementation behind this proxy
    address public implementation;

    /// Pending implementation behind this proxy
    address public pendingImplementation;
}
