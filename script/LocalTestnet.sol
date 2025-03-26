// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {console, Script} from "forge-std/Script.sol";
import {ERC20PresetFixedSupply} from
    "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";
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
import {
    deployCreate3Factory,
    ICreate3Factory,
    SINGLETON_FACTORY
} from "script/utils/Create3Factory.sol";
import {create3} from "script/utils/Create3Helpers.sol";
import {writeDeploymentJson} from "script/utils/DeploymentJson.sol";
import {
    deployModulesDeployer, ModulesDeployer, ModuleData
} from "script/utils/ModulesDeployer.sol";
import {DummyWrappedNativeToken, IWrappedNativeToken} from "src/IWrappedNativeToken.sol";
import {DummyGelatoAutomate} from "src/RepoDriver.sol";

contract Deploy is Script {
    function run() public {
        require(block.chainid == 31337, "Must be run on Anvil local testnet");
        bytes32 salt = bytes32("test");

        vm.startBroadcast();
        etchSingletonFactory();
        ICreate3Factory create3Factory = deployCreate3Factory();
        ModulesDeployer modulesDeployer = deployModulesDeployer(create3Factory, salt, msg.sender);

        address governor = msg.sender;
        ModuleData[] memory modules = new ModuleData[](5);
        modules[0] = callerModuleData(modulesDeployer);
        modules[1] = dripsModuleData(modulesDeployer, governor, 1 days);
        modules[2] = addressDriverModuleData(modulesDeployer, governor);
        modules[3] = nftDriverModuleData(modulesDeployer, governor);
        modules[4] = immutableSplitsDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](5);
        modules[0] =
            repoDriverModuleData(modulesDeployer, governor, new DummyGelatoAutomate(), "", 0, 0);
        modules[1] = repoSubAccountDriverModuleData(modulesDeployer, governor);
        modules[2] = repoDeadlineDriverModuleData(modulesDeployer, governor);
        IWrappedNativeToken wrappedNativeToken = new DummyWrappedNativeToken();
        modules[3] = giversRegistryModuleData(modulesDeployer, governor, wrappedNativeToken);
        modules[4] = nativeTokenUnwrapperModuleData(modulesDeployer, wrappedNativeToken);
        modulesDeployer.deployModules(modules);

        writeDeploymentJson(vm, modulesDeployer, salt);

        deployTestERC20(modulesDeployer);
    }

    function etchSingletonFactory() internal {
        string memory code =
            "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe036"
            "01600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
        string memory args = string.concat('["', vm.toString(SINGLETON_FACTORY), '","', code, '"]');
        vm.rpc("anvil_setCode", args);
    }

    function deployTestERC20(ModulesDeployer modulesDeployer) internal {
        address erc20 = create3(
            modulesDeployer,
            "TestERC20",
            type(ERC20PresetFixedSupply).creationCode,
            abi.encode("test ERC-20", "TEST", 100 ether, msg.sender)
        );
        console.log("Test ERC-20:", erc20);
    }
}
