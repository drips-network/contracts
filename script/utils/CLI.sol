// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {RADWORKS} from "script/utils/Radworks.sol";

library DeployCLI {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function finalRun() internal view returns (bool) {
        return VM.envOr("FINAL_RUN", false);
    }

    function requireChainId(uint256 chainId) internal view {
        require(
            block.chainid == chainId,
            string.concat("The script must be run on the chain with ID ", VM.toString(chainId))
        );
    }

    function requireWallet() internal view {
        if (!finalRun()) return;
        require(
            msg.sender == 0x7dCaCF417BA662840DcD2A35b67f55911815dD7e,
            "The final run must be done with the deployer wallet"
        );
    }

    function salt() internal view returns (bytes32) {
        if (finalRun()) {
            return bytes32("DripsV2Final");
        }
        string memory saltString = VM.envOr("SALT", string(""));
        if (bytes(saltString).length == 0) {
            saltString = string.concat("Test", VM.toString(VM.getNonce(msg.sender)));
        }
        return bytes32(bytes(saltString));
    }

    function radworks() internal view returns (address) {
        return finalRun() ? RADWORKS : VM.envOr("RADWORKS", msg.sender);
    }

    function checkConfig(uint256 chainId)
        internal
        view
        returns (bytes32 salt_, address radworks_)
    {
        requireChainId(chainId);
        requireWallet();
        return (salt(), radworks());
    }
}
