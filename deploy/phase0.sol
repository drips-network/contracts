// spdx-license-identifier: gpl-3.0-only
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

    address public immutable tokensHolder;
    uint256 public immutable timelockDelay;
    address public immutable governorGuardian;
    ENS public immutable ens;
    bytes32 public immutable namehash;
    string public label;

    constructor(
        address _tokensHolder,
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

        RadicleToken _token = new RadicleToken(_tokensHolder);
        Timelock _timelock = new Timelock(govAddr, _timelockDelay);
        Governor _governor = new Governor(address(_timelock), address(_token), _governorGuardian);
        require(address(_governor) == govAddr, "Governor deployed under an unexpected address");
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

        tokensHolder = _tokensHolder;
        timelockDelay = _timelockDelay;
        governorGuardian = _governorGuardian;
        ens = _ens;
        namehash = _namehash;
        label = _label;
    }
}
