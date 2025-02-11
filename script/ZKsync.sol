// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
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
    addToProposalWithdrawWeth,
    createProposal,
    execute,
    propose,
    RadworksProposal,
    RADWORKS,
    requireRunOnEthereum
} from "script/utils/Radworks.sol";
import {AddressDriver} from "src/AddressDriver.sol";
import {Call, GovernorProxy} from "src/BridgedGovernor.sol";
import {Caller} from "src/Caller.sol";
import {Drips} from "src/Drips.sol";
import {GiversRegistry, IWrappedNativeToken} from "src/Giver.sol";
import {ImmutableSplitsDriver} from "src/ImmutableSplitsDriver.sol";
import {ManagedProxy} from "src/Managed.sol";
import {NativeTokenUnwrapper} from "src/NativeTokenUnwrapper.sol";
import {NFTDriver} from "src/NFTDriver.sol";
import {IAutomate, RepoDriver} from "src/RepoDriver.sol";
import {RepoDeadlineDriver} from "src/RepoDeadlineDriver.sol";
import {RepoSubAccountDriver} from "src/RepoSubAccountDriver.sol";
import {CREATE_PREFIX} from "zksync/system-contracts/contracts/Constants.sol";

IWrappedNativeToken constant WRAPPED_NATIVE_TOKEN =
    IWrappedNativeToken(0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91);

// Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts
uint32 constant ZKSYNC_EID = 30165;
address constant ZKSYNC_ENDPOINT = 0xd07C30aF3Ff30D96BDc9c6044958230Eb797DDBF;
address constant ZKSYNC_RECEIVE_ULN = 0x04830f6deCF08Dec9eD6C3fCAD215245B78A59e1;

function governorSetConfigParams() pure returns (SetConfigParam[] memory params) {
    // Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
    address[] memory dvns = new address[](5);
    dvns[0] = 0x3A5a74f863ec48c1769C4Ee85f6C3d70f5655E2A; // Bware labs
    dvns[1] = 0x1253E268Bc04bB43CB96D2F7Ee858b8A1433Cf6D; // Horizen labs
    dvns[2] = 0x620A9DF73D2F1015eA75aea1067227F9013f5C51; // LayerZero Labs
    dvns[3] = 0xb183c2b91cf76cAd13602b32ADa2Fd273f19009C; // Nethermind
    dvns[4] = 0x62aA89bAd332788021F6F4F4Fb196D5Fe59C27a6; // Stargate
    return createSetConfigParams({otherChainEid: ETHEREUM_EID, dvns: dvns, threshold: 3});
}

function radworksSetConfigParams() pure returns (SetConfigParam[] memory params) {
    // Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
    address[] memory dvns = new address[](5);
    dvns[0] = 0x7a23612F07d81F16B26cF0b5a4C3eca0E8668df2; // Bware labs
    dvns[1] = 0x380275805876Ff19055EA900CDb2B46a94ecF20D; // Horizen labs
    dvns[2] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // LayerZero Labs
    dvns[3] = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5; // Nethermind
    dvns[4] = 0x8FafAE7Dd957044088b3d0F67359C327c6200d18; // Stargate
    return createSetConfigParams({otherChainEid: ZKSYNC_EID, dvns: dvns, threshold: 3});
}

contract Deploy is Script {
    function run() public {
        require(block.chainid == 324, "Not running on ZKsync");
        address radworks;
        if (vm.envOr("FINAL_RUN", false)) {
            require(
                msg.sender == 0x7dCaCF417BA662840DcD2A35b67f55911815dD7e, "Use the deployer wallet"
            );
            radworks = RADWORKS;
        } else {
            radworks = vm.envOr("RADWORKS", msg.sender);
        }
        vm.broadcast();
        ZKsyncDeployer deployer = new ZKsyncDeployer(msg.sender, radworks);
        writeDeploymentJson(deployer);
    }

    function writeDeploymentJson(ZKsyncDeployer deployer) internal {
        string memory objectKey = "deployment JSON";

        vm.serializeAddress(objectKey, "LZBridgedGovernor", address(deployer.lzBridgedGovernor()));
        vm.serializeAddress(objectKey, "Caller", address(deployer.caller()));
        vm.serializeAddress(objectKey, "Drips", address(deployer.drips()));
        vm.serializeUint(objectKey, "Drips cycle seconds", deployer.drips().cycleSecs());
        vm.serializeAddress(objectKey, "AddressDriver", address(deployer.addressDriver()));
        vm.serializeAddress(objectKey, "NFTDriver", address(deployer.nftDriver()));
        vm.serializeAddress(
            objectKey, "ImmutableSplitsDriver", address(deployer.immutableSplitsDriver())
        );
        vm.serializeAddress(objectKey, "RepoDriver", address(deployer.repoDriver()));
        vm.serializeAddress(
            objectKey, "RepoSubAccountDriver", address(deployer.repoSubAccountDriver())
        );
        vm.serializeAddress(objectKey, "RepoDeadlineDriver", address(deployer.repoDeadlineDriver()));
        vm.serializeAddress(objectKey, "GiversRegistry", address(deployer.giversRegistry()));
        vm.serializeAddress(
            objectKey, "NativeTokenUnwrapper", address(deployer.nativeTokenUnwrapper())
        );
        vm.serializeAddress(objectKey, "ZKsyncDeployer", address(deployer));
        vm.serializeAddress(objectKey, "Deployer", msg.sender);
        string memory json = vm.serializeUint(objectKey, "Chain ID", block.chainid);
        vm.writeJson(json, "deployment.json");
    }
}

contract ZKsyncDeployer {
    LZBridgedGovernor public immutable lzBridgedGovernor;
    Caller public immutable caller;
    Drips public immutable drips;
    AddressDriver public immutable addressDriver;
    NFTDriver public immutable nftDriver;
    ImmutableSplitsDriver public immutable immutableSplitsDriver;
    RepoDriver public immutable repoDriver;
    RepoSubAccountDriver public immutable repoSubAccountDriver;
    RepoDeadlineDriver public immutable repoDeadlineDriver;
    GiversRegistry public immutable giversRegistry;
    NativeTokenUnwrapper public immutable nativeTokenUnwrapper;

    constructor(address sender, address radworks) {
        address governor = computeAddress(address(this), 1);
        {
            LZBridgedGovernor logic = new LZBridgedGovernor(
                ZKSYNC_ENDPOINT, ETHEREUM_EID, bytes32(uint256(uint160(radworks)))
            );
            Call[] memory calls = governorConfigInitCalls({
                endpoint: ZKSYNC_ENDPOINT,
                governor: governor,
                receiveUln: ZKSYNC_RECEIVE_ULN,
                params: governorSetConfigParams()
            });
            lzBridgedGovernor = LZBridgedGovernor(payable(new GovernorProxy(logic, calls)));
            require(governor == address(lzBridgedGovernor), "Unexpected governor address");
        }
        caller = new Caller();
        {
            Drips logic = new Drips(1 days);
            drips = Drips(address(new ManagedProxy(logic, governor, "")));
        }
        {
            AddressDriver logic = new AddressDriver(drips, address(caller), drips.nextDriverId());
            addressDriver = AddressDriver(address(new ManagedProxy(logic, governor, "")));
            drips.registerDriver(address(addressDriver));
        }
        {
            NFTDriver logic = new NFTDriver(drips, address(caller), drips.nextDriverId());
            nftDriver = NFTDriver(address(new ManagedProxy(logic, governor, "")));
            drips.registerDriver(address(nftDriver));
        }
        {
            ImmutableSplitsDriver logic = new ImmutableSplitsDriver(drips, drips.nextDriverId());
            immutableSplitsDriver =
                ImmutableSplitsDriver(address(new ManagedProxy(logic, governor, "")));
            drips.registerDriver(address(immutableSplitsDriver));
        }
        {
            RepoDriver logic = new RepoDriver(
                drips,
                address(caller),
                drips.nextDriverId(),
                // From https://docs.gelato.network/web3-services/web3-functions/contract-addresses.
                IAutomate(0xF27e0dfD58B423b1e1B90a554001d0561917602F)
            );
            bytes memory data = abi.encodeCall(
                RepoDriver.updateGelatoTask,
                // Deployed from https://github.com/drips-network/contracts-gelato-web3-function.
                // Calculated to saturate the Gelato free tier giving 200K GU.
                // Assumes that each requests costs up to 11 GU (5 seconds of CPU + 1 transaction).
                // The penalty-free throughput is 1 request per 3 minutes.
                ("QmeP5ETCt7bZLMtQeFRmJNm5mhYaGgM3GNvExQ4PP12whD", 80, 18000)
            );
            repoDriver = RepoDriver(payable(new ManagedProxy(logic, governor, data)));
            drips.registerDriver(address(repoDriver));
        }
        {
            RepoSubAccountDriver logic =
                new RepoSubAccountDriver(repoDriver, address(caller), drips.nextDriverId());
            repoSubAccountDriver =
                RepoSubAccountDriver(address(new ManagedProxy(logic, governor, "")));
            drips.registerDriver(address(repoSubAccountDriver));
        }
        {
            RepoDeadlineDriver logic = new RepoDeadlineDriver(repoDriver, drips.nextDriverId());
            repoDeadlineDriver = RepoDeadlineDriver(address(new ManagedProxy(logic, governor, "")));
            drips.registerDriver(address(repoDeadlineDriver));
        }
        {
            GiversRegistry logic = new GiversRegistry(addressDriver, WRAPPED_NATIVE_TOKEN);
            giversRegistry = GiversRegistry(address(new ManagedProxy(logic, governor, "")));
        }
        nativeTokenUnwrapper = new NativeTokenUnwrapper(WRAPPED_NATIVE_TOKEN);
        while (drips.nextDriverId() < 100) {
            drips.registerDriver(sender);
        }
    }

    function computeAddress(address sender, uint256 nonce) internal pure returns (address) {
        bytes32 hash = keccak256(
            bytes.concat(CREATE_PREFIX, bytes32(uint256(uint160(sender))), bytes32(nonce))
        );

        return address(uint160(uint256(hash)));
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
            governorEid: ZKSYNC_EID,
            governor: governor,
            gas: 100_000,
            message: LZBridgedGovernor.Message({nonce: nonce, value: 0, calls: calls})
        });

        vm.startBroadcast();
        // propose(proposal);
        execute(proposal);
    }
}
