// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.2;
pragma experimental ABIEncoderV2;

import "./Pool.sol";

contract ReceiverWeightsTest {
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
        for (uint256 i = 0; i < weights.length; i++) {
            ReceiverWeightIterated calldata weight = weights[i];
            weightsSumDelta += weight.weight;
            weightsSumDelta -= receiverWeights.setWeight(
                weight.receiver,
                weight.weight
            );
        }
        receiverWeightsSumDelta = weightsSumDelta;
        delete receiverWeightsIterated;
        address receiver = address(0);
        while (true) {
            uint32 weight;
            (receiver, weight) = receiverWeights.nextWeight(receiver);
            if (weight == 0) break;
            receiverWeightsIterated.push(
                ReceiverWeightIterated(receiver, weight)
            );
        }
    }

    function getReceiverWeightsIterated()
        external
        view
        returns (ReceiverWeightIterated[] memory)
    {
        return receiverWeightsIterated;
    }
}
