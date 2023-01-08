// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Splits, SplitsReceiver} from "../../src/Splits.sol";
import {Managed} from "../../src/Managed.sol";

contract SplitsHarness is Splits, Managed {
    constructor() Splits(erc1967Slot("eip1967.splits.storage")) {}

    SplitsReceiver[] public currSplitReceiversLocal1;
    SplitsReceiver[] public currSplitReceiversLocal2;

    function getCurrSplitsReceiverLocalArr(bool selectCurrSplitReceivers, uint256 index
    ) public view returns (uint256 userId, uint32 weight) {
        if (selectCurrSplitReceivers) {
            userId = currSplitReceiversLocal1[index].userId;
            weight = currSplitReceiversLocal1[index].weight;
        } else {
            userId = currSplitReceiversLocal2[index].userId;
            weight = currSplitReceiversLocal2[index].weight;
        }
    }

    function getCurrSplitsReceiverLocaLength(bool selectCurrSplitReceivers
    ) public view returns (uint256 length) {
        if (selectCurrSplitReceivers) {
            length = currSplitReceiversLocal1.length;
        } else {
            length = currSplitReceiversLocal2.length;
        }
    }

    function getSplitsStorageSlot(
    ) public view returns (bytes32) {
        return _splitsStorageSlot;
    }

    function getPausedSlot(
    ) public view returns (bytes32) {
        return pausedSlot;
    }

    function upgradeTo(address newImplementation
    ) external override onlyProxy {}  // empty function to resolve function call

    function upgradeToAndCall(address newImplementation, bytes memory data
    ) external payable override onlyProxy {}  // empty function to resolve function call

    function splittable(uint256 userId, uint256 assetId
    ) public view returns (uint128 amt) {
        return _splittable(userId, assetId);
    }

    function splitResults(uint256 userId, bool selectCurrSplitReceivers, uint128 amount
    ) public view returns (uint128 collectableAmt, uint128 splitAmt) {
        if (selectCurrSplitReceivers) {
            return _splitResults(userId, currSplitReceiversLocal1, amount);
        } else {
            return _splitResults(userId, currSplitReceiversLocal2, amount);
        }
    }

    function split(uint256 userId, uint256 assetId, bool selectCurrSplitReceivers
    ) public returns (uint128 collectableAmt, uint128 splitAmt) {
        if (selectCurrSplitReceivers) {
            return _split(userId, assetId, currSplitReceiversLocal1);
        } else {
            return _split(userId, assetId, currSplitReceiversLocal2);
        }
    }

    function collectable(uint256 userId, uint256 assetId
    ) public view returns (uint128 amt) {
        return _collectable(userId, assetId);
    }

    function collect(uint256 userId, uint256 assetId
    ) public returns (uint128 amt) {
        return _collect(userId, assetId);
    }

    function give(uint256 userId, uint256 receiver, uint256 assetId, uint128 amt
    ) public {
        return _give(userId, receiver, assetId, amt);
    } 

    function setSplits(uint256 userId, bool selectCurrSplitReceivers
    ) public {
        if (selectCurrSplitReceivers) {
            return _setSplits(userId, currSplitReceiversLocal1);
        } else {
            return _setSplits(userId, currSplitReceiversLocal2);
        }
    }

    function assertSplitsValid(bool selectCurrSplitReceivers, bytes32 receiversHash
    ) public {
        SplitsReceiver[] memory emptyReceivers = new SplitsReceiver[] (0);
        if (selectCurrSplitReceivers) {
            return _assertSplitsValid(currSplitReceiversLocal1, receiversHash);
        } else {
            return _assertSplitsValid(currSplitReceiversLocal2, receiversHash);
        }
    }

    function assertCurrSplits(uint256 userId, bool selectCurrSplitReceivers
    ) public view {
        if (selectCurrSplitReceivers) {
            return _assertCurrSplits(userId, currSplitReceiversLocal1);
        } else {
            return _assertCurrSplits(userId, currSplitReceiversLocal2);
        }
    }

    function splitsHash(uint256 userId
    ) public view returns (bytes32 currSplitsHash) {
        return _splitsHash(userId);
    }

    function hashSplits(bool selectCurrSplitReceivers
    ) public view returns (bytes32 receiversHash) {
        if (selectCurrSplitReceivers) {
            bytes memory tmp = abi.encode(currSplitReceiversLocal1);
            require(tmp.length % 32 == 0, "not compatible length");
            return _hashSplits(currSplitReceiversLocal1);
        } else {
            bytes memory tmp = abi.encode(currSplitReceiversLocal2);
            require(tmp.length % 32 == 0, "not compatible length");
            return _hashSplits(currSplitReceiversLocal2);
        }
    }

}