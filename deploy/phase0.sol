// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

import {ENS} from "@ensdomains/ens/contracts/ENS.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import {Governor} from "../Governance/Governor.sol";
import {RadicleToken} from "../Governance/RadicleToken.sol";
import {Timelock} from "../Governance/Timelock.sol";
import {Registrar} from "../Registrar.sol";

contract Phase0 {
    RadicleToken public immutable token;
    Timelock public immutable timelock;
    Governor public immutable governor;
    Registrar public immutable registrar;

    address public immutable monadicAddr;
    address public immutable foundationAddr;
    uint256 public immutable timelockDelay;
    address public immutable governorGuardian;
    ENS public immutable ens;
    bytes32 public immutable namehash;
    string public label;

    uint256 public constant MONADIC_ALLOCATION = 32221392e18;
    uint256 public constant FOUNDATION_ALLOCATION = 13925009e18;
    uint256 public constant TREASURY_ALLOCATION = 53853599e18;

    // solhint-disable reentrancy
    constructor(
        address _monadicAddr,
        address _foundationAddr,
        uint256 _timelockDelay,
        address _governorGuardian,
        ENS _ens,
        bytes32 _namehash,
        string memory _label
    ) {
        require(
            uint160(address(this)) >> 154 != 0,
            "Factory contract address starts with 0 byte, "
            "please make any transaction and rerun deployment"
        );
        uint8 governorNonce = 3;
        bytes memory govAddrPayload = abi.encodePacked(hex"d694", address(this), governorNonce);
        address govAddr = address(uint256(keccak256(govAddrPayload)));

        RadicleToken _token = new RadicleToken(address(this));
        Timelock _timelock = new Timelock(govAddr, _timelockDelay);
        Governor _governor = new Governor(address(_timelock), address(_token), _governorGuardian);
        require(address(_governor) == govAddr, "Governor deployed under an unexpected address");

        _token.transfer(_monadicAddr, MONADIC_ALLOCATION);
        _token.transfer(_foundationAddr, FOUNDATION_ALLOCATION);
        _token.transfer(address(_timelock), TREASURY_ALLOCATION);
        require(_token.balanceOf(address(this)) == 0, "All tokens are allocated");
        require(
            MONADIC_ALLOCATION + FOUNDATION_ALLOCATION + TREASURY_ALLOCATION ==
                _token.totalSupply(),
            "All tokens are allocated"
        );

        Registrar _registrar =
            new Registrar(
                _ens,
                _token,
                address(_timelock),
                10,
                _namehash,
                uint256(keccak256(bytes(_label)))
            );

        token = _token;
        timelock = _timelock;
        governor = _governor;
        registrar = _registrar;

        monadicAddr = _monadicAddr;
        foundationAddr = _foundationAddr;
        timelockDelay = _timelockDelay;
        governorGuardian = _governorGuardian;
        ens = _ens;
        namehash = _namehash;
        label = _label;
    }
}
