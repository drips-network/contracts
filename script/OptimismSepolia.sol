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

uint256 constant CHAIN_ID = 11155420;

// Take from https://docs.optimism.io/stack/smart-contracts
IWrappedNativeToken constant WRAPPED_NATIVE_TOKEN =
    IWrappedNativeToken(0x4200000000000000000000000000000000000006);

contract Deploy is Script {
    function run() public {
        (bytes32 salt,) = DeployCLI.checkConfig(CHAIN_ID);

        vm.startBroadcast();
        ICreate3Factory create3Factory = deployCreate3Factory();
        ModulesDeployer modulesDeployer = deployModulesDeployer(create3Factory, salt, msg.sender);

        address governor = msg.sender;
        ModuleData[] memory modules = new ModuleData[](3);
        modules[0] = callerModuleData(modulesDeployer);
        modules[1] = dripsModuleData(modulesDeployer, governor, 1 days);
        modules[2] = addressDriverModuleData(modulesDeployer, governor);
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

contract DeployRepoSubAccountDriver is Script {
    function run() public {
        ModulesDeployer modulesDeployer = DeployCLI.checkConfigToAddModule(CHAIN_ID);
        vm.startBroadcast();

        ModuleData[] memory modules = new ModuleData[](1);
        address governor = repoDriverModule(modulesDeployer).repoDriver().admin();
        modules[0] = repoSubAccountDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        console.log(
            "Deployed RepoSubAccountDriver to",
            address(repoSubAccountDriverModule(modulesDeployer).repoSubAccountDriver())
        );
    }
}
