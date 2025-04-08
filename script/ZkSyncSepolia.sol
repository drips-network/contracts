// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {addressDriverModuleData} from "script/modules/AddressDriver.sol";
import {callerModuleData} from "script/modules/Caller.sol";
import {dripsModuleData} from "script/modules/Drips.sol";
import {giversRegistryModuleData} from "script/modules/GiversRegistry.sol";
import {immutableSplitsDriverModuleData} from "script/modules/ImmutableSplitsDriver.sol";
import {nativeTokenUnwrapperModuleData} from "script/modules/NativeTokenUnwrapper.sol";
import {nftDriverModuleData} from "script/modules/NFTDriver.sol";
import {repoDeadlineDriverModuleData} from "script/modules/RepoDeadlineDriver.sol";
import {repoDriverModuleData} from "script/modules/RepoDriver.sol";
import {repoSubAccountDriverModuleData} from "script/modules/RepoSubAccountDriver.sol";
import {DeployCLI} from "script/utils/CLI.sol";
import {deployCreate3Factory, ICreate3Factory} from "script/utils/Create3Factory.sol";
import {writeDeploymentJson} from "script/utils/DeploymentJson.sol";
import {
    deployModulesDeployer, ModulesDeployer, ModuleData
} from "script/utils/ModulesDeployer.sol";
import {DummyWrappedNativeToken, IWrappedNativeToken} from "src/IWrappedNativeToken.sol";
import {DummyGelatoAutomate} from "src/RepoDriver.sol";

// Due to different gas metering always run with --skip-simulation and --slow
contract Deploy is Script {
    function run() public {
        (bytes32 salt,) = DeployCLI.checkConfig(300);
        vm.startBroadcast();
        ICreate3Factory create3Factory = deployCreate3Factory();
        ModulesDeployer modulesDeployer = deployModulesDeployer(create3Factory, salt, msg.sender);

        address governor = msg.sender;
        ModuleData[] memory modules = new ModuleData[](3);
        modules[0] = callerModuleData(modulesDeployer);
        modules[1] = dripsModuleData(modulesDeployer, governor, 1 days);
        modules[2] = addressDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](2);
        modules[0] = nftDriverModuleData(modulesDeployer, governor);
        modules[1] = immutableSplitsDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](3);
        modules[0] =
            repoDriverModuleData(modulesDeployer, governor, new DummyGelatoAutomate(), "", 0, 0);
        modules[1] = repoSubAccountDriverModuleData(modulesDeployer, governor);
        modules[2] = repoDeadlineDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](2);
        IWrappedNativeToken wrappedNativeToken = new DummyWrappedNativeToken();
        modules[0] = giversRegistryModuleData(modulesDeployer, governor, wrappedNativeToken);
        modules[1] = nativeTokenUnwrapperModuleData(modulesDeployer, wrappedNativeToken);
        modulesDeployer.deployModules(modules);

        writeDeploymentJson(vm, modulesDeployer, salt);
    }
}
