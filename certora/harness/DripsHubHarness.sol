// SPDX-License-Identifier: GPL-3.0-onl
pragma solidity ^0.8.15;

import {Drips, DripsConfig, DripsHistory, DripsConfigImpl, DripsReceiver} from "../../src/Drips.sol";
import {IReserve} from "../../src/Reserve.sol";
import {Managed} from "../../src/Managed.sol";
import {Splits, SplitsReceiver} from "../../src/Splits.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {DripsHub} from "../../src/DripsHub.sol";


contract DripsHubHarness is DripsHub {

    constructor(uint32 cycleSecs_, IReserve reserve_) DripsHub(cycleSecs_, reserve_) {}

    // setting local arrays of structs to pass to setDrips()
    DripsReceiver[] public currReceiversLocal;
    DripsReceiver[] public newReceiversLocal;

    SplitsReceiver[] public currSplitReceiversLocal;

    function setDripsReceiverLocalArr(bool select, uint index, uint256 receiverId, DripsConfig config) public {
        if (select == true) {  // 1 == newReceiversLocal
            newReceiversLocal[index].userId = receiverId;
            newReceiversLocal[index].config = config;
        } else {
            currReceiversLocal[index].userId = receiverId;
            currReceiversLocal[index].config = config;
        }
    }

    function getDripsReceiverLocalArr(bool select, uint index)
        public view
        returns (uint256 userId, uint192 amtPerSec, uint32 start, uint32 duration) {
        DripsConfig config;
        if (select == true) {  // 1 == newReceiversLocal
            userId = newReceiversLocal[index].userId;
            config = newReceiversLocal[index].config;
        } else {
            userId = currReceiversLocal[index].userId;
            config = currReceiversLocal[index].config;
        }
        amtPerSec = DripsConfigImpl.amtPerSec(config);
        start = DripsConfigImpl.start(config);
        duration = DripsConfigImpl.duration(config);
    }

    function getDripsReceiverLocalLength(bool select) public view returns (uint256 length) {
        if (select == true) {  // 1 == newReceiversLocal
            length = newReceiversLocal.length;
        } else {
            length = currReceiversLocal.length;
        }
    }

    function getRelevantStateVars(uint256 assetId, uint256 userId, uint32 cycle)
        public view
        returns (int128 thisCycle, int128 nextCycle, uint32 nextReceivableCycle) {
        thisCycle = _dripsStorage().states[assetId][userId].amtDeltas[cycle].thisCycle;
        nextCycle = _dripsStorage().states[assetId][userId].amtDeltas[cycle].nextCycle;
        nextReceivableCycle = _dripsStorage().states[assetId][userId].nextReceivableCycle;
    }

    // helper that calls setDrips() using the local currReceivers and newReceivers
    function _newHelperSetDrips(
        uint256 userId,
        IERC20 erc20,
        int128 balanceDelta
    ) external {
        setDrips(userId, erc20, currReceiversLocal, balanceDelta, newReceiversLocal);
    }

    // helper that calls split() using the local currSplitReceiversLocal
    function helperSplit(
        uint256 userId,
        IERC20 erc20
    ) external returns (uint128 collectableAmt, uint128 splitAmt){
        return split(userId, erc20, currSplitReceiversLocal);
    }

    // helper that calls collectAll() using the local currSplitReceiversLocal
    function helperCollectAll(
        uint256 userId,
        IERC20 erc20
    ) external returns (uint128 collectedAmt, uint128 splitAmt){
        return collectAll(userId, erc20, currSplitReceiversLocal);
    }


    function _helperCreateConfig(
        uint192 _amtPerSec,
        uint32 _start,
        uint32 _duration
    ) public pure returns (DripsConfig) {
        return DripsConfigImpl.create(_amtPerSec, _start, _duration);
    }


    // simplification of _calcMaxEnd in the case of maximum one DripsReceiver
    function _calcMaxEnd(uint128 balance, DripsReceiver[] memory receivers)
        internal view override returns (uint32 maxEnd) {

        require(receivers.length <= 1, "Too many drips receivers");

        if (receivers.length == 0 || balance == 0) {
            maxEnd = uint32(_currTimestamp());
            return maxEnd;
        }

        uint192 amtPerSec = receivers[0].config.amtPerSec();

        if (amtPerSec == 0) {
            maxEnd = uint32(_currTimestamp());
            return maxEnd;
        }

        uint32 start = receivers[0].config.start();
        uint32 duration = receivers[0].config.duration();
        uint32 end;

        if (duration == 0) {  // duration == 0 -> user requests to drip until end of balance
            end = type(uint32).max;
        } else {
            end = start + duration;
        }

        if (balance / amtPerSec > end - start) {
            maxEnd = end;
        } else {
            maxEnd = start + uint32(balance / amtPerSec);
        }

        return maxEnd;
    }

    // simplified version of _updateReceiverStates():
    function _updateReceiverStates(
        mapping(uint256 => DripsState) storage states,
        DripsReceiver[] memory currReceivers,
        uint32 lastUpdate,
        uint32 currMaxEnd,
        DripsReceiver[] memory newReceivers,
        uint32 newMaxEnd
    //) private {
    ) internal override {

        require (currReceivers.length == 1, "");
        require (newReceivers.length == 1, "");
        DripsReceiver memory currRecv;
        currRecv = currReceivers[0];
        DripsReceiver memory newRecv;
        newRecv = newReceivers[0];
        require ((currRecv.userId == newRecv.userId) &&
                (currRecv.config.amtPerSec() == newRecv.config.amtPerSec()), "");

        if (currReceivers.length == 1 && newReceivers.length == 1) {
            DripsReceiver memory currRecv;
            currRecv = currReceivers[0];
            DripsReceiver memory newRecv;
            newRecv = newReceivers[0];

            if ((currRecv.userId == newRecv.userId) &&
                (currRecv.config.amtPerSec() == newRecv.config.amtPerSec())) {

                DripsState storage state = states[currRecv.userId];
                (uint32 currStart, uint32 currEnd) = _dripsRangeInFuture(currRecv, lastUpdate, currMaxEnd);
                (uint32 newStart, uint32 newEnd) = _dripsRangeInFuture(newRecv, _currTimestamp(), newMaxEnd);
                {
                    int256 amtPerSec = int256(uint256(currRecv.config.amtPerSec()));
                    // Move the start and end times if updated
                    _addDeltaRange(state, currStart, newStart, -amtPerSec);
                    _addDeltaRange(state, currEnd, newEnd, amtPerSec);
                }
                // Ensure that the user receives the updated cycles
                uint32 currStartCycle = _cycleOf(currStart);
                uint32 newStartCycle = _cycleOf(newStart);
                if (currStartCycle > newStartCycle && state.nextReceivableCycle > newStartCycle) {
                    state.nextReceivableCycle = newStartCycle;
                }

                return;
            }
        }


        for (uint i = 0; i < currReceivers.length; i++) {
            DripsReceiver memory currRecv;
            currRecv = currReceivers[i];
            DripsState storage state = states[currRecv.userId];
            (uint32 start, uint32 end) = _dripsRangeInFuture(currRecv, lastUpdate, currMaxEnd);
            int256 amtPerSec = int256(uint256(currRecv.config.amtPerSec()));
            _addDeltaRange(state, start, end, -amtPerSec);
        }

        for (uint i = 0; i < newReceivers.length; i++) {
            DripsReceiver memory newRecv;
            newRecv = newReceivers[i];
            DripsState storage state = states[newRecv.userId];
            (uint32 start, uint32 end) = _dripsRangeInFuture(newRecv, _currTimestamp(), newMaxEnd);
            int256 amtPerSec = int256(uint256(newRecv.config.amtPerSec()));
            _addDeltaRange(state, start, end, amtPerSec);
            // Ensure that the user receives the updated cycles
            uint32 startCycle = _cycleOf(start);
            if (state.nextReceivableCycle == 0 || state.nextReceivableCycle > startCycle) {
                state.nextReceivableCycle = startCycle;
            }
        }
    }


    // we re-wrote _receivableDripsVerbose to perform two time the loops
    function _receivableDripsVerbose(
        uint256 userId,
        uint256 assetId,
        uint32 maxCycles
    )
        //private
        internal
        override
        view
        returns (
            uint128 receivedAmt,
            uint32 receivableCycles,
            uint32 fromCycle,
            uint32 toCycle,
            int128 amtPerCycle
        )
    {
        (fromCycle, toCycle) = _receivableDripsCyclesRange(userId, assetId);
        if (toCycle - fromCycle > maxCycles) {
            receivableCycles = toCycle - fromCycle - maxCycles;
            toCycle -= receivableCycles;
        }
        DripsState storage state = _dripsStorage().states[assetId][userId];

        uint32 midCycle = (fromCycle + toCycle) / 2;

        for (uint32 cycle = fromCycle; cycle < midCycle; cycle++) {
            amtPerCycle += state.amtDeltas[cycle].thisCycle;
            receivedAmt += uint128(amtPerCycle);
            amtPerCycle += state.amtDeltas[cycle].nextCycle;
        }
        for (uint32 cycle = midCycle; cycle < toCycle; cycle++) {
            amtPerCycle += state.amtDeltas[cycle].thisCycle;
            receivedAmt += uint128(amtPerCycle);
            amtPerCycle += state.amtDeltas[cycle].nextCycle;
        }
    }

    // we re-wrote _receiveDrips to perform two time the loops
    function _receiveDrips(
        uint256 userId,
        uint256 assetId,
        uint32 maxCycles
    ) public override
        //internal
        returns (uint128 receivedAmt, uint32 receivableCycles) {
        uint32 fromCycle;
        uint32 toCycle;
        int128 finalAmtPerCycle;
        (
            receivedAmt,
            receivableCycles,
            fromCycle,
            toCycle,
            finalAmtPerCycle
        ) = _receivableDripsVerbose(userId, assetId, maxCycles);
        if (fromCycle != toCycle) {
            DripsState storage state = _dripsStorage().states[assetId][userId];
            state.nextReceivableCycle = toCycle;
            mapping(uint32 => AmtDelta) storage amtDeltas = state.amtDeltas;

            uint32 midCycle = (fromCycle + toCycle) / 2;

            for (uint32 cycle = fromCycle; cycle < midCycle; cycle++) {
            //for (uint32 cycle = fromCycle; cycle < toCycle; cycle++) {
                delete amtDeltas[cycle];
            }
            for (uint32 cycle = midCycle; cycle < toCycle; cycle++) {
            //for (uint32 cycle = fromCycle; cycle < toCycle; cycle++) {
                delete amtDeltas[cycle];
            }
            // The next cycle delta must be relative to the last received cycle, which got zeroed.
            // In other words the next cycle delta must be an absolute value.
            if (finalAmtPerCycle != 0) amtDeltas[toCycle].thisCycle += finalAmtPerCycle;
        }
        emit ReceivedDrips(userId, assetId, receivedAmt, receivableCycles);
    }


    // helper functions to evaluate the re-write of updateReceiverStates
    // to access the original function, we use super.
    function helperUpdateReceiverStates(
        //mapping(uint256 => DripsState) storage states,
        //DripsReceiver[] memory currReceivers,
        uint256 assetId,
        //uint256 userId,
        uint32 lastUpdate,
        uint32 currMaxEnd,
        //DripsReceiver[] memory newReceivers,
        uint32 newMaxEnd
    //) private {
    ) public {
        //DripsState storage state = _dripsStorage().states[assetId][userId];

        _updateReceiverStates(
            _dripsStorage().states[assetId],
            currReceiversLocal,
            lastUpdate,
            currMaxEnd,
            newReceiversLocal,
            newMaxEnd
        );
    }

    function helperUpdateReceiverStatesOriginal(
        //mapping(uint256 => DripsState) storage states,
        //DripsReceiver[] memory currReceivers,
        uint256 assetId,
        //uint256 userId,
        uint32 lastUpdate,
        uint32 currMaxEnd,
        //DripsReceiver[] memory newReceivers,
        uint32 newMaxEnd
    //) private {
    ) public {
        //DripsState storage state = _dripsStorage().states[assetId][userId];

        super._updateReceiverStates(
            _dripsStorage().states[assetId],
            currReceiversLocal,
            lastUpdate,
            currMaxEnd,
            newReceiversLocal,
            newMaxEnd
        );
    }

    /*

    // _dripsStorage().states[assetId][currRecv.userId].amtDeltas[_cycleOf(timestamp)].thisCycle
    // _dripsStorage().states[assetId][currRecv.userId].amtDeltas[__].nextCycle
    // _dripsStorage().states[assetId][currRecv.userId].nextReceivableCycle

    mapping(uint256 => mapping(uint32 => int128)) thisCycleMapping; //userId -> cycleOf -> thisCycle
    mapping(uint256 => mapping(uint32 => int128)) nextCycleMapping; //userId -> cycleOf -> thisCycle
    mapping(uint256 => uint32) nextReceivableCycleMapping;          //userId -> nextReceivableCycle

    function _updateReceiverStates(
        mapping(uint256 => DripsState) storage states,
        DripsReceiver[] memory currReceivers,
        uint32 lastUpdate,
        uint32 currMaxEnd,
        DripsReceiver[] memory newReceivers,
        uint32 newMaxEnd
    //) private {
    ) internal override {  // notice the override
        //return;
        //require(currReceivers.length < 2, "Attempt to reduce computation");
        //require(newReceivers.length < 2, "Attempt to reduce computation");
        uint256 currIdx = 0;
        uint256 newIdx = 0;
        while (true) {
            bool pickCurr = currIdx < currReceivers.length;
            DripsReceiver memory currRecv;
            if (pickCurr) currRecv = currReceivers[currIdx];

            bool pickNew = newIdx < newReceivers.length;
            DripsReceiver memory newRecv;
            if (pickNew) newRecv = newReceivers[newIdx];

            // if-1
            // Limit picking both curr and new to situations when they differ only by time
            if (
                pickCurr &&
                pickNew &&
                (currRecv.userId != newRecv.userId ||
                    currRecv.config.amtPerSec() != newRecv.config.amtPerSec())
            ) {
                pickCurr = _isOrdered(currRecv, newRecv);
                pickNew = !pickCurr;
            }
            
            if (pickCurr && pickNew) {
                // // if-2: same userId, same amtPerSec
                // // Shift the existing drip to fulfil the new configuration

                // DripsState storage state = states[currRecv.userId];
                // (uint32 currStart, uint32 currEnd) = _dripsRangeInFuture(
                //     currRecv,
                //     lastUpdate,
                //     currMaxEnd
                // );
                // (uint32 newStart, uint32 newEnd) = _dripsRangeInFuture(
                //     newRecv,
                //     _currTimestamp(),
                //     newMaxEnd
                // );
                // {
                //     int256 amtPerSec = int256(uint256(currRecv.config.amtPerSec()));
                //     // Move the start and end times if updated
                //     _addDeltaRange(state, currStart, newStart, -amtPerSec);
                //     _addDeltaRange(state, currEnd, newEnd, amtPerSec);
                // }
                // // Ensure that the user receives the updated cycles
                // uint32 currStartCycle = _cycleOf(currStart);
                // uint32 newStartCycle = _cycleOf(newStart);
                // if (currStartCycle > newStartCycle && state.nextReceivableCycle > newStartCycle) {
                //     state.nextReceivableCycle = newStartCycle;
                // }

                states[currRecv.userId].amtDeltas[_currTimestamp()].thisCycle = thisCycleMapping[currRecv.userId][_currTimestamp()];
                states[currRecv.userId].amtDeltas[_currTimestamp()].nextCycle = nextCycleMapping[currRecv.userId][_currTimestamp()];
                states[currRecv.userId].nextReceivableCycle = nextReceivableCycleMapping[currRecv.userId];

            } else if (pickCurr) {
                // // if-3
                // // Remove an existing drip
                // DripsState storage state = states[currRecv.userId];
                // (uint32 start, uint32 end) = _dripsRangeInFuture(currRecv, lastUpdate, currMaxEnd);
                // int256 amtPerSec = int256(uint256(currRecv.config.amtPerSec()));
                // _addDeltaRange(state, start, end, -amtPerSec);
                // //
                states[currRecv.userId].amtDeltas[_currTimestamp()].thisCycle = thisCycleMapping[currRecv.userId][_currTimestamp()];
                states[currRecv.userId].amtDeltas[_currTimestamp()].nextCycle = nextCycleMapping[currRecv.userId][_currTimestamp()];
                //states[currRecv.userId].nextReceivableCycle = nextReceivableCycleMapping[currRecv.userId];
            } else if (pickNew) {
                // // if-4
                // // Create a new drip
                // DripsState storage state = states[newRecv.userId];
                // (uint32 start, uint32 end) = _dripsRangeInFuture(
                //     newRecv,
                //     _currTimestamp(),
                //     newMaxEnd
                // );
                // int256 amtPerSec = int256(uint256(newRecv.config.amtPerSec()));
                // _addDeltaRange(state, start, end, amtPerSec);
                // // Ensure that the user receives the updated cycles
                // uint32 startCycle = _cycleOf(start);
                // if (state.nextReceivableCycle == 0 || state.nextReceivableCycle > startCycle) {
                //     state.nextReceivableCycle = startCycle;
                // }
                // //
                states[newRecv.userId].amtDeltas[_currTimestamp()].thisCycle = thisCycleMapping[newRecv.userId][_currTimestamp()];
                states[newRecv.userId].amtDeltas[_currTimestamp()].nextCycle = nextCycleMapping[newRecv.userId][_currTimestamp()];
                states[newRecv.userId].nextReceivableCycle = nextReceivableCycleMapping[newRecv.userId];
                
            } else {
                break;
            }

            if (pickCurr) currIdx++;
            if (pickNew) newIdx++;
        }
    }

    */


    /*
    function _helperSetDrips(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver memory currReceiver,
        int128 balanceDelta,
        DripsReceiver memory newReceiver
    ) external {
    
        DripsReceiver[] memory currReceivers = new DripsReceiver[] (1);
        currReceivers[0] = currReceiver;
       
        DripsReceiver[] memory newReceivers = new DripsReceiver[] (1);
        newReceivers[0] = newReceiver;

        DripsReceiver[] memory emptyReceivers = new DripsReceiver[] (0);

        if (currReceiver.userId == 0 && newReceiver.userId != 0) {
            setDrips(userId, erc20, emptyReceivers, balanceDelta, newReceivers);

        } else if (currReceiver.userId != 0 && newReceiver.userId == 0) {
            setDrips(userId, erc20, currReceivers, balanceDelta, emptyReceivers);

        } else if (currReceiver.userId != 0 && newReceiver.userId != 0) {
            setDrips(userId, erc20, currReceivers, balanceDelta, newReceivers);
        }

    }
    */

    /*
    // currReceivers is empty, newReceivers has one element
    function _helperSetDrips01(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver memory currReceiver,
        int128 balanceDelta,
        DripsReceiver memory newReceiver
    ) external {
        DripsReceiver[] memory newReceivers = new DripsReceiver[] (1);
        newReceivers[0] = newReceiver;
        DripsReceiver[] memory emptyReceivers = new DripsReceiver[] (0);
        setDrips(userId, erc20, emptyReceivers, balanceDelta, newReceivers);
    }

    // currReceivers has one element, newReceivers is empty
    function _helperSetDrips10(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver memory currReceiver,
        int128 balanceDelta,
        DripsReceiver memory newReceiver
    ) external {
        DripsReceiver[] memory currReceivers = new DripsReceiver[] (1);
        currReceivers[0] = currReceiver;
        DripsReceiver[] memory emptyReceivers = new DripsReceiver[] (0);
        setDrips(userId, erc20, currReceivers, balanceDelta, emptyReceivers);
    }

    // currReceivers has one element, newReceivers has one element
    function _helperSetDrips11(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver memory currReceiver,
        int128 balanceDelta,
        DripsReceiver memory newReceiver
    ) external {
        DripsReceiver[] memory currReceivers = new DripsReceiver[] (1);
        currReceivers[0] = currReceiver;
        DripsReceiver[] memory newReceivers = new DripsReceiver[] (1);
        newReceivers[0] = newReceiver;
        setDrips(userId, erc20, currReceivers, balanceDelta, newReceivers);
    }
    */

    /*
    // this helper function accept single DripsReceiver element (not array of them) 
    function helperSetDrips11(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver memory currReceiver,
        int128 balanceDelta,
        DripsReceiver memory newReceiver
    ) public virtual whenNotPaused onlyApp(userId) returns (uint128 newBalance, int128 realBalanceDelta) {
        DripsReceiver[] memory currReceivers = new DripsReceiver[] (1);
        currReceivers[0] = currReceiver;
        DripsReceiver[] memory newReceivers = new DripsReceiver[] (1);
        newReceivers[0] = newReceiver;

        if (balanceDelta > 0) {
            increaseTotalBalance(erc20, uint128(balanceDelta));
        }
        (newBalance, realBalanceDelta) = Drips._setDrips(
            userId,
            _assetId(erc20),
            currReceivers,
            balanceDelta,
            newReceivers
        );
        if (realBalanceDelta > 0) {
            reserve.deposit(erc20, msg.sender, uint128(realBalanceDelta));
        } else if (realBalanceDelta < 0) {
            decreaseTotalBalance(erc20, uint128(-realBalanceDelta));
            reserve.withdraw(erc20, msg.sender, uint128(-realBalanceDelta));
        }
    }

    function helperSetDrips01(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver memory currReceiver,
        int128 balanceDelta,
        DripsReceiver memory newReceiver
    ) public virtual whenNotPaused onlyApp(userId) returns (uint128 newBalance, int128 realBalanceDelta) {
        DripsReceiver[] memory currReceivers = new DripsReceiver[] (0);
        //currReceivers[0] = currReceiver;
        DripsReceiver[] memory newReceivers = new DripsReceiver[] (1);
        newReceivers[0] = newReceiver;

        if (balanceDelta > 0) {
            increaseTotalBalance(erc20, uint128(balanceDelta));
        }
        (newBalance, realBalanceDelta) = Drips._setDrips(
            userId,
            _assetId(erc20),
            currReceivers,
            balanceDelta,
            newReceivers
        );
        if (realBalanceDelta > 0) {
            reserve.deposit(erc20, msg.sender, uint128(realBalanceDelta));
        } else if (realBalanceDelta < 0) {
            decreaseTotalBalance(erc20, uint128(-realBalanceDelta));
            reserve.withdraw(erc20, msg.sender, uint128(-realBalanceDelta));
        }
    }
    */


    /*
    // helper that returns an array with one struct element
    function _helperArrOfStruct(
        DripsReceiver memory someReceiver
    ) external returns (DripsReceiver[] memory someReceivers) {
        DripsReceiver[] memory someReceivers = new DripsReceiver[] (1);
        someReceivers[0] = someReceiver;
    }

    function _helperEmptyArrOfStruct() external returns (DripsReceiver[] memory someReceivers) {
        DripsReceiver[] memory someReceivers = new DripsReceiver[] (0);
    }
    */




    


    /*
    function callSetDripsWithParameters(
        uint256 userId,
        IERC20 erc20,
        uint256 currReceiver1_userId,
        uint192 currReceiver1_amtPerSec,
        uint32 currReceiver1_start,
        uint32 currReceiver1_duration,
        int128 balanceDelta,
        uint256 newReceiver1_userId,
        uint192 newReceiver1_amtPerSec,
        uint32 newReceiver1_start,
        uint32 newReceiver1_duration
    ) public {


        DripsConfig currConfig1 = DripsConfigImpl.create(currReceiver1_amtPerSec, currReceiver1_start, currReceiver1_duration);
        DripsReceiver memory currReceiver1;
        currReceiver1.userId = currReceiver1_userId;
        currReceiver1.config = currConfig1;
        DripsReceiver[] memory currReceivers = new DripsReceiver[] (1);
        currReceivers[0] = currReceiver1;

        DripsConfig newConfig1 = DripsConfigImpl.create(newReceiver1_amtPerSec, newReceiver1_start, newReceiver1_duration);
        DripsReceiver memory newReceiver1;
        newReceiver1.userId = newReceiver1_userId;
        newReceiver1.config = newConfig1;
        DripsReceiver[] memory newReceivers = new DripsReceiver[] (1);
        newReceivers[0] = newReceiver1;

        DripsReceiver[] memory emptyReceivers = new DripsReceiver[] (0);

        if ((currReceiver1_userId == 0) && newReceiver1_userId != 0) {
            setDrips(userId, erc20, currReceivers, balanceDelta, emptyReceivers);

        } else if ((currReceiver1_userId != 0) && newReceiver1_userId == 0) {
            setDrips(userId, erc20, emptyReceivers, balanceDelta, newReceivers);

        } else if ((currReceiver1_userId != 0) && newReceiver1_userId != 0) {
            setDrips(userId, erc20, currReceivers, balanceDelta, newReceivers);
        }

    }
    */


    // function setDripsLimited(
    //     uint256 userId,
    //     IERC20 erc20,
    //     DripsReceiver[] memory currReceivers,
    //     int128 balanceDelta,
    //     DripsReceiver[] memory newReceivers
    // ) public whenNotPaused onlyApp(userId) returns (uint128 newBalance, int128 realBalanceDelta) {
    //     // Modification: we add requirement to have shorter input that won't timeout
    //     require(currReceivers.length < 2, "currReceivers list too long");
    //     require(newReceivers.length < 2, "newReceivers list too long");

    //     if (balanceDelta > 0) {
    //         increaseTotalBalance(erc20, uint128(balanceDelta));
    //     }

    //     // The original code below accepts two arrays or any length:
    //     (newBalance, realBalanceDelta) = Drips._setDrips(
    //         userId,
    //         _assetId(erc20),
    //         currReceivers,
    //         balanceDelta,
    //         newReceivers
    //     );

    //     if (realBalanceDelta > 0) {
    //         reserve.deposit(erc20, msg.sender, uint128(realBalanceDelta));
    //     } else if (realBalanceDelta < 0) {
    //         decreaseTotalBalance(erc20, uint128(-realBalanceDelta));
    //         reserve.withdraw(erc20, msg.sender, uint128(-realBalanceDelta));
    //     }
    // }

    function getCycleSecs() public view returns (uint32) {
        return Drips._cycleSecs;
    }
    
    function getMaxDripsReceivers() public view returns (uint8) {
        return Drips._MAX_DRIPS_RECEIVERS;
    }

    // setter to verify we have access to _dripsStorage()
    function setBalanceOfUserId (uint256 assetId, uint256 userId, uint128 setValue) public {
        DripsState storage state = Drips._dripsStorage().states[assetId][userId];
        state.balance = setValue;
    }

}