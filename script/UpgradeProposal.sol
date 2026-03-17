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
    createSetConfigParam,
    ETHEREUM_EID,
    ETHEREUM_ENDPOINT,
    GovernorProposalLZ,
    LZBridgedGovernor,
    SetConfigParam
} from "script/utils/LayerZero.sol";
import {Origin} from "src/BridgedGovernor.sol";
import {ImmutableSplitsDriver} from "src/ImmutableSplitsDriver.sol";
import {IWrappedNativeToken} from "src/IWrappedNativeToken.sol";
import {RepoDriver} from "src/RepoDriver.sol";
import {NFTDriver} from "src/NFTDriver.sol";
import {console, Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {
    GovernorVotesComp
} from "openzeppelin-contracts/governance/extensions/GovernorVotesComp.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20VotesComp} from "openzeppelin-contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import {ICompoundTimelock} from "openzeppelin-contracts/vendor/compound/ICompoundTimelock.sol";

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

contract DeployLogic is Script, StdAssertions {
    function run() public {
        if (block.chainid == 1) deploy(ETHEREUM_REPO_DRIVER, ETHEREUM_CALLER, ETHEREUM_CHAIN);
        else if (block.chainid == 10) deploy(REPO_DRIVER, CALLER, OPTIMISM_CHAIN);
        else if (block.chainid == 1088) deploy(REPO_DRIVER, CALLER, METIS_CHAIN);
        else if (block.chainid == 314) deploy(REPO_DRIVER, CALLER, FILECOIN_CHAIN);
        else assertTrue(false, "Invalid chain");
    }

    function deploy(RepoDriver repoDriver, address caller, bytes32 chain) internal {
        vm.startBroadcast();
        RepoDriver newRepoDriver =
            new RepoDriver(repoDriver.drips(), caller, repoDriver.driverId(), chain);

        console.log("Chain ID:", block.chainid);
        console.log("Chain:", string(bytes.concat(chain)));
        console.log("RepoDriver logic:", address(newRepoDriver));
        console.log("----------------------------------");
        console.log("RepoDriver drips:", address(newRepoDriver.drips()));
        console.log("Current RepoDriver caller trusted:", repoDriver.isTrustedForwarder(caller));
        console.log("RepoDriver caller trusted:", newRepoDriver.isTrustedForwarder(caller));
        console.log("RepoDriver driverId:", newRepoDriver.driverId());
        console.log("RepoDriver chain:", string(bytes.concat(newRepoDriver.chain())));
    }
}

address constant LIT_ORACLE = 0x77a97dcA6A47e206E112f6F42Ef18c6f16B5e060;
bytes constant UPDATE_LIT_ORACLE_CALLDATA =
    abi.encodeCall(RepoDriver.updateLitOracle, (LIT_ORACLE));

function createMetisUpgradeMessage() pure returns (LZBridgedGovernor.Message memory) {
    return LZBridgedGovernor.Message({
        nonce: 1,
        value: 0,
        calls: Calls.create()
            .push(
                address(REPO_DRIVER),
                abi.encodeCall(
                    UUPSUpgradeable.upgradeToAndCall,
                    (0xd02fa26582E3FAd0eC9629eFFEbd94a5fC87EBCC, UPDATE_LIT_ORACLE_CALLDATA)
                )
            )
    });
}

contract TestProposalOnMetis is Script, StdAssertions {
    function run() public {
        address repoDriverDrips = address(REPO_DRIVER.drips());
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        uint32 repoDriverDriverId = REPO_DRIVER.driverId();
        uint256 accountId =
            uint256(0x000000030065667374616a61732f64726970732d746573742d7265706f2d3130);
        address repoDriverAccountOwner = REPO_DRIVER.ownerOf(accountId);
        assertNotEq(repoDriverAccountOwner, address(0));

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

        assertEq(REPO_DRIVER.implementation(), 0xd02fa26582E3FAd0eC9629eFFEbd94a5fC87EBCC);
        assertEq(address(REPO_DRIVER.drips()), repoDriverDrips);
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        assertEq(REPO_DRIVER.driverId(), repoDriverDriverId);
        assertEq(REPO_DRIVER.ownerOf(accountId), repoDriverAccountOwner);
        assertEq(REPO_DRIVER.litOracle(), LIT_ORACLE);
        assertEq(REPO_DRIVER.chain(), METIS_CHAIN);
    }
}

function createOptimismUpgradeMessage() pure returns (LZBridgedGovernor.Message memory) {
    return LZBridgedGovernor.Message({
        nonce: 1,
        value: 0,
        calls: Calls.create()
            .push(
                address(REPO_DRIVER),
                abi.encodeCall(
                    UUPSUpgradeable.upgradeToAndCall,
                    (0x2347492c38871210f7dCD2594208356bAfcC674d, UPDATE_LIT_ORACLE_CALLDATA)
                )
            )
    });
}

contract TestProposalOnOptimism is Script, StdAssertions {
    function run() public {
        address repoDriverDrips = address(REPO_DRIVER.drips());
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        uint32 repoDriverDriverId = REPO_DRIVER.driverId();
        uint256 accountId =
            uint256(0x0000000300736875747465722d6e6574776f726b2f7368757474657200000000);
        address repoDriverAccountOwner = REPO_DRIVER.ownerOf(accountId);
        assertNotEq(repoDriverAccountOwner, address(0));

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

        assertEq(REPO_DRIVER.implementation(), 0x2347492c38871210f7dCD2594208356bAfcC674d);
        assertEq(address(REPO_DRIVER.drips()), repoDriverDrips);
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        assertEq(REPO_DRIVER.driverId(), repoDriverDriverId);
        assertEq(REPO_DRIVER.ownerOf(accountId), repoDriverAccountOwner);
        assertEq(REPO_DRIVER.litOracle(), LIT_ORACLE);
        assertEq(REPO_DRIVER.chain(), OPTIMISM_CHAIN);
    }
}

function createFilecoinUpgradeMessage() pure returns (AxelarBridgedGovernor.Message memory) {
    return AxelarBridgedGovernor.Message({
        nonce: 1,
        calls: Calls.create()
            .push(
                address(REPO_DRIVER),
                abi.encodeCall(
                    UUPSUpgradeable.upgradeToAndCall,
                    (0x75A8fb92D1b437B4EEa25347304Fe52A9985aCe4, UPDATE_LIT_ORACLE_CALLDATA)
                )
            )
    });
}

contract TestProposalOnFilecoin is Script, StdAssertions {
    function run() public {
        address repoDriverDrips = address(REPO_DRIVER.drips());
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        uint32 repoDriverDriverId = REPO_DRIVER.driverId();
        uint256 accountId =
            uint256(0x000000030043454c74642f43454c2d526574726f000000000000000000000000);
        address repoDriverAccountOwner = REPO_DRIVER.ownerOf(accountId);
        assertNotEq(repoDriverAccountOwner, address(0));

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

        assertEq(REPO_DRIVER.implementation(), 0x75A8fb92D1b437B4EEa25347304Fe52A9985aCe4);
        assertEq(address(REPO_DRIVER.drips()), repoDriverDrips);
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        assertEq(REPO_DRIVER.driverId(), repoDriverDriverId);
        assertEq(REPO_DRIVER.ownerOf(accountId), repoDriverAccountOwner);
        assertEq(REPO_DRIVER.litOracle(), LIT_ORACLE);
        assertEq(REPO_DRIVER.chain(), FILECOIN_CHAIN);
    }
}

function createProposal() view returns (GovernorProposal memory proposal) {
    proposal = GovernorProposalImpl.create(
        RADWORKS_GOVERNOR, "[RGP - 29] - Migrate Drips oracle to Lit protocol"
    );

    // Upgrade the Ethereum contracts
    proposal.pushCall(
        address(ETHEREUM_REPO_DRIVER),
        abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall,
            (0x56F2A96d9f4aa82D76C48ec4C2483F260A965f06, UPDATE_LIT_ORACLE_CALLDATA)
        )
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
        address repoDriverDrips = address(ETHEREUM_REPO_DRIVER.drips());
        assertTrue(ETHEREUM_REPO_DRIVER.isTrustedForwarder(ETHEREUM_CALLER));
        uint32 repoDriverDriverId = ETHEREUM_REPO_DRIVER.driverId();
        uint256 accountId =
            uint256(0x0000000300656c696d752d61692f63616c63756c61746f720000000000000000);
        address repoDriverAccountOwner = ETHEREUM_REPO_DRIVER.ownerOf(accountId);
        assertNotEq(repoDriverAccountOwner, address(0));

        createProposal().testExecute();

        assertEq(ETHEREUM_REPO_DRIVER.implementation(), 0x56F2A96d9f4aa82D76C48ec4C2483F260A965f06);
        assertEq(address(ETHEREUM_REPO_DRIVER.drips()), repoDriverDrips);
        assertTrue(ETHEREUM_REPO_DRIVER.isTrustedForwarder(ETHEREUM_CALLER));
        assertEq(ETHEREUM_REPO_DRIVER.driverId(), repoDriverDriverId);
        assertEq(ETHEREUM_REPO_DRIVER.ownerOf(accountId), repoDriverAccountOwner);
        assertEq(ETHEREUM_REPO_DRIVER.litOracle(), LIT_ORACLE);
        assertEq(ETHEREUM_REPO_DRIVER.chain(), ETHEREUM_CHAIN);
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
