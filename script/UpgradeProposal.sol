// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {
    AxelarBridgedGovernor,
    GovernorProposalAxelar,
    IAxelarGMPGateway
} from "script/utils/Axelar.sol";
import {
    Call,
    Calls,
    GovernorProposal,
    GovernorProposalImpl,
    RADWORKS_GOVERNOR,
    RADWORKS_TIMELOCK
} from "script/utils/Governor.sol";
import {
    ETHEREUM_EID,
    ETHEREUM_ENDPOINT,
    GovernorProposalLZ,
    LZBridgedGovernor
} from "script/utils/LayerZero.sol";
import {Origin} from "src/BridgedGovernor.sol";
import {RepoDriver} from "src/RepoDriver.sol";
import {console, Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";

using Calls for Call[];
using GovernorProposalAxelar for GovernorProposal;
using GovernorProposalLZ for GovernorProposal;

address constant ETHEREUM_CALLER = 0x60F25ac5F289Dc7F640f948521d486C964A248e5;
RepoDriver constant ETHEREUM_REPO_DRIVER =
    RepoDriver(payable(0x770023d55D09A9C110694827F1a6B32D5c2b373E));

LZBridgedGovernor constant LZ_BRIDGED_GOVERNOR =
    LZBridgedGovernor(payable(0x07791819560264627e9c4B1308e546667E83B564));
AxelarBridgedGovernor constant AXELAR_BRIDGED_GOVERNOR =
    AxelarBridgedGovernor(payable(0xE9B15C572EB7Ba2E2856cc5eFaAb8fe1d0e34116));

address constant CALLER = 0xd6Ab8e72dE3742d45AdF108fAa112Cd232718828;
RepoDriver constant REPO_DRIVER = RepoDriver(payable(0xe75f56B26857cAe06b455Bfc9481593Ae0FB4257));

// Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
uint32 constant METIS_EID = 30151;
uint32 constant OPTIMISM_EID = 30111;

bytes32 constant ETHEREUM_CHAIN = "ethereum";
bytes32 constant OPTIMISM_CHAIN = "optimism";
bytes32 constant METIS_CHAIN = "metis";
bytes32 constant FILECOIN_CHAIN = "filecoin";

address constant LIT_ORACLE = 0xEbaeEfa413B80eCC62723aDF59dE17e06f2DF8CE;

function createMetisUpgradeMessage() pure returns (LZBridgedGovernor.Message memory) {
    return LZBridgedGovernor.Message({
        nonce: 2,
        value: 0,
        calls: Calls.create()
            .push(address(REPO_DRIVER), abi.encodeCall(RepoDriver.updateLitOracle, (LIT_ORACLE)))
    });
}

contract TestProposalOnMetis is Script, StdAssertions {
    function run() public {
        assertNotEq(REPO_DRIVER.litOracle(), LIT_ORACLE);

        vm.prank(ETHEREUM_ENDPOINT); // The endpoint has the same address as on Ethereum
        LZ_BRIDGED_GOVERNOR.lzReceive(
            Origin({
                srcEid: ETHEREUM_EID, sender: bytes32(uint256(uint160(RADWORKS_TIMELOCK))), nonce: 0
            }),
            0,
            abi.encode(createMetisUpgradeMessage()),
            address(0),
            ""
        );

        assertEq(REPO_DRIVER.litOracle(), LIT_ORACLE);
    }
}

function createOptimismUpgradeMessage() pure returns (LZBridgedGovernor.Message memory) {
    return LZBridgedGovernor.Message({
        nonce: 2,
        value: 0,
        calls: Calls.create()
            .push(address(REPO_DRIVER), abi.encodeCall(RepoDriver.updateLitOracle, (LIT_ORACLE)))
    });
}

contract TestProposalOnOptimism is Script, StdAssertions {
    function run() public {
        assertNotEq(REPO_DRIVER.litOracle(), LIT_ORACLE);

        vm.prank(ETHEREUM_ENDPOINT); // The endpoint has the same address as on Ethereum
        LZ_BRIDGED_GOVERNOR.lzReceive(
            Origin({
                srcEid: ETHEREUM_EID, sender: bytes32(uint256(uint160(RADWORKS_TIMELOCK))), nonce: 0
            }),
            0,
            abi.encode(createOptimismUpgradeMessage()),
            address(0),
            ""
        );

        assertEq(REPO_DRIVER.litOracle(), LIT_ORACLE);
    }
}

function createFilecoinUpgradeMessage() pure returns (AxelarBridgedGovernor.Message memory) {
    return AxelarBridgedGovernor.Message({
        nonce: 2,
        calls: Calls.create()
            .push(address(REPO_DRIVER), abi.encodeCall(RepoDriver.updateLitOracle, (LIT_ORACLE)))
    });
}

contract TestProposalOnFilecoin is Script, StdAssertions {
    function run() public {
        assertNotEq(REPO_DRIVER.litOracle(), LIT_ORACLE);

        vm.mockCall(
            0xe432150cce91c13a887f7D836923d5597adD8E31,
            IAxelarGMPGateway.validateContractCall.selector,
            abi.encode(true)
        );
        AXELAR_BRIDGED_GOVERNOR.execute(
            0,
            "Ethereum",
            "0x8dA8f82d2BbDd896822de723F55D6EdF416130ba",
            abi.encode(createFilecoinUpgradeMessage())
        );

        assertEq(REPO_DRIVER.litOracle(), LIT_ORACLE);
    }
}

function createProposal() view returns (GovernorProposal memory proposal) {
    proposal = GovernorProposalImpl.create(
        RADWORKS_GOVERNOR, "[RGP - 30] - Migrate Drips oracle to Lit Chipotle"
    );

    // Upgrade the Ethereum contracts
    proposal.pushCall(
        address(ETHEREUM_REPO_DRIVER), abi.encodeCall(RepoDriver.updateLitOracle, (LIT_ORACLE))
    );

    // Send a message upgrading the Metis contracts
    proposal.pushCallSendLZGovernorMessage({
        fee: 0.01 ether,
        governorEid: METIS_EID,
        governor: LZ_BRIDGED_GOVERNOR,
        gas: 500_000,
        message: createMetisUpgradeMessage()
    });

    // Send a message upgrading the Optimism contracts
    proposal.pushCallSendLZGovernorMessage({
        fee: 0.01 ether,
        governorEid: OPTIMISM_EID,
        governor: LZ_BRIDGED_GOVERNOR,
        gas: 500_000,
        message: createOptimismUpgradeMessage()
    });

    // Send a message upgrading the Filecoin contracts
    proposal.pushCallSendAxelarGovernorMessage({
        fee: 0.01 ether,
        governorChain: "Filecoin",
        governor: AXELAR_BRIDGED_GOVERNOR,
        message: createFilecoinUpgradeMessage()
    });
}

contract TestProposalOnEthereum is Script, StdAssertions {
    function run() public {
        assertNotEq(ETHEREUM_REPO_DRIVER.litOracle(), LIT_ORACLE);

        createProposal().testExecute();

        assertEq(ETHEREUM_REPO_DRIVER.litOracle(), LIT_ORACLE);
    }
}

contract Propose is Script {
    function run() public {
        vm.startBroadcast();
        uint256 proposalId = createProposal().propose();
        console.log("Proposed proposal", proposalId);
    }
}

contract Queue is Script {
    function run() public {
        vm.startBroadcast();
        uint256 proposalId = createProposal().queue();
        console.log("Queued proposal", proposalId);
    }
}

contract Execute is Script {
    function run() public {
        vm.startBroadcast();
        uint256 proposalId = createProposal().execute();
        console.log("Executed proposal", proposalId);
    }
}
