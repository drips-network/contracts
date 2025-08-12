// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {console, Script} from "forge-std/Script.sol";
import {DeployCLI} from "script/utils/CLI.sol";
import {
    Create3Factory,
    DripsDeployer,
    giversRegistryModule,
    Module,
    nativeTokenUnwrapperModule,
    repoDeadlineDriverModule,
    repoSubAccountDriverModule,
    repoSubAccountDriverModule,
    requireDripsDeployer
} from "script/utils/Legacy.sol";
import {IWrappedNativeToken} from "src/IWrappedNativeToken.sol";

IWrappedNativeToken constant WRAPPED_NATIVE_TOKEN =
    IWrappedNativeToken(0xE67ABDA0D43f7AC8f37876bBF00D1DFadbB93aaa);

contract DeployExtras is Script {
    function run() public {
        DripsDeployer deployer =
            requireDripsDeployer(11155111, 0xa6030dD9D31FA2333Ee9f7feaCa6FB23c42a1d96);

        Module[] memory modules = new Module[](4);
        modules[0] = repoSubAccountDriverModule(deployer, msg.sender);
        modules[1] = repoDeadlineDriverModule(deployer, msg.sender);
        modules[2] = giversRegistryModule(deployer, msg.sender, WRAPPED_NATIVE_TOKEN);
        modules[3] = nativeTokenUnwrapperModule(deployer, WRAPPED_NATIVE_TOKEN);

        vm.broadcast();
        deployer.deployModules(modules, new Module[](0), new Module[](0), new Module[](0));
    }
}
