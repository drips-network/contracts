// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {console, Script} from "forge-std/Script.sol";

import {addressDriverModuleData} from "script/modules/AddressDriver.sol";
import {callerModuleData} from "script/modules/Caller.sol";
import {dripsModuleData} from "script/modules/Drips.sol";
import {giversRegistryModuleData, IWrappedNativeToken} from "script/modules/GiversRegistry.sol";
import {immutableSplitsDriverModuleData} from "script/modules/ImmutableSplitsDriver.sol";
import {
    Call,
    lzBridgedGovernorAddress,
    lzBridgedGovernorModule,
    lzBridgedGovernorModuleData
} from "script/modules/LZBridgedGovernor.sol";
import {nativeTokenUnwrapperModuleData} from "script/modules/NativeTokenUnwrapper.sol";
import {nftDriverModuleData} from "script/modules/NFTDriver.sol";
import {
    repoDeadlineDriverModule,
    repoDeadlineDriverModuleData
} from "script/modules/RepoDeadlineDriver.sol";
import {IAutomate, repoDriverModule, repoDriverModuleData} from "script/modules/RepoDriver.sol";
import {
    repoSubAccountDriverModule,
    repoSubAccountDriverModuleData
} from "script/modules/RepoSubAccountDriver.sol";
import {DeployCLI} from "script/utils/CLI.sol";
import {deployCreate3Factory, ICreate3Factory} from "script/utils/Create3Factory.sol";
import {writeDeploymentJson} from "script/utils/DeploymentJson.sol";
import {
    addToProposalConfigInit,
    addToProposalGovernorMessage,
    createSetConfigParams,
    ETHEREUM_EID,
    governorConfigInitCalls,
    LZBridgedGovernor,
    SetConfigParam,
    upgradeToCall
} from "script/utils/LayerZero.sol";
import {
    deployModulesDeployer, ModulesDeployer, ModuleData
} from "script/utils/ModulesDeployer.sol";
import {
    addToProposalWithdrawWeth,
    createProposal,
    execute,
    propose,
    RadworksProposal,
    requireRunOnEthereum,
    WETH
} from "script/utils/Radworks.sol";

uint256 constant CHAIN_ID = 10;

// Take from https://docs.optimism.io/stack/smart-contracts
IWrappedNativeToken constant WRAPPED_NATIVE_TOKEN =
    IWrappedNativeToken(0x4200000000000000000000000000000000000006);

// Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
uint32 constant OPTIMISM_EID = 30111;
address constant OPTIMISM_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
address constant OPTIMISM_RECEIVE_ULN = 0x3c4962Ff6258dcfCafD23a814237B7d6Eb712063;

function governorSetConfigParams() pure returns (SetConfigParam[] memory params) {
    // Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
    address[] memory dvns = new address[](5);
    dvns[0] = 0x218B462e19d00c8feD4adbCe78f33aEf88d2ccFc; // Axelar
    dvns[1] = 0x6A02D83e8d433304bba74EF1c427913958187142; // LayerZero Labs
    dvns[2] = 0x8ddF05F9A5c488b4973897E278B58895bF87Cb24; // Polyhedra
    dvns[3] = 0xfe6507F094155caBB4784403Cd784C2DF04122dd; // Stargate
    dvns[4] = 0x313328609a9C38459CaE56625FFf7F2AD6dcde3b; // Switchboard
    return createSetConfigParams({otherChainEid: ETHEREUM_EID, dvns: dvns, threshold: 3});
}

function radworksSetConfigParams() pure returns (SetConfigParam[] memory params) {
    // Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
    address[] memory dvns = new address[](5);
    dvns[0] = 0xCE5B47FA5139fC5f3c8c5f4C278ad5F56A7b2016; // Axelar
    dvns[1] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs
    dvns[2] = 0x8ddF05F9A5c488b4973897E278B58895bF87Cb24; // Polyhedra
    dvns[3] = 0x8FafAE7Dd957044088b3d0F67359C327c6200d18; // Stargate
    dvns[4] = 0x276e6B1138d2d49C0Cda86658765d12Ef84550c1; // Switchboard
    return createSetConfigParams({otherChainEid: OPTIMISM_EID, dvns: dvns, threshold: 3});
}

contract Deploy is Script {
    function run() public {
        (bytes32 salt, address radworks) = DeployCLI.checkConfig(CHAIN_ID);

        vm.startBroadcast();
        ICreate3Factory create3Factory = deployCreate3Factory();
        ModulesDeployer modulesDeployer = deployModulesDeployer(create3Factory, salt, msg.sender);

        address governor = lzBridgedGovernorAddress(modulesDeployer);
        ModuleData[] memory modules = new ModuleData[](4);
        modules[0] = lzBridgedGovernorModuleData({
            modulesDeployer: modulesDeployer,
            endpoint: OPTIMISM_ENDPOINT,
            ownerEid: ETHEREUM_EID,
            owner: radworks,
            calls: governorConfigInitCalls({
                endpoint: OPTIMISM_ENDPOINT,
                governor: governor,
                receiveUln: OPTIMISM_RECEIVE_ULN,
                params: governorSetConfigParams()
            })
        });
        modules[1] = callerModuleData(modulesDeployer);
        modules[2] = dripsModuleData(modulesDeployer, governor, 1 days);
        modules[3] = addressDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](5);
        modules[0] = nftDriverModuleData(modulesDeployer, governor);
        modules[1] = immutableSplitsDriverModuleData(modulesDeployer, governor);
        modules[2] = repoDriverModuleData({
            modulesDeployer: modulesDeployer,
            admin: governor,
            // Taken from https://docs.gelato.network/web3-services/web3-functions/contract-addresses
            gelatoAutomate: IAutomate(0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0),
            // Deployed from https://github.com/drips-network/contracts-gelato-web3-function
            ipfsCid: "QmeP5ETCt7bZLMtQeFRmJNm5mhYaGgM3GNvExQ4PP12whD",
            // Calculated to saturate the Gelato free tier giving 200K GU.
            // Assumes that each requests costs up to 11 GU (5 seconds of CPU + 1 transaction).
            // The penalty-free throughput is 1 request per 3 minutes.
            maxRequestsPerBlock: 80,
            maxRequestsPer31Days: 18000
        });
        modules[3] = giversRegistryModuleData(modulesDeployer, governor, WRAPPED_NATIVE_TOKEN);
        modules[4] = nativeTokenUnwrapperModuleData(modulesDeployer, WRAPPED_NATIVE_TOKEN);
        modulesDeployer.deployModules(modules);

        writeDeploymentJson(vm, modulesDeployer, salt);
    }
}

contract DeployExtras is Script {
    function run() public {
        ModulesDeployer modulesDeployer = DeployCLI.checkConfigToAddModule(CHAIN_ID);
        vm.startBroadcast();

        ModuleData[] memory modules = new ModuleData[](2);
        address governor = repoDriverModule(modulesDeployer).repoDriver().admin();
        modules[0] = repoSubAccountDriverModuleData(modulesDeployer, governor);
        modules[1] = repoDeadlineDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        console.log(
            "Deployed RepoSubAccountDriver to",
            address(repoSubAccountDriverModule(modulesDeployer).repoSubAccountDriver())
        );
        console.log(
            "Deployed RepoDeadlineDriver to",
            address(repoDeadlineDriverModule(modulesDeployer).repoDeadlineDriver())
        );
    }
}

contract ProposeTestUpdate is Script {
    function run() public {
        requireRunOnEthereum();
        address radworks = 0xd7bEbfA4ecF5df8bF92Fca35d0Ce7995db2E2E96;
        address governor = 0xEDcC9Ca2303dC8f67879F1BCF6549CBe7FfdBb17;
        address proxy = 0x245A4AF555216cCeaf18968fbb85206B10EB4AcC;
        address implementation = 0x747D2cb1e9dC2bEF8E4E08778A85Df8d43b93842;
        uint256 nonce = 0;

        RadworksProposal memory proposal =
            createProposal(radworks, "Update a proxy\nThis is just a **test**!");

        addToProposalConfigInit(proposal, radworksSetConfigParams());

        uint256 fee = 0.01 ether;
        addToProposalWithdrawWeth(proposal, fee);

        Call[] memory calls = new Call[](1);
        calls[0] = upgradeToCall(proxy, implementation);
        addToProposalGovernorMessage({
            proposal: proposal,
            fee: fee,
            governorEid: OPTIMISM_EID,
            governor: governor,
            gas: 100_000,
            message: LZBridgedGovernor.Message({nonce: nonce, value: 0, calls: calls})
        });

        vm.startBroadcast();
        // propose(proposal);
        execute(proposal);
    }
}
