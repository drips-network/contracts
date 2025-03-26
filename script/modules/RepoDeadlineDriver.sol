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
import {RepoDeadlineDriver} from "src/RepoDeadlineDriver.sol";

bytes32 constant REPO_DEADLINE_DRIVER_MODULE_SALT = "RepoDeadlineDriverModule";

function isRepoDeadlineDriverModuleDeployed(ModulesDeployer modulesDeployer)
    view
    returns (bool yes)
{
    return isModuleDeployed(modulesDeployer, REPO_DEADLINE_DRIVER_MODULE_SALT);
}

function repoDeadlineDriverModule(ModulesDeployer modulesDeployer)
    view
    returns (RepoDeadlineDriverModule)
{
    return RepoDeadlineDriverModule(getModule(modulesDeployer, REPO_DEADLINE_DRIVER_MODULE_SALT));
}

function repoDeadlineDriverModuleData(ModulesDeployer modulesDeployer, address admin)
    pure
    returns (ModuleData memory)
{
    bytes memory args = abi.encode(modulesDeployer, admin);
    return ModuleData({
        salt: REPO_DEADLINE_DRIVER_MODULE_SALT,
        initCode: abi.encodePacked(type(RepoDeadlineDriverModule).creationCode, args),
        value: 0
    });
}

contract RepoDeadlineDriverModule is Module {
    RepoDeadlineDriver public immutable repoDeadlineDriver;

    constructor(ModulesDeployer modulesDeployer, address admin)
        Module(modulesDeployer, REPO_DEADLINE_DRIVER_MODULE_SALT)
    {
        RepoDriver repoDriver = repoDriverModule(modulesDeployer).repoDriver();
        uint32 driverId = 5;
        RepoDeadlineDriver logic = new RepoDeadlineDriver(repoDriver, driverId);
        address proxy = create3ManagedProxy(modulesDeployer, "RepoDeadlineDriver", logic, admin, "");
        repoDeadlineDriver = RepoDeadlineDriver(proxy);
        dripsModule(modulesDeployer).claimDriverId(
            REPO_DEADLINE_DRIVER_MODULE_SALT, driverId, proxy
        );
    }
}
