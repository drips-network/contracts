// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {GovernorVotesComp} from "openzeppelin-contracts/governance/extensions/GovernorVotesComp.sol";
import {IGovernorTimelock} from "openzeppelin-contracts/governance/extensions/IGovernorTimelock.sol";
import {ICompoundTimelock} from "openzeppelin-contracts/vendor/compound/ICompoundTimelock.sol";
import {Call} from "src/BridgedGovernor.sol";
import {Vm} from "forge-std/Vm.sol";

IGovernorTimelock constant RADWORKS_GOVERNOR =
    IGovernorTimelock(0xD64D01D04498bFc60f04178e0B62a757C5048212);
address constant RADWORKS_TIMELOCK = 0x8dA8f82d2BbDd896822de723F55D6EdF416130ba;

function requireRunOnEthereum() view {
    require(block.chainid == 1, "Must be run on Ethereum");
}

struct GovernorProposal {
    IGovernorTimelock governor;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
}

using Calls for Call[];

library Calls {
    function create() internal pure returns (Call[] memory) {
        return new Call[](0);
    }

    function push(Call[] memory calls, address target, bytes memory data)
        internal
        pure
        returns (Call[] memory)
    {
        return calls.push(target, 0, data);
    }

    function push(Call[] memory calls, address target, uint256 value, bytes memory data)
        internal
        pure
        returns (Call[] memory newCalls)
    {
        newCalls = new Call[](calls.length + 1);
        for (uint256 i = 0; i < calls.length; i++) {
            newCalls[i] = calls[i];
        }
        newCalls[calls.length] = Call({target: target, value: value, data: data});
    }
}

using GovernorProposalImpl for GovernorProposal global;

library GovernorProposalImpl {
    function create(IGovernorTimelock governor, string memory description)
        internal
        pure
        returns (GovernorProposal memory proposal)
    {
        proposal.governor = governor;
        proposal.description = description;
    }

    function pushCall(GovernorProposal memory proposal, address target, bytes memory data)
        internal
        pure
        returns (GovernorProposal memory)
    {
        return proposal.pushCall(target, 0, data);
    }

    function pushCall(
        GovernorProposal memory proposal,
        address target,
        uint256 value,
        bytes memory data
    ) internal pure returns (GovernorProposal memory) {
        uint256 oldLength = proposal.targets.length;

        address[] memory targets = new address[](oldLength + 1);
        uint256[] memory values = new uint256[](oldLength + 1);
        bytes[] memory calldatas = new bytes[](oldLength + 1);

        for (uint256 i = 0; i < oldLength; i++) {
            targets[i] = proposal.targets[i];
            values[i] = proposal.values[i];
            calldatas[i] = proposal.calldatas[i];
        }

        targets[oldLength] = target;
        values[oldLength] = value;
        calldatas[oldLength] = data;

        proposal.targets = targets;
        proposal.values = values;
        proposal.calldatas = calldatas;

        return proposal;
    }

    function propose(GovernorProposal memory proposal) internal returns (uint256 proposalId) {
        return proposal.governor.propose(
            proposal.targets, proposal.values, proposal.calldatas, proposal.description
        );
    }

    function castVoteFor(GovernorProposal memory proposal) internal returns (uint256 proposalId) {
        proposalId = proposal.governor.hashProposal(
            proposal.targets,
            proposal.values,
            proposal.calldatas,
            keccak256(bytes(proposal.description))
        );
        return proposal.governor.castVote(proposalId, 1);
    }

    function queue(GovernorProposal memory proposal) internal returns (uint256 proposalId) {
        return proposal.governor.queue(
            proposal.targets,
            proposal.values,
            proposal.calldatas,
            keccak256(bytes(proposal.description))
        );
    }

    function execute(GovernorProposal memory proposal) internal returns (uint256 proposalId) {
        return proposal.governor.execute(
            proposal.targets,
            proposal.values,
            proposal.calldatas,
            keccak256(bytes(proposal.description))
        );
    }

    function testExecute(GovernorProposal memory proposal) internal {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        address voter = address(bytes20("Voter"));
        address timelock = proposal.governor.timelock();

        vm.startPrank(timelock);
        GovernorVotesComp(payable(address(proposal.governor))).token().delegate(voter);
        vm.stopPrank();

        vm.startPrank(voter);

        vm.roll(vm.getBlockNumber() + 1);
        proposal.propose();

        vm.roll(vm.getBlockNumber() + proposal.governor.votingDelay() + 1);
        proposal.castVoteFor();

        vm.stopPrank();

        vm.roll(vm.getBlockNumber() + proposal.governor.votingPeriod());
        proposal.queue();

        vm.warp(vm.getBlockTimestamp() + ICompoundTimelock(payable(timelock)).delay());
        proposal.execute();
    }
}
