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
import {deployCreate3Factory, ICreate3Factory} from "script/utils/Create3Factory.sol";
import {DeployCLI} from "script/utils/CLI.sol";
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
    RADWORKS,
    requireRunOnEthereum,
    WETH
} from "script/utils/Radworks.sol";

uint256 constant CHAIN_ID = 1088;

IWrappedNativeToken constant WRAPPED_NATIVE_TOKEN = IWrappedNativeToken(address(0));

// Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
uint32 constant METIS_EID = 30151;
address constant METIS_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
address constant METIS_RECEIVE_ULN = 0x5539Eb17a84E1D59d37C222Eb2CC4C81b502D1Ac;

function governorSetConfigParams() pure returns (SetConfigParam[] memory params) {
    // Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
    address[] memory dvns = new address[](5);
    dvns[0] = 0x7fe673201724925B5c477d4E1A4Bd3E954688cF5; // Horizen
    dvns[1] = 0x32d4F92437454829b3Fe7BEBfeCE5D0523DEb475; // LayerZero Labs
    dvns[2] = 0x6ABdb569Dc985504cCcB541ADE8445E5266e7388; // Nethermind
    dvns[3] = 0x8ddF05F9A5c488b4973897E278B58895bF87Cb24; // Polyhedra
    dvns[4] = 0x61A1B61A1087be03ABeDC04900Cfcc1C14187237; // Stargate
    return createSetConfigParams({otherChainEid: ETHEREUM_EID, dvns: dvns, threshold: 3});
}

function radworksSetConfigParams() pure returns (SetConfigParam[] memory params) {
    // Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
    address[] memory dvns = new address[](5);
    dvns[0] = 0x380275805876Ff19055EA900CDb2B46a94ecF20D; // Horizen
    dvns[1] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs
    dvns[2] = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5; // Nethermind
    dvns[3] = 0x8ddF05F9A5c488b4973897E278B58895bF87Cb24; // Polyhedra
    dvns[4] = 0x8FafAE7Dd957044088b3d0F67359C327c6200d18; // Stargate
    return createSetConfigParams({otherChainEid: METIS_EID, dvns: dvns, threshold: 3});
}

contract Deploy is Script {
    function run() public {
        (bytes32 salt, address radworks) = DeployCLI.checkConfig(CHAIN_ID);

        vm.startBroadcast();
        ICreate3Factory create3Factory = deployCreate3Factory();
        ModulesDeployer modulesDeployer = deployModulesDeployer(create3Factory, salt, msg.sender);

        address governor = lzBridgedGovernorAddress(modulesDeployer);
        ModuleData[] memory modules = new ModuleData[](2);
        modules[0] = lzBridgedGovernorModuleData({
            modulesDeployer: modulesDeployer,
            endpoint: METIS_ENDPOINT,
            ownerEid: ETHEREUM_EID,
            owner: radworks,
            calls: governorConfigInitCalls({
                endpoint: METIS_ENDPOINT,
                governor: governor,
                receiveUln: METIS_RECEIVE_ULN,
                params: governorSetConfigParams()
            })
        });
        modules[1] = callerModuleData(modulesDeployer);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](1);
        modules[0] = dripsModuleData(modulesDeployer, governor, 1 days);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](2);
        modules[0] = addressDriverModuleData(modulesDeployer, governor);
        modules[1] = nftDriverModuleData(modulesDeployer, governor);
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](1);
        modules[0] = repoDriverModuleData({
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
        modulesDeployer.deployModules(modules);

        modules = new ModuleData[](2);
        modules[0] = immutableSplitsDriverModuleData(modulesDeployer, governor);
        modules[1] = giversRegistryModuleData(modulesDeployer, governor, WRAPPED_NATIVE_TOKEN);
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
        address governor = 0x5ddd68cc89bfc98702Ff17afAE2C8Ad589Eb9680;
        address proxy = 0x11B0D1987285742867756054C6F836b5B15ED360;
        address implementation = 0xa4D8Ab5699EDA234d835830FC323A551B15878a3;
        uint256 nonce = 0;

        RadworksProposal memory proposal =
            createProposal(radworks, "Update a proxy\nThis is just a **test**!");

        addToProposalConfigInit(proposal, radworksSetConfigParams());

        uint256 fee = 0.001 ether;
        // addToProposalWithdrawWeth(proposal, fee);

        Call[] memory calls = new Call[](1);
        calls[0] = upgradeToCall(proxy, implementation);
        addToProposalGovernorMessage({
            proposal: proposal,
            fee: fee,
            governorEid: METIS_EID,
            governor: governor,
            gas: 100_000,
            message: LZBridgedGovernor.Message({nonce: nonce, value: 0, calls: calls})
        });

        vm.startBroadcast();
        // propose(proposal);
        execute(proposal);
    }
}
