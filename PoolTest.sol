// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "./libraries/ProxyDeltas.sol";
import "./libraries/ReceiverWeights.sol";
import "@nomiclabs/buidler/console.sol";

contract ReceiverWeightsTest {
    bool internal constant PRINT_GAS_USAGE = false;

    using ReceiverWeightsImpl for ReceiverWeights;

    /// @dev The tested data structure
    ReceiverWeights private receiverWeights;
    /// @dev The values returned from the iteration after the last `setWeights` call
    ReceiverWeightIterated[] private receiverWeightsIterated;
    /// @notice The change of sum of the stored receiver weights due to the last `setWeights` call
    int256 public weightReceiverSumDelta;
    /// @notice The change of sum of the stored proxy weights due to the last `setWeights` call
    int256 public weightProxySumDelta;

    struct ReceiverWeightIterated {
        address receiver;
        uint32 weightReceiver;
        uint32 weightProxy;
    }

    function setWeights(ReceiverWeightIterated[] calldata weights) external {
        require(
            receiverWeights.isZeroed() == (receiverWeightsIterated.length == 0),
            "Invalid result of isZeroed"
        );
        weightReceiverSumDelta = 0;
        weightProxySumDelta = 0;
        uint256 totalGasUsed = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            address receiver = weights[i].receiver;
            uint32 newWeightReceiver = weights[i].weightReceiver;
            uint32 newWeightProxy = weights[i].weightProxy;
            uint256 gasUsed = gasleft();
            uint32 oldWeightReceiver = receiverWeights.setReceiverWeight(
                receiver,
                newWeightReceiver
            );
            gasUsed -= gasleft();
            uint32 oldWeightProxy = receiverWeights.setProxyWeight(receiver, newWeightProxy);
            totalGasUsed += gasUsed;
            weightReceiverSumDelta -= oldWeightReceiver;
            weightReceiverSumDelta += newWeightReceiver;
            weightProxySumDelta -= oldWeightProxy;
            weightProxySumDelta += newWeightProxy;
            if (PRINT_GAS_USAGE)
                console.log(
                    "Setting for receiver %s weight %d with gas used %d",
                    receiver,
                    newWeightReceiver,
                    gasUsed
                );
        }
        delete receiverWeightsIterated;
        address receiver = ReceiverWeightsImpl.ADDR_ROOT;
        uint256 iterationGasUsed = 0;
        while (true) {
            // Each step of the non-pruning iteration should yield the same items
            (
                address receiverIter,
                uint32 weightReceiverIter,
                uint32 weightProxyIter
            ) = receiverWeights.nextWeight(receiver);
            uint32 weightReceiver;
            uint32 weightProxy;
            uint256 gasLeftBefore = gasleft();
            (receiver, weightReceiver, weightProxy) = receiverWeights.nextWeightPruning(receiver);
            iterationGasUsed += gasLeftBefore - gasleft();
            require(receiverIter == receiver, "Non-pruning iterator yielded a different receiver");
            require(
                weightReceiverIter == weightReceiver,
                "Non-pruning iterator yielded a different receiver weight"
            );
            require(
                weightProxyIter == weightProxy,
                "Non-pruning iterator yielded a different proxy weight"
            );
            if (receiver == ReceiverWeightsImpl.ADDR_ROOT) break;
            receiverWeightsIterated.push(
                ReceiverWeightIterated(receiver, weightReceiver, weightProxy)
            );
        }
        if (PRINT_GAS_USAGE) {
            console.log("Iterated over weight list with gas used %d", iterationGasUsed);
            console.log("Total gas used %d", totalGasUsed + iterationGasUsed);
        }
    }

    /// @dev Making `receiverWeightsIterated` public would generate
    /// a getter accepting an index parameter and returning a single item
    function getReceiverWeightsIterated() external view returns (ReceiverWeightIterated[] memory) {
        return receiverWeightsIterated;
    }
}

contract ProxyDeltasTest {
    bool internal constant PRINT_GAS_USAGE = false;

    using ProxyDeltasImpl for ProxyDeltas;

    /// @dev The tested data structure
    ProxyDeltas private proxyDeltas;
    /// @dev The values returned from the iteration after the last `addToDeltas` call
    ProxyDeltaIterated[] private proxyDeltasIterated;

    struct ProxyDeltaIterated {
        uint64 cycle;
        int128 thisCycleDelta;
        int128 nextCycleDelta;
    }

    function addToDeltas(uint64 finishedCycle, ProxyDeltaIterated[] calldata deltas) external {
        uint256 totalGasUsed = 0;
        for (uint256 i = 0; i < deltas.length; i++) {
            ProxyDeltaIterated calldata delta = deltas[i];
            uint256 gasUsed = gasleft();
            proxyDeltas.addToDelta(delta.cycle, delta.thisCycleDelta, delta.nextCycleDelta);
            gasUsed -= gasleft();
            totalGasUsed += gasUsed;
            if (PRINT_GAS_USAGE) {
                if (delta.thisCycleDelta >= 0)
                    console.log(
                        "Adding to cycle %s delta %d with gas used %d",
                        delta.cycle,
                        uint128(delta.thisCycleDelta),
                        gasUsed
                    );
                else
                    console.log(
                        "Adding to cycle %s delta -%d with gas used %d",
                        delta.cycle,
                        uint128(-delta.thisCycleDelta),
                        gasUsed
                    );
            }
        }
        delete proxyDeltasIterated;
        uint64 cycle = ProxyDeltasImpl.CYCLE_ROOT;
        uint256 gasUsed = 0;
        while (true) {
            int128 thisCycleDelta;
            int128 nextCycleDelta;
            uint256 gasLeftBefore = gasleft();
            (cycle, thisCycleDelta, nextCycleDelta) = proxyDeltas.nextDeltaPruning(
                cycle,
                finishedCycle
            );
            gasUsed += gasLeftBefore - gasleft();
            if (cycle == ProxyDeltasImpl.CYCLE_ROOT) break;
            proxyDeltasIterated.push(ProxyDeltaIterated(cycle, thisCycleDelta, nextCycleDelta));
        }
        if (PRINT_GAS_USAGE) {
            console.log("Iterated over proxy deltas with gas used %d", gasUsed);
            console.log("Total gas used %d", totalGasUsed + gasUsed);
        }
    }

    /// @dev Making `proxyDeltasIterated` public would generate
    /// a getter accepting an index parameter and returning a single item
    function getProxyDeltasIterated() external view returns (ProxyDeltaIterated[] memory) {
        return proxyDeltasIterated;
    }
}
