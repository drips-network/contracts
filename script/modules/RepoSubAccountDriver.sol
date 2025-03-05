// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {callerModule} from "script/modules/Caller.sol";
import {dripsModule} from "script/modules/Drips.sol";
import {RepoDriver, repoDriverModule} from "script/modules/RepoDriver.sol";
import {create3ManagedProxy} from "script/utils/Create3Helpers.sol";
import {
    isModuleDeployed,
    ModulesDeployer,
    getModule,
    Module,
    ModuleData
} from "script/utils/ModulesDeployer.sol";
import {RepoSubAccountDriver} from "src/RepoSubAccountDriver.sol";

bytes32 constant REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT = "RepoSubAccountDriverModule";

function isRepoSubAccountDriverModuleDeployed(ModulesDeployer modulesDeployer)
    view
    returns (bool yes)
{
    return isModuleDeployed(modulesDeployer, REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT);
}

function repoSubAccountDriverModule(ModulesDeployer modulesDeployer)
    view
    returns (RepoSubAccountDriverModule)
{
    return
        RepoSubAccountDriverModule(getModule(modulesDeployer, REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT));
}

function repoSubAccountDriverModuleData(ModulesDeployer modulesDeployer, address admin)
    pure
    returns (ModuleData memory)
{
    bytes memory args = abi.encode(modulesDeployer, admin);
    return ModuleData({
        salt: REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT,
        initCode: abi.encodePacked(type(RepoSubAccountDriverModule).creationCode, args),
        value: 0
    });
}

contract RepoSubAccountDriverModule is Module {
    RepoSubAccountDriver public immutable repoSubAccountDriver;

    constructor(ModulesDeployer modulesDeployer, address admin)
        Module(modulesDeployer, REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT)
    {
        RepoDriver repoDriver = repoDriverModule(modulesDeployer).repoDriver();
        address forwarder = address(callerModule(modulesDeployer).caller());
        uint32 driverId = 4;
        RepoSubAccountDriver logic = new RepoSubAccountDriver(repoDriver, forwarder, driverId);
        address proxy =
            create3ManagedProxy(modulesDeployer, "RepoSubAccountDriver", logic, admin, "");
        repoSubAccountDriver = RepoSubAccountDriver(payable(proxy));
        dripsModule(modulesDeployer).claimDriverId(
            REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT, driverId, proxy
        );
    }
}
