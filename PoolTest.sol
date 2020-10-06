// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "./Pool.sol";
import "@nomiclabs/buidler/console.sol";

contract ReceiverWeightsTest {
    bool internal constant PRINT_GAS_USAGE = false;

    using ReceiverWeightsImpl for mapping(address => ReceiverWeight);

    mapping(address => ReceiverWeight) private receiverWeights;
    ReceiverWeightIterated[] private receiverWeightsIterated;
    int256 public receiverWeightsSumDelta;

    struct ReceiverWeightIterated {
        address receiver;
        uint32 weight;
    }

    function setWeights(ReceiverWeightIterated[] calldata weights) external {
        int256 weightsSumDelta = 0;
        uint256 totalGasUsed = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            ReceiverWeightIterated calldata weight = weights[i];
            address receiver = weights[i].receiver;
            uint32 newWeight = weights[i].weight;
            uint256 gasUsed = gasleft();
            uint256 oldWeight = receiverWeights.setWeight(receiver, newWeight);
            gasUsed -= gasleft();
            totalGasUsed += gasUsed;
            weightsSumDelta -= int256(oldWeight);
            weightsSumDelta += newWeight;
            if (PRINT_GAS_USAGE)
                console.log(
                    "Setting for receiver %s weight %d with gas used %d",
                    receiver,
                    newWeight,
                    gasUsed
                );
        }
        receiverWeightsSumDelta = weightsSumDelta;
        delete receiverWeightsIterated;
        address receiver = address(0);
        uint256 iterationGasUsed = 0;
        while (true) {
            uint32 weight;
            uint256 gasLeftBefore = gasleft();
            (receiver, weight) = receiverWeights.nextWeight(receiver);
            iterationGasUsed += gasLeftBefore - gasleft();
            if (weight == 0) break;
            receiverWeightsIterated.push(ReceiverWeightIterated(receiver, weight));
        }
        if (PRINT_GAS_USAGE) {
            console.log("Iterated over weight list with gas used %d", iterationGasUsed);
            console.log("Total gas used %d", totalGasUsed + iterationGasUsed);
        }
    }

    function getReceiverWeightsIterated() external view returns (ReceiverWeightIterated[] memory) {
        return receiverWeightsIterated;
    }
}
