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
import {IAutomate, RepoDriver} from "src/RepoDriver.sol";
import {NFTDriver} from "src/NFTDriver.sol";
import {console, Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {GovernorVotesComp} from "openzeppelin-contracts/governance/extensions/GovernorVotesComp.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20VotesComp} from "openzeppelin-contracts/token/ERC20/extensions/ERC20VotesComp.sol";
import {ICompoundTimelock} from "openzeppelin-contracts/vendor/compound/ICompoundTimelock.sol";

using Calls for Call[];
using GovernorProposalAxelar for GovernorProposal;
using GovernorProposalLZ for GovernorProposal;

address constant ETHEREUM_CALLER = 0x60F25ac5F289Dc7F640f948521d486C964A248e5;
NFTDriver constant ETHEREUM_NFT_DRIVER = NFTDriver(0xcf9c49B0962EDb01Cdaa5326299ba85D72405258);
ImmutableSplitsDriver constant ETHEREUM_IMMUTABLE_SPLITS_DRIVER =
    ImmutableSplitsDriver(0x1212975c0642B07F696080ec1916998441c2b774);
RepoDriver constant ETHEREUM_REPO_DRIVER =
    RepoDriver(payable(0x770023d55D09A9C110694827F1a6B32D5c2b373E));

address constant SEPOLIA_CALLER = 0x09e04Cb8168bd0E8773A79Cc2099f19C46776Fee;
NFTDriver constant SEPOLIA_NFT_DRIVER = NFTDriver(0xdC773a04C0D6EFdb80E7dfF961B6a7B063a28B44);
ImmutableSplitsDriver constant SEPOLIA_IMMUTABLE_SPLITS_DRIVER =
    ImmutableSplitsDriver(0xC3C1955bb50AdA4dC8a55aBC6d4d2a39242685c1);
RepoDriver constant SEPOLIA_REPO_DRIVER =
    RepoDriver(payable(0xa71bdf410D48d4AA9aE1517A69D7E1Ef0c179b2B));

LZBridgedGovernor constant LZ_BRIDGED_GOVERNOR =
    LZBridgedGovernor(payable(0x07791819560264627e9c4B1308e546667E83B564));
AxelarBridgedGovernor constant AXELAR_BRIDGED_GOVERNOR =
    AxelarBridgedGovernor(payable(0xE9B15C572EB7Ba2E2856cc5eFaAb8fe1d0e34116));
address constant CALLER = 0xd6Ab8e72dE3742d45AdF108fAa112Cd232718828;
ImmutableSplitsDriver constant IMMUTABLE_SPLITS_DRIVER =
    ImmutableSplitsDriver(0x96EC722e1338f08bbd469b80394eE118a0bc6753);
RepoDriver constant REPO_DRIVER = RepoDriver(payable(0xe75f56B26857cAe06b455Bfc9481593Ae0FB4257));

// Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
uint32 constant METIS_EID = 30151;
uint32 constant OPTIMISM_EID = 30111;

contract DeployLogicOnEthereum is Script {
    function run() public {
        vm.startBroadcast();
        NFTDriver nftDriver = new NFTDriver(
            ETHEREUM_NFT_DRIVER.drips(), ETHEREUM_CALLER, ETHEREUM_NFT_DRIVER.driverId()
        );
        ImmutableSplitsDriver immutableSplitsDriver = new ImmutableSplitsDriver(
            ETHEREUM_IMMUTABLE_SPLITS_DRIVER.drips(), ETHEREUM_IMMUTABLE_SPLITS_DRIVER.driverId()
        );
        RepoDriver repoDriver = new RepoDriver(
            ETHEREUM_REPO_DRIVER.drips(),
            ETHEREUM_CALLER,
            ETHEREUM_REPO_DRIVER.driverId(),
            // Taken from https://docs.gelato.cloud/Web3-Functions/Additional-Resources/Supported-networks
            IAutomate(0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0)
        );

        console.log("NFTDriver logic:", address(nftDriver));
        console.log("ImmutableSplitsDriver logic:", address(immutableSplitsDriver));
        console.log("RepoDriver logic:", address(repoDriver));
        console.log("----------------------------------");
        console.log("NFTDriver drips:", address(nftDriver.drips()));
        console.log(
            "Current NFTDriver caller trusted:",
            ETHEREUM_NFT_DRIVER.isTrustedForwarder(ETHEREUM_CALLER)
        );
        console.log("NFTDriver caller trusted:", nftDriver.isTrustedForwarder(ETHEREUM_CALLER));
        console.log("NFTDriver driverId:", nftDriver.driverId());
        console.log("----------------------------------");
        console.log("ImmutableSplitsDriver drips:", address(immutableSplitsDriver.drips()));
        console.log("ImmutableSplitsDriver driverId:", immutableSplitsDriver.driverId());
        console.log("----------------------------------");
        console.log("RepoDriver drips:", address(repoDriver.drips()));
        console.log(
            "Current RepoDriver caller trusted:",
            ETHEREUM_REPO_DRIVER.isTrustedForwarder(ETHEREUM_CALLER)
        );
        console.log("RepoDriver caller trusted:", repoDriver.isTrustedForwarder(ETHEREUM_CALLER));
        console.log("RepoDriver driverId:", repoDriver.driverId());
        console.log("RepoDriver gelatoAutomate:", address(repoDriver.gelatoAutomate()));
    }
}

contract DeployLogicOnSepolia is Script {
    function run() public {
        vm.startBroadcast();
        NFTDriver nftDriver =
            new NFTDriver(SEPOLIA_NFT_DRIVER.drips(), SEPOLIA_CALLER, SEPOLIA_NFT_DRIVER.driverId());
        ImmutableSplitsDriver immutableSplitsDriver = new ImmutableSplitsDriver(
            SEPOLIA_IMMUTABLE_SPLITS_DRIVER.drips(), SEPOLIA_IMMUTABLE_SPLITS_DRIVER.driverId()
        );
        RepoDriver repoDriver = new RepoDriver(
            SEPOLIA_REPO_DRIVER.drips(),
            SEPOLIA_CALLER,
            SEPOLIA_REPO_DRIVER.driverId(),
            // Taken from https://docs.gelato.cloud/Web3-Functions/Additional-Resources/Supported-networks
            IAutomate(0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0)
        );

        console.log("NFTDriver logic:", address(nftDriver));
        console.log("ImmutableSplitsDriver logic:", address(immutableSplitsDriver));
        console.log("RepoDriver logic:", address(repoDriver));
        console.log("----------------------------------");
        console.log("NFTDriver drips:", address(nftDriver.drips()));
        console.log(
            "Current NFTDriver caller trusted:",
            SEPOLIA_NFT_DRIVER.isTrustedForwarder(SEPOLIA_CALLER)
        );
        console.log("NFTDriver caller trusted:", nftDriver.isTrustedForwarder(SEPOLIA_CALLER));
        console.log("NFTDriver driverId:", nftDriver.driverId());
        console.log("----------------------------------");
        console.log("ImmutableSplitsDriver drips:", address(immutableSplitsDriver.drips()));
        console.log("ImmutableSplitsDriver driverId:", immutableSplitsDriver.driverId());
        console.log("----------------------------------");
        console.log("RepoDriver drips:", address(repoDriver.drips()));
        console.log(
            "Current RepoDriver caller trusted:",
            SEPOLIA_REPO_DRIVER.isTrustedForwarder(SEPOLIA_CALLER)
        );
        console.log("RepoDriver caller trusted:", repoDriver.isTrustedForwarder(SEPOLIA_CALLER));
        console.log("RepoDriver driverId:", repoDriver.driverId());
        console.log("RepoDriver gelatoAutomate:", address(repoDriver.gelatoAutomate()));
    }
}

bytes constant UPDATE_GELATO_TASK_CALLDATA = abi.encodeCall(
    RepoDriver.updateGelatoTask, ("QmZaFjGs6vPTxhDtP2CKDtwrP7CvM1S4k6ZnHNHxkzQbNn", 80, 18000)
);

contract UpgradeOnSepolia is Script {
    function run() public {
        vm.startBroadcast();
        SEPOLIA_NFT_DRIVER.upgradeTo(0x3f836D71b5aA23972f6E796cfD67CAD5e6a7f026);
        SEPOLIA_IMMUTABLE_SPLITS_DRIVER.upgradeTo(0xb89c0849Ff7c279E195FA7576B532344Ca1d6083);
        SEPOLIA_REPO_DRIVER.upgradeToAndCall(
            0x68CFD1803E7dDDb7432348644E9441b8105172D2, UPDATE_GELATO_TASK_CALLDATA
        );
    }
}

contract DeployLogic is Script {
    function run() public {
        vm.startBroadcast();
        ImmutableSplitsDriver immutableSplitsDriver = new ImmutableSplitsDriver(
            IMMUTABLE_SPLITS_DRIVER.drips(), IMMUTABLE_SPLITS_DRIVER.driverId()
        );
        RepoDriver repoDriver = new RepoDriver(
            REPO_DRIVER.drips(), CALLER, REPO_DRIVER.driverId(), REPO_DRIVER.gelatoAutomate()
        );

        console.log("ImmutableSplitsDriver logic:", address(immutableSplitsDriver));
        console.log("RepoDriver logic:", address(repoDriver));
        console.log("----------------------------------");
        console.log("ImmutableSplitsDriver drips:", address(immutableSplitsDriver.drips()));
        console.log("ImmutableSplitsDriver driverId:", immutableSplitsDriver.driverId());
        console.log("----------------------------------");
        console.log("RepoDriver drips:", address(repoDriver.drips()));
        console.log("Current RepoDriver caller trusted:", REPO_DRIVER.isTrustedForwarder(CALLER));
        console.log("RepoDriver caller trusted:", repoDriver.isTrustedForwarder(CALLER));
        console.log("RepoDriver driverId:", repoDriver.driverId());
        console.log("RepoDriver gelatoAutomate:", address(repoDriver.gelatoAutomate()));
    }
}

function createMetisSetConfigParam() pure returns (SetConfigParam memory) {
    // Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
    address[] memory dvns = new address[](5);
    dvns[0] = 0x380275805876Ff19055EA900CDb2B46a94ecF20D; // Horizen
    dvns[1] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs
    dvns[2] = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5; // Nethermind
    dvns[3] = 0x8ddF05F9A5c488b4973897E278B58895bF87Cb24; // Polyhedra
    dvns[4] = 0x8FafAE7Dd957044088b3d0F67359C327c6200d18; // Stargate
    return createSetConfigParam(METIS_EID, dvns, 3);
}

function createOptimismSetConfigParam() pure returns (SetConfigParam memory) {
    // Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
    address[] memory dvns = new address[](5);
    dvns[0] = 0xCE5B47FA5139fC5f3c8c5f4C278ad5F56A7b2016; // Axelar
    dvns[1] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs
    dvns[2] = 0x8ddF05F9A5c488b4973897E278B58895bF87Cb24; // Polyhedra
    dvns[3] = 0x8FafAE7Dd957044088b3d0F67359C327c6200d18; // Stargate
    dvns[4] = 0x276e6B1138d2d49C0Cda86658765d12Ef84550c1; // Switchboard
    return createSetConfigParam(OPTIMISM_EID, dvns, 3);
}

function createMetisUpgradeMessage() pure returns (LZBridgedGovernor.Message memory) {
    return LZBridgedGovernor.Message({
        nonce: 0,
        value: 0,
        calls: Calls.create().push(
            address(IMMUTABLE_SPLITS_DRIVER),
            abi.encodeCall(UUPSUpgradeable.upgradeTo, (0x459d3067322AA9637430D9512D2f61a853322045))
        ).push(
            address(REPO_DRIVER),
            abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (0x277cEFeC0EE89f01A27d4f66670341743f1C95D2, UPDATE_GELATO_TASK_CALLDATA)
            )
        )
    });
}

contract TestProposalOnMetis is Script, StdAssertions {
    function run() public {
        address immutableSplitsDriverDrips = address(IMMUTABLE_SPLITS_DRIVER.drips());
        uint32 immutableSplitsDriverDriverId = IMMUTABLE_SPLITS_DRIVER.driverId();

        address repoDriverDrips = address(REPO_DRIVER.drips());
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        uint32 repoDriverDriverId = REPO_DRIVER.driverId();
        uint256 accountId =
            uint256(0x000000030065667374616a61732f64726970732d746573742d7265706f2d3130);
        address repoDriverAccountOwner = REPO_DRIVER.ownerOf(accountId);
        assertNotEq(repoDriverAccountOwner, address(0));
        address repoDriverGelatoAutomate = address(REPO_DRIVER.gelatoAutomate());
        assertNotEq(repoDriverGelatoAutomate, address(0));
        address repoDriverGelatoTasksOwner = address(REPO_DRIVER.gelatoTasksOwner());
        assertNotEq(repoDriverGelatoAutomate, address(0));

        vm.prank(ETHEREUM_ENDPOINT); // The endpoint has the same address as on Ethereum
        LZ_BRIDGED_GOVERNOR.lzReceive(
            Origin({
                srcEid: ETHEREUM_EID,
                sender: bytes32(uint256(uint160(RADWORKS_TIMELOCK))),
                nonce: 0
            }),
            0,
            abi.encode(createMetisUpgradeMessage()),
            address(0),
            ""
        );

        assertEq(
            IMMUTABLE_SPLITS_DRIVER.implementation(), 0x459d3067322AA9637430D9512D2f61a853322045
        );
        assertEq(REPO_DRIVER.implementation(), 0x277cEFeC0EE89f01A27d4f66670341743f1C95D2);

        assertEq(address(IMMUTABLE_SPLITS_DRIVER.drips()), immutableSplitsDriverDrips);
        assertEq(IMMUTABLE_SPLITS_DRIVER.driverId(), immutableSplitsDriverDriverId);

        assertEq(address(REPO_DRIVER.drips()), repoDriverDrips);
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        assertEq(REPO_DRIVER.driverId(), repoDriverDriverId);
        assertEq(REPO_DRIVER.ownerOf(accountId), repoDriverAccountOwner);
        assertEq(address(REPO_DRIVER.gelatoAutomate()), repoDriverGelatoAutomate);
        assertEq(address(REPO_DRIVER.gelatoTasksOwner()), repoDriverGelatoTasksOwner);
    }
}

function createOptimismUpgradeMessage() pure returns (LZBridgedGovernor.Message memory) {
    return LZBridgedGovernor.Message({
        nonce: 0,
        value: 0,
        calls: Calls.create().push(
            address(IMMUTABLE_SPLITS_DRIVER),
            abi.encodeCall(UUPSUpgradeable.upgradeTo, (0xa4D8Ab5699EDA234d835830FC323A551B15878a3))
        ).push(
            address(REPO_DRIVER),
            abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (0x41cced5DB73791de36FfaC3DD4D19a4C7378E6FB, UPDATE_GELATO_TASK_CALLDATA)
            )
        )
    });
}

contract TestProposalOnOptimism is Script, StdAssertions {
    function run() public {
        address immutableSplitsDriverDrips = address(IMMUTABLE_SPLITS_DRIVER.drips());
        uint32 immutableSplitsDriverDriverId = IMMUTABLE_SPLITS_DRIVER.driverId();

        address repoDriverDrips = address(REPO_DRIVER.drips());
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        uint32 repoDriverDriverId = REPO_DRIVER.driverId();
        uint256 accountId =
            uint256(0x0000000300736875747465722d6e6574776f726b2f7368757474657200000000);
        address repoDriverAccountOwner = REPO_DRIVER.ownerOf(accountId);
        assertNotEq(repoDriverAccountOwner, address(0));
        address repoDriverGelatoAutomate = address(REPO_DRIVER.gelatoAutomate());
        assertNotEq(repoDriverGelatoAutomate, address(0));
        address repoDriverGelatoTasksOwner = address(REPO_DRIVER.gelatoTasksOwner());
        assertNotEq(repoDriverGelatoAutomate, address(0));

        vm.prank(ETHEREUM_ENDPOINT); // The endpoint has the same address as on Ethereum
        LZ_BRIDGED_GOVERNOR.lzReceive(
            Origin({
                srcEid: ETHEREUM_EID,
                sender: bytes32(uint256(uint160(RADWORKS_TIMELOCK))),
                nonce: 0
            }),
            0,
            abi.encode(createOptimismUpgradeMessage()),
            address(0),
            ""
        );

        assertEq(
            IMMUTABLE_SPLITS_DRIVER.implementation(), 0xa4D8Ab5699EDA234d835830FC323A551B15878a3
        );
        assertEq(REPO_DRIVER.implementation(), 0x41cced5DB73791de36FfaC3DD4D19a4C7378E6FB);

        assertEq(address(IMMUTABLE_SPLITS_DRIVER.drips()), immutableSplitsDriverDrips);
        assertEq(IMMUTABLE_SPLITS_DRIVER.driverId(), immutableSplitsDriverDriverId);

        assertEq(address(REPO_DRIVER.drips()), repoDriverDrips);
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        assertEq(REPO_DRIVER.driverId(), repoDriverDriverId);
        assertEq(REPO_DRIVER.ownerOf(accountId), repoDriverAccountOwner);
        assertEq(address(REPO_DRIVER.gelatoAutomate()), repoDriverGelatoAutomate);
        assertEq(address(REPO_DRIVER.gelatoTasksOwner()), repoDriverGelatoTasksOwner);
    }
}

function createFilecoinUpgradeMessage() pure returns (AxelarBridgedGovernor.Message memory) {
    return AxelarBridgedGovernor.Message({
        nonce: 0,
        calls: Calls.create().push(
            address(IMMUTABLE_SPLITS_DRIVER),
            abi.encodeCall(UUPSUpgradeable.upgradeTo, (0xCcB20FB4b70226E829009D018461d508fcA70060))
        ).push(
            address(REPO_DRIVER),
            abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall,
                (0x20A1B66689cdA2c97aB167C0c0732EC3E986C3b0, UPDATE_GELATO_TASK_CALLDATA)
            )
        )
    });
}

contract TestProposalOnFilecoin is Script, StdAssertions {
    function run() public {
        address immutableSplitsDriverDrips = address(IMMUTABLE_SPLITS_DRIVER.drips());
        uint32 immutableSplitsDriverDriverId = IMMUTABLE_SPLITS_DRIVER.driverId();

        address repoDriverDrips = address(REPO_DRIVER.drips());
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        uint32 repoDriverDriverId = REPO_DRIVER.driverId();
        uint256 accountId =
            uint256(0x000000030043454c74642f43454c2d526574726f000000000000000000000000);
        address repoDriverAccountOwner = REPO_DRIVER.ownerOf(accountId);
        assertNotEq(repoDriverAccountOwner, address(0));
        address repoDriverGelatoAutomate = address(REPO_DRIVER.gelatoAutomate());
        assertNotEq(repoDriverGelatoAutomate, address(0));
        address repoDriverGelatoTasksOwner = address(REPO_DRIVER.gelatoTasksOwner());
        assertNotEq(repoDriverGelatoAutomate, address(0));

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

        assertEq(
            IMMUTABLE_SPLITS_DRIVER.implementation(), 0xCcB20FB4b70226E829009D018461d508fcA70060
        );
        assertEq(REPO_DRIVER.implementation(), 0x20A1B66689cdA2c97aB167C0c0732EC3E986C3b0);

        assertEq(address(IMMUTABLE_SPLITS_DRIVER.drips()), immutableSplitsDriverDrips);
        assertEq(IMMUTABLE_SPLITS_DRIVER.driverId(), immutableSplitsDriverDriverId);

        assertEq(address(REPO_DRIVER.drips()), repoDriverDrips);
        assertTrue(REPO_DRIVER.isTrustedForwarder(CALLER));
        assertEq(REPO_DRIVER.driverId(), repoDriverDriverId);
        assertEq(REPO_DRIVER.ownerOf(accountId), repoDriverAccountOwner);
        assertEq(address(REPO_DRIVER.gelatoAutomate()), repoDriverGelatoAutomate);
        assertEq(address(REPO_DRIVER.gelatoTasksOwner()), repoDriverGelatoTasksOwner);
    }
}

function createProposal() view returns (GovernorProposal memory proposal) {
    proposal = GovernorProposalImpl.create(RADWORKS_GOVERNOR, "TODO");

    // Upgrade the Ethereum contracts
    proposal.pushCall(
        address(ETHEREUM_NFT_DRIVER),
        abi.encodeCall(UUPSUpgradeable.upgradeTo, (0x566ECff89fD28B374F40E64D0B838Fa2175Fc99E))
    );
    proposal.pushCall(
        address(ETHEREUM_IMMUTABLE_SPLITS_DRIVER),
        abi.encodeCall(UUPSUpgradeable.upgradeTo, (0x6E276c2975C1d9Ea776C6fEbE3437ADd4A769131))
    );
    proposal.pushCall(
        address(ETHEREUM_REPO_DRIVER),
        abi.encodeCall(
            UUPSUpgradeable.upgradeToAndCall,
            (0x65C75c75A2cDdd98152cAD40ebbbfEc988bcFdd9, UPDATE_GELATO_TASK_CALLDATA)
        )
    );

    // Unwrap 0.1 WETH for message bridging fees.
    proposal.pushCall(
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
        abi.encodeCall(IWrappedNativeToken.withdraw, (0.1 ether))
    );

    // Configure LayerZero
    SetConfigParam[] memory setConfigParams = new SetConfigParam[](2);
    setConfigParams[0] = createMetisSetConfigParam();
    setConfigParams[1] = createOptimismSetConfigParam();
    proposal.pushCallLZConfigInit(setConfigParams);

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
        address nftDriverDrips = address(ETHEREUM_NFT_DRIVER.drips());
        assertTrue(ETHEREUM_NFT_DRIVER.isTrustedForwarder(ETHEREUM_CALLER));
        uint32 nftDriverDriverId = ETHEREUM_NFT_DRIVER.driverId();
        address nftDriverTokenOwner = ETHEREUM_NFT_DRIVER.ownerOf(
            31191755684409194768993126690116100972451994534322097113232155071147
        );
        uint256 nftDriverNextToken = ETHEREUM_NFT_DRIVER.nextTokenId();

        address immutableSplitsDriverDrips = address(ETHEREUM_IMMUTABLE_SPLITS_DRIVER.drips());
        uint32 immutableSplitsDriverDriverId = ETHEREUM_IMMUTABLE_SPLITS_DRIVER.driverId();

        address repoDriverDrips = address(ETHEREUM_REPO_DRIVER.drips());
        assertTrue(ETHEREUM_REPO_DRIVER.isTrustedForwarder(ETHEREUM_CALLER));
        uint32 repoDriverDriverId = ETHEREUM_REPO_DRIVER.driverId();
        address repoDriverAccountOwner = ETHEREUM_REPO_DRIVER.ownerOf(
            80921563202612637598894410645163834771211244060364915984146437767168
        );
        assertNotEq(repoDriverAccountOwner, address(0));

        createProposal().testExecute();

        assertEq(ETHEREUM_NFT_DRIVER.implementation(), 0x566ECff89fD28B374F40E64D0B838Fa2175Fc99E);
        assertEq(
            ETHEREUM_IMMUTABLE_SPLITS_DRIVER.implementation(),
            0x6E276c2975C1d9Ea776C6fEbE3437ADd4A769131
        );
        assertEq(ETHEREUM_REPO_DRIVER.implementation(), 0x65C75c75A2cDdd98152cAD40ebbbfEc988bcFdd9);

        assertEq(address(ETHEREUM_NFT_DRIVER.drips()), nftDriverDrips);
        assertTrue(ETHEREUM_NFT_DRIVER.isTrustedForwarder(ETHEREUM_CALLER));
        assertEq(ETHEREUM_NFT_DRIVER.driverId(), nftDriverDriverId);
        assertEq(
            ETHEREUM_NFT_DRIVER.ownerOf(
                31191755684409194768993126690116100972451994534322097113232155071147
            ),
            nftDriverTokenOwner
        );
        assertEq(ETHEREUM_NFT_DRIVER.nextTokenId(), nftDriverNextToken);

        assertEq(address(ETHEREUM_IMMUTABLE_SPLITS_DRIVER.drips()), immutableSplitsDriverDrips);
        assertEq(ETHEREUM_IMMUTABLE_SPLITS_DRIVER.driverId(), immutableSplitsDriverDriverId);

        assertEq(address(ETHEREUM_REPO_DRIVER.drips()), repoDriverDrips);
        assertTrue(ETHEREUM_REPO_DRIVER.isTrustedForwarder(ETHEREUM_CALLER));
        assertEq(ETHEREUM_REPO_DRIVER.driverId(), repoDriverDriverId);
        assertEq(
            ETHEREUM_REPO_DRIVER.ownerOf(
                80921563202612637598894410645163834771211244060364915984146437767168
            ),
            repoDriverAccountOwner
        );
        assertEq(
            address(ETHEREUM_REPO_DRIVER.gelatoAutomate()),
            0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0
        );
        assertEq(
            address(ETHEREUM_REPO_DRIVER.gelatoTasksOwner()),
            0x6110056c7280083501148616bd24974769b1ee65
        );
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
