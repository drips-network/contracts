// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {console, Script} from "forge-std/Script.sol";
import {
    ERC20PresetFixedSupply
} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
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
import {deployCreate3Factory, ICreate3Factory} from "script/utils/Create3Factory.sol";
import {create3} from "script/utils/Create3Helpers.sol";
import {writeDeploymentJson} from "script/utils/DeploymentJson.sol";
import {deployModulesDeployer, ModulesDeployer, ModuleData} from "script/utils/ModulesDeployer.sol";
import {IWrappedNativeToken} from "src/IWrappedNativeToken.sol";

contract Deploy is Script {
    function run() public {
        require(block.chainid == 11155111, "Must be run on Sepolia");
        bytes32 salt = bytes32("DripsDeployerTest6");
        IWrappedNativeToken wrappedNativeToken =
            IWrappedNativeToken(0xE67ABDA0D43f7AC8f37876bBF00D1DFadbB93aaa);

        vm.startBroadcast();
        ICreate3Factory create3Factory = deployCreate3Factory();
        ModulesDeployer modulesDeployer = deployModulesDeployer(create3Factory, salt, msg.sender);

        address governor = msg.sender;
        ModuleData[] memory modules = new ModuleData[](3);
        modules[0] = callerModuleData(modulesDeployer);
        modules[1] = nativeTokenUnwrapperModuleData(modulesDeployer, wrappedNativeToken);
        modules[2] = dripsModuleData(modulesDeployer, governor, 1 days);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](3);
        modules[0] = addressDriverModuleData(modulesDeployer, governor);
        modules[1] = giversRegistryModuleData(modulesDeployer, governor, wrappedNativeToken);
        modules[2] = nftDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](4);
        modules[0] = immutableSplitsDriverModuleData(modulesDeployer, governor);
        modules[1] = repoDriverModuleData(
            modulesDeployer,
            governor,
            bytes32("sepolia"),
            0x77a97dcA6A47e206E112f6F42Ef18c6f16B5e060
        );
        modules[2] = repoSubAccountDriverModuleData(modulesDeployer, governor);
        modules[3] = repoDeadlineDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        writeDeploymentJson(vm, modulesDeployer, salt);
    }
}
