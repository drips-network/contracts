// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {console, Script} from "forge-std/Script.sol";
import {ExecutorOptions} from "layer-zero-v2/protocol/contracts/messagelib/libs/ExecutorOptions.sol";
// import {OptionsBuilder} from "layer-zero-v2/oapp/contracts/oapp/libs/OptionsBuilder.sol";
import {
    ILayerZeroEndpointV2,
    IMessageLibManager,
    MessagingParams,
    MessagingReceipt
} from "layer-zero-v2/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "layer-zero-v2/protocol/contracts/interfaces/IMessageLibManager.sol";
import {Constant} from "layer-zero-v2/messagelib/test/util/Constant.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {BridgedGovernor, BridgedGovernorProxy, Call} from "src/BridgedGovernor.sol";

// Taken from layer-zero-v2/messagelib/contracts/uln/UlnBase.sol
struct UlnConfig {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
}

uint256 constant SEPOLIA_CHAIN_ID = 11155111;
uint256 constant MUMBAI_CHAIN_ID = 80001;

uint256 constant NO_GRACE_PERIOD = 0;

// Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/endpoints
address constant SEPOLIA_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
uint32 constant SEPOLIA_EID = 40161;
address constant MUMBAI_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
uint32 constant MUMBAI_EID = 40109;

// Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/messagelibs
address constant MUMBAI_RECEIVE_ULN_302 = 0xfa4Fbda8E809150eE1676ce675AC746Beb9aF379;
address constant SEPOLIA_SEND_ULN_302 = 0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE;

// Taken from https://docs.layerzero.network/v2/developers/evm/technical-reference/dvn-addresses
address constant SEPOLIA_LAYER_ZERO_LABS_DVN = 0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193;
address constant MUMBAI_LAYER_ZERO_LABS_DVN = 0x67a822F55C5F6E439550b9C4EA39E406480a40f3;
address constant SEPOLIA_BWARE_LABS_DVN = 0xCA7a736be0Fe968A33Af62033B8b36D491f7999B;
address constant MUMBAI_BWARE_LABS_DVN = 0x1cf01d5042d1ae231F918a2645f2762d663476E7;

function requireSorted(address[] memory addresses) pure {
    for (uint256 i = 1; i < addresses.length; i++) {
        require(uint160(addresses[i - 1]) < uint160(addresses[i]), "Addresses not sorted");
    }
}

function messageOptions(uint128 gas) pure returns (bytes memory) {
    uint16 optionsType = 3;
    return abi.encodePacked(optionsType, executorGasOption(gas), executorOrderedOption());
}

function executorGasOption(uint128 gas) pure returns (bytes memory) {
    bytes memory payload = ExecutorOptions.encodeLzReceiveOption(gas, 0);
    return executorOption(ExecutorOptions.OPTION_TYPE_LZRECEIVE, payload);
}

function executorOrderedOption() pure returns (bytes memory) {
    return executorOption(ExecutorOptions.OPTION_TYPE_ORDERED_EXECUTION, "");
}

function executorOption(uint8 optionType, bytes memory payload) pure returns (bytes memory) {
    uint16 length = uint16(1 + payload.length);
    return abi.encodePacked(ExecutorOptions.WORKER_ID, length, optionType, payload);
}

function addressToBytes32(address addr) pure returns (bytes32) {
    return bytes32(uint256(uint160(addr)));
}

// forge script scripts/DeployBridgedGovernor.s.sol:ConfigureOnSepolia $WALLET_ARGS -f "$ETH_RPC_URL"

contract ConfigureOnSepolia is Script {
    function run() public {
        require(block.chainid == SEPOLIA_CHAIN_ID, "Must be run on Sepolia");

        address[] memory optionalDVNs = new address[](2);
        optionalDVNs[0] = SEPOLIA_LAYER_ZERO_LABS_DVN;
        optionalDVNs[1] = SEPOLIA_BWARE_LABS_DVN;
        requireSorted(optionalDVNs);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({
            eid: MUMBAI_EID,
            configType: Constant.CONFIG_TYPE_ULN,
            config: abi.encode(
                UlnConfig({
                    confirmations: 2,
                    requiredDVNCount: Constant.NIL_DVN_COUNT,
                    optionalDVNCount: uint8(optionalDVNs.length),
                    optionalDVNThreshold: 1,
                    requiredDVNs: new address[](0),
                    optionalDVNs: optionalDVNs
                })
            )
        });

        vm.startBroadcast();
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(SEPOLIA_ENDPOINT);
        endpoint.setSendLibrary(msg.sender, MUMBAI_EID, SEPOLIA_SEND_ULN_302);
        endpoint.setConfig(msg.sender, SEPOLIA_SEND_ULN_302, params);
        vm.stopBroadcast();
    }
}

// forge script scripts/DeployBridgedGovernor.s.sol:DeployToMumbai $WALLET_ARGS -f "$ETH_RPC_URL"

contract DeployToMumbai is Script {
    function run() public {
        require(block.chainid == MUMBAI_CHAIN_ID, "Must be run on Polygon Mumbai");

        address[] memory optionalDVNs = new address[](2);
        optionalDVNs[0] = MUMBAI_BWARE_LABS_DVN;
        optionalDVNs[1] = MUMBAI_LAYER_ZERO_LABS_DVN;
        requireSorted(optionalDVNs);

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({
            eid: SEPOLIA_EID,
            configType: Constant.CONFIG_TYPE_ULN,
            config: abi.encode(
                UlnConfig({
                    confirmations: 2,
                    requiredDVNCount: Constant.NIL_DVN_COUNT,
                    optionalDVNCount: uint8(optionalDVNs.length),
                    optionalDVNThreshold: 1,
                    requiredDVNs: new address[](0),
                    optionalDVNs: optionalDVNs
                })
            )
        });

        address governor = vm.computeCreateAddress(msg.sender, vm.getNonce(msg.sender) + 1);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: MUMBAI_ENDPOINT,
            data: abi.encodeWithSelector(
                IMessageLibManager.setReceiveLibrary.selector,
                governor,
                SEPOLIA_EID,
                MUMBAI_RECEIVE_ULN_302,
                NO_GRACE_PERIOD
            ),
            value: 0
        });
        calls[1] = Call({
            target: MUMBAI_ENDPOINT,
            data: abi.encodeWithSelector(
                IMessageLibManager.setConfig.selector, governor, MUMBAI_RECEIVE_ULN_302, params
            ),
            value: 0
        });

        bytes32 owner = addressToBytes32(msg.sender);

        vm.startBroadcast();
        address governorLogic = address(new BridgedGovernor(MUMBAI_ENDPOINT, SEPOLIA_EID, owner));
        address governorProxy = address(new BridgedGovernorProxy(governorLogic, calls));
        vm.stopBroadcast();

        require(governorProxy == governor, "Invalid deployment address");
        console.log("Deployed BridgedGovernor:", governor);
    }
}

// forge script scripts/DeployBridgedGovernor.sol:SendToMumbai $WALLET_ARGS -f "$ETH_RPC_URL"

contract SendToMumbai is Script {
    function run() public {
        require(block.chainid == SEPOLIA_CHAIN_ID, "Must be run on Sepolia");

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: 0x6D8873f56a56f0Af376091beddDD149f3592e854,
            data: abi.encodeWithSignature("approve(address,uint256)", address(0x1234), 5678),
            value: 0
        });

        MessagingParams memory params = MessagingParams({
            dstEid: MUMBAI_EID,
            receiver: addressToBytes32(0xf3Fb9312d0b2413f0C79DbcaFfCfCF70Bef95fc5),
            message: abi.encode(calls),
            options: messageOptions(50_000),
            payInLzToken: false
        });

        vm.startBroadcast();
        MessagingReceipt memory receipt =
            ILayerZeroEndpointV2(SEPOLIA_ENDPOINT).send{value: 0.001 ether}(params, msg.sender);
        vm.stopBroadcast();
        console.log("GUID:", Strings.toHexString(uint256(receipt.guid), 32));
        console.log("Nonce:", receipt.nonce);
        console.log("Cost wei:", receipt.fee.nativeFee);
    }
}

// - C O N F I R M A T I O N S -
//96, // 3 epochs
