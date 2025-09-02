// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IAxelarGasService} from "axelar/interfaces/IAxelarGasService.sol";
import {IAxelarGMPGateway} from "axelar/interfaces/IAxelarGMPGateway.sol";
import {AddressToString} from "axelar/libs/AddressString.sol";
import {GovernorProposal} from "script/utils/Governor.sol";
import {AxelarBridgedGovernor, Call} from "src/BridgedGovernor.sol";

IAxelarGMPGateway constant ETHEREUM_GATEWAY =
    IAxelarGMPGateway(0x4F4495243837681061C4743b74B3eEdf548D56A5);
IAxelarGasService constant ETHEREUM_GAS_SERVICE =
    IAxelarGasService(0x2d5d7d31F671F86C782533cc367F14109a082712);

using GovernorProposalAxelar for GovernorProposal;

library GovernorProposalAxelar {
    function pushCallSendAxelarGovernorMessage(
        GovernorProposal memory proposal,
        uint256 fee,
        string memory governorChain,
        AxelarBridgedGovernor governor,
        AxelarBridgedGovernor.Message memory message
    ) internal view returns (GovernorProposal memory) {
        string memory governorStr = AddressToString.toString(address(governor));
        bytes memory payload = abi.encode(message);
        if (fee > 0) {
            address sender = proposal.governor.timelock();
            proposal.pushCall(
                address(ETHEREUM_GAS_SERVICE),
                fee,
                abi.encodeCall(
                    IAxelarGasService.payNativeGasForContractCall,
                    (sender, governorChain, governorStr, payload, sender)
                )
            );
        }
        return proposal.pushCall(
            address(ETHEREUM_GATEWAY),
            abi.encodeCall(IAxelarGMPGateway.callContract, (governorChain, governorStr, payload))
        );
    }
}
