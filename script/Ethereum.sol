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
import {RADWORKS} from "script/utils/Radworks.sol";
import {IWrappedNativeToken} from "src/IWrappedNativeToken.sol";

IWrappedNativeToken constant WRAPPED_NATIVE_TOKEN =
    IWrappedNativeToken(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

contract DeployExtras is Script {
    function run() public {
        DripsDeployer deployer = requireDripsDeployer(1, 0x0c1Ea3a5434Bf8F135fD0c7258F0f25219fDB27f);

        Module[] memory modules = new Module[](4);
        modules[0] = repoSubAccountDriverModule(deployer, RADWORKS);
        modules[1] = repoDeadlineDriverModule(deployer, RADWORKS);
        modules[2] = giversRegistryModule(deployer, RADWORKS, WRAPPED_NATIVE_TOKEN);
        modules[3] = nativeTokenUnwrapperModule(deployer, WRAPPED_NATIVE_TOKEN);

        vm.broadcast();
        deployer.deployModules(modules, new Module[](0), new Module[](0), new Module[](0));
    }
}

import {AddressDriver, SplitsReceiver} from "src/AddressDriver.sol";
import {RepoDeadlineDriver} from "src/RepoDeadlineDriver.sol";
import {GiversRegistry} from "src/Giver.sol";
import {NativeTokenUnwrapper} from "src/NativeTokenUnwrapper.sol";
import {Drips, Forge, IERC20, RepoDriver} from "src/RepoDriver.sol";
import {RepoSubAccountDriver} from "src/RepoSubAccountDriver.sol";

contract TestExtras is Script {
    AddressDriver constant ADDRESS_DRIVER =
        AddressDriver(0x1455d9bD6B98f95dd8FEB2b3D60ed825fcef0610);
    RepoDriver constant REPO_DRIVER =
        RepoDriver(payable(0x770023d55D09A9C110694827F1a6B32D5c2b373E));
    RepoSubAccountDriver constant REPO_SUBACCOUNT_DRIVER =
        RepoSubAccountDriver(0xc219395880FA72E3Ad9180B8878e0D39d144130b);
    RepoDeadlineDriver constant REPO_DEADLINE_DRIVER =
        RepoDeadlineDriver(0x8324ea3538f12895C941a625B7f15Df2d7dBfDfF);
    GiversRegistry constant GIVERS_REGISTRY =
        GiversRegistry(0xe9957C6B02bbB916bf63Cda6fF71981C8e21E398);
    NativeTokenUnwrapper constant NATIVE_TOKEN_UNWRAPPER =
        NativeTokenUnwrapper(payable(0xA4D564894eb4B318e06aDbc284295B6597A22019));
    IERC20 constant POINTS = IERC20(0xd7C1EB0fe4A30d3B2a846C04aa6300888f087A5F);

    function run() public {
        vm.startBroadcast();
        console.log("My wallet", msg.sender);
        uint256 repoAccountId = 0x0000000301ea112c23b9add2f4d503ec324431c3e635c6e67bc653ba4da28338;
        console.log("REPO_DRIVER.ownerOf(repoAccountId)", REPO_DRIVER.ownerOf(repoAccountId));

        uint256 subAccountId = REPO_SUBACCOUNT_DRIVER.calcAccountId(repoAccountId);
        console.log("subAccountId");
        console.logBytes32(bytes32(repoAccountId));
        console.logBytes32(bytes32(subAccountId));
        console.log(
            "REPO_SUBACCOUNT_DRIVER.ownerOf(subAccountId)",
            REPO_SUBACCOUNT_DRIVER.ownerOf(subAccountId)
        );

        POINTS.approve(address(REPO_SUBACCOUNT_DRIVER), 100);
        REPO_SUBACCOUNT_DRIVER.give(subAccountId, 1234, POINTS, 100);

        Drips drips = REPO_DRIVER.drips();
        require(drips.splittable(1234, POINTS) == 100, "Splittable");

        uint256 myAddressId = ADDRESS_DRIVER.calcAccountId(msg.sender);
        uint256 deadlineId = REPO_DEADLINE_DRIVER.calcAccountId(repoAccountId, myAddressId, 1234, 1);

        address payable giver = payable(GIVERS_REGISTRY.giver(deadlineId));
        giver.transfer(1000);
        GIVERS_REGISTRY.give(deadlineId, IERC20(address(0)));
        require(drips.splittable(deadlineId, WRAPPED_NATIVE_TOKEN) == 1000, "Splittable deadline");
        drips.split(deadlineId, WRAPPED_NATIVE_TOKEN, new SplitsReceiver[](0));
        require(
            REPO_DEADLINE_DRIVER.collectAndGive(
                repoAccountId, myAddressId, 1234, 1, WRAPPED_NATIVE_TOKEN
            ) == 1000,
            "CollectAndGive"
        );

        drips.split(myAddressId, WRAPPED_NATIVE_TOKEN, new SplitsReceiver[](0));
        ADDRESS_DRIVER.collect(WRAPPED_NATIVE_TOKEN, address(NATIVE_TOKEN_UNWRAPPER));

        address payable someWallet = payable(0x4567253498364978294922578928087098689789);
        require(NATIVE_TOKEN_UNWRAPPER.unwrap(someWallet) == 1000, "Unwrap");
        require(someWallet.balance == 1000, "Balance");

        console.log("Success!");
    }
}
