//SPDX-License-Identifier: ISC
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./Rad.sol";

struct User {
    address addr;
    bytes32 linkId;
}

contract RadicleRegistry {
    Rad private immutable rad;
    IERC20 private immutable dai;

    uint256 public constant REGISTRATION_FEE = 1e12;

    mapping(string => User) public users;
    mapping(bytes32 => string) public usersByLinkId;
    mapping(string => mapping(string => bytes32)) public projects;

    constructor(address _rad, address _dai) public {
        rad = Rad(_rad);
        dai = IERC20(_dai);
    }

    event UserRegistered(address account, string name, bytes32 linkId);

    function registerUserDai(string calldata name, bytes32 linkId) external {
        dai.transferFrom(msg.sender, address(this), REGISTRATION_FEE);

        require(users[name].addr == address(0), "user exists");
        require(bytes(usersByLinkId[linkId]).length == 0, "Link ID exists");

        users[name] = User({addr: msg.sender, linkId: linkId});
        usersByLinkId[linkId] = name;
        emit UserRegistered(msg.sender, name, linkId);
    }

    function registerProject(
        string calldata userName,
        string calldata projectName,
        bytes32 linkId
    ) external {
        address userAddr = users[userName].addr;
        require(msg.sender == userAddr, "not authorized");
        require(projects[userName][projectName] == "", "project exists");

        projects[userName][projectName] = linkId;
    }
}
