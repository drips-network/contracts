// SPDX-License-Identifier: GPL-3.0-onl
pragma solidity ^0.8.15;

import {Drips, DripsConfig, DripsHistory, DripsConfigImpl, DripsReceiver} from "../../src/Drips.sol";
import {IReserve} from "../../src/Reserve.sol";
import {Managed} from "../../src/Managed.sol";
import {Splits, SplitsReceiver} from "../../src/Splits.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {DripsHub} from "../../src/DripsHub.sol";


contract UpdateReceiverStatesHarness is DripsHub {

    constructor(uint32 cycleSecs_, IReserve reserve_) DripsHub(cycleSecs_, reserve_) {}

    // // no old, 3 new
    // function _helperUpdateReceiverStates_0Old_3New(
    //     DripsReceiver memory receiver1,
    //     DripsReceiver memory receiver2,
    //     DripsReceiver memory receiver3,
    //     uint256 assetId,
    //     uint256 userId) external {
    
    //     DripsReceiver[] memory receiversOld = new DripsReceiver[] (0);
    //     //receiversOld[0] = receiverOld1;
    //     //receiversOld[1] = receiverOld2;
    //     //receiversOld[2] = receiverOld2;
       
    //     DripsReceiver[] memory  receiversNew = new DripsReceiver[] (3);
    //     receiversNew[0] = receiver1;
    //     receiversNew[1] = receiver2;
    //     receiversNew[2] = receiver3;

    //     DripsState storage state = _dripsStorage().states[assetId][userId];
    //     uint32 lastUpdate; // = state.updateTime;
    //     uint32 currMaxEnd; // = state.maxEnd;
    //     uint32 newMaxEnd;

    //     _updateReceiverStates(
    //         Drips._dripsStorage().states[assetId],
    //         receiversOld,
    //         lastUpdate,
    //         currMaxEnd,
    //         receiversNew,
    //         newMaxEnd
    //     );
    // }


    // // 3 old, 0 new
    // function _helperUpdateReceiverStates_3Old_0New(
    //     DripsReceiver memory receiver1,
    //     DripsReceiver memory receiver2,
    //     DripsReceiver memory receiver3,
    //     uint256 assetId,
    //     uint256 userId) external {
    
    //     DripsReceiver[] memory receiversOld = new DripsReceiver[] (3);
    //     receiversOld[0] = receiver1;
    //     receiversOld[1] = receiver2;
    //     receiversOld[2] = receiver3;
       
    //     DripsReceiver[] memory  receiversNew = new DripsReceiver[] (0);
    //     //receiversNew[0] = receiver1;
    //     //receiversNew[1] = receiver2;
    //     //receiversNew[2] = receiver3;

    //     DripsState storage state = _dripsStorage().states[assetId][userId];
    //     uint32 lastUpdate; // = state.updateTime;
    //     uint32 currMaxEnd; // = state.maxEnd;
    //     uint32 newMaxEnd;

    //     _updateReceiverStates(
    //         Drips._dripsStorage().states[assetId],
    //         receiversOld,
    //         lastUpdate,
    //         currMaxEnd,
    //         receiversNew,
    //         newMaxEnd
    //     );
    // }

    // // 1 Old, 2 New
    // function _helperUpdateReceiverStates_1Old_2New(
    //     DripsReceiver memory receiver1,
    //     DripsReceiver memory receiver2,
    //     DripsReceiver memory receiver3,
    //     uint256 assetId,
    //     uint256 userId) external {
    
    //     DripsReceiver[] memory receiversOld = new DripsReceiver[] (1);
    //     receiversOld[0] = receiver1;
    //     //receiversOld[1] = receiver2;
    //     //receiversOld[2] = receiver3;
       
    //     DripsReceiver[] memory  receiversNew = new DripsReceiver[] (2);
    //     receiversNew[0] = receiver2;
    //     receiversNew[1] = receiver3;
    //     //receiversNew[2] = receiver3;

    //     DripsState storage state = _dripsStorage().states[assetId][userId];
    //     uint32 lastUpdate; // = state.updateTime;
    //     uint32 currMaxEnd; // = state.maxEnd;
    //     uint32 newMaxEnd;

    //     _updateReceiverStates(
    //         Drips._dripsStorage().states[assetId],
    //         receiversOld,
    //         lastUpdate,
    //         currMaxEnd,
    //         receiversNew,
    //         newMaxEnd
    //     );
    // }

    // // 2 Old, 1 New
    // function _helperUpdateReceiverStates_2Old_1New(
    //     DripsReceiver memory receiver1,
    //     DripsReceiver memory receiver2,
    //     DripsReceiver memory receiver3,
    //     uint256 assetId,
    //     uint256 userId) external {
    
    //     DripsReceiver[] memory receiversOld = new DripsReceiver[] (2);
    //     receiversOld[0] = receiver1;
    //     receiversOld[1] = receiver2;
    //     //receiversOld[2] = receiver3;
       
    //     DripsReceiver[] memory  receiversNew = new DripsReceiver[] (1);
    //     receiversNew[0] = receiver3;
    //     //receiversNew[1] = receiver3;
    //     //receiversNew[2] = receiver3;

    //     DripsState storage state = _dripsStorage().states[assetId][userId];
    //     uint32 lastUpdate; // = state.updateTime;
    //     uint32 currMaxEnd; // = state.maxEnd;
    //     uint32 newMaxEnd;

    //     _updateReceiverStates(
    //         Drips._dripsStorage().states[assetId],
    //         receiversOld,
    //         lastUpdate,
    //         currMaxEnd,
    //         receiversNew,
    //         newMaxEnd
    //     );
    // }

    // no old, 2 new
    function _helperUpdateReceiverStates_0Old_2New(
        DripsReceiver memory receiver1,
        DripsReceiver memory receiver2,
        DripsReceiver memory receiver3,
        uint256 assetId,
        uint256 userId) external {
    
        DripsReceiver[] memory receiversOld = new DripsReceiver[] (0);
       
        DripsReceiver[] memory  receiversNew = new DripsReceiver[] (2);
        receiversNew[0] = receiver1;
        receiversNew[1] = receiver2;

        DripsState storage state = _dripsStorage().states[assetId][userId];
        uint32 lastUpdate; // = state.updateTime;
        uint32 currMaxEnd; // = state.maxEnd;
        uint32 newMaxEnd;

        _updateReceiverStates(
            Drips._dripsStorage().states[assetId],
            receiversOld,
            lastUpdate,
            currMaxEnd,
            receiversNew,
            newMaxEnd
        );
    }


    // 2 old, no new
    function _helperUpdateReceiverStates_2Old_0New(
        DripsReceiver memory receiver1,
        DripsReceiver memory receiver2,
        DripsReceiver memory receiver3,
        uint256 assetId,
        uint256 userId) external {
    
        DripsReceiver[] memory receiversOld = new DripsReceiver[] (2);
        receiversOld[0] = receiver1;
        receiversOld[1] = receiver2;
       
        DripsReceiver[] memory  receiversNew = new DripsReceiver[] (0);

        DripsState storage state = _dripsStorage().states[assetId][userId];
        uint32 lastUpdate; // = state.updateTime;
        uint32 currMaxEnd; // = state.maxEnd;
        uint32 newMaxEnd;

        _updateReceiverStates(
            Drips._dripsStorage().states[assetId],
            receiversOld,
            lastUpdate,
            currMaxEnd,
            receiversNew,
            newMaxEnd
        );
    }


    // 1 old, 1 new
    function _helperUpdateReceiverStates_1Old_1New(
        DripsReceiver memory receiver1,
        DripsReceiver memory receiver2,
        DripsReceiver memory receiver3,
        uint256 assetId,
        uint256 userId) external {
    
        DripsReceiver[] memory receiversOld = new DripsReceiver[] (1);
        receiversOld[0] = receiver1;
       
        DripsReceiver[] memory  receiversNew = new DripsReceiver[] (1);
        receiversNew[0] = receiver2;

        DripsState storage state = _dripsStorage().states[assetId][userId];
        uint32 lastUpdate; // = state.updateTime;
        uint32 currMaxEnd; // = state.maxEnd;
        uint32 newMaxEnd;

        _updateReceiverStates(
            Drips._dripsStorage().states[assetId],
            receiversOld,
            lastUpdate,
            currMaxEnd,
            receiversNew,
            newMaxEnd
        );
    }

    function unpackArgs(
        DripsReceiver memory receiver1,
        DripsReceiver memory receiver2,
        DripsReceiver memory receiver3
        //uint256 assetId,
        //uint256 userId
    ) public pure returns(
        DripsReceiver memory Receiver1,
        DripsReceiver memory Receiver2,
        DripsReceiver memory Receiver3
    ){
        Receiver1 = receiver1;
        Receiver2 = receiver2;
        Receiver3 = receiver3;
    }


    function _helperUpdateReceiverStates(
        DripsReceiver memory receiverOld1,
        DripsReceiver memory receiverOld2,
        DripsReceiver memory receiverNew1,
        uint256 assetId,
        uint256 userId
    ) external {
    
        DripsReceiver[] memory receiversOld = new DripsReceiver[] (2);
        receiversOld[0] = receiverOld1;
        receiversOld[1] = receiverOld2;
        //receiversOld[0] = receiverOld2;  // currLen 1-id2, newLen 2-id2
       
        DripsReceiver[] memory  receiversNew = new DripsReceiver[] (1);
        receiversNew[0] = receiverNew1;
        //receiversNew[1] = receiverOld2; 

        DripsState storage state = _dripsStorage().states[assetId][userId];
        uint32 lastUpdate = state.updateTime;
        uint32 currMaxEnd = state.maxEnd;

        uint32 newMaxEnd = 0xFFFFFFFF;

        //require (false);  //require false
        //return; //return 1
        _updateReceiverStates(
            Drips._dripsStorage().states[assetId],
            receiversOld,
            lastUpdate,
            currMaxEnd,
            receiversNew,
            newMaxEnd
        );
    }




    function getCycleSecs() public view returns (uint32) {
        return Drips._cycleSecs;
    }

    function setBalanceOfUserId (uint256 assetId, uint256 userId, uint128 setValue) public {
        DripsState storage state = Drips._dripsStorage().states[assetId][userId];
        state.balance = setValue;
    }
    
    // function callUpdateReceiverStates(
    //     uint256 userId,
    //     uint256 assetId,
    //     DripsReceiver[] memory currReceivers,
    //     //int128 balanceDelta,
    //     DripsReceiver[] memory newReceivers
    //     ) public {

    //     DripsState storage state = Drips._dripsStorage().states[assetId][userId];
    //     uint32 lastUpdate = state.updateTime;
    //     uint32 currMaxEnd = state.maxEnd;
    //     uint32 newMaxEnd = currMaxEnd; // simplified to prevent calling _calcMaxEnd()

    //     //Drips._updateReceiverStates(
    //     _updateReceiverStates(
    //         Drips._dripsStorage().states[assetId],
    //         currReceivers,
    //         lastUpdate,
    //         currMaxEnd,
    //         newReceivers,
    //         newMaxEnd
    //     );

    // }




    // Dummy balances for simplification of _updateReceiverStates()
    //mapping(uint256 => uint128) public dummyCurrBalance;  // userId -> balances
    //mapping(uint256 => uint128) public dummyNewBalance;  // userId -> balances

    //Creating a simplified function to override the one that causes a timeout
    function _updateReceiverStates(
        mapping(uint256 => DripsState) storage states,
        DripsReceiver[] memory currReceivers,
        uint32 lastUpdate,
        uint32 currMaxEnd,
        DripsReceiver[] memory newReceivers,
        uint32 newMaxEnd
    ) internal override {  // notice the override
    //) internal {

        //DripsState storage state = Drips._dripsStorage().states[assetId][userId];

        require(currReceivers.length <= _MAX_DRIPS_RECEIVERS, "Too many drips receivers");
        require(newReceivers.length <= _MAX_DRIPS_RECEIVERS, "Too many drips receivers");

        //require(currReceivers.length <= 3, "Too many drips receivers");  // for faster performance
        //require(newReceivers.length <= 3, "Too many drips receivers");  // for faster performance

        for (uint32 i = 0 ; i < currReceivers.length; i++ ) {
            DripsState storage state = states[currReceivers[i].userId];
            //state.balance = dummyCurrBalance[currReceivers[i].userId];
            state.amtDeltas[0].thisCycle -= 1;
            state.amtDeltas[0].nextCycle -= 1;
            state.nextReceivableCycle = uint32(i+1);
        }

        for (uint32 j = 0 ; j < newReceivers.length; j++ ) {
            DripsState storage state = states[newReceivers[j].userId];
            //state.balance = dummyNewBalance[newReceivers[j].userId];
            state.amtDeltas[0].thisCycle += 1;
            state.amtDeltas[0].nextCycle += 1;
            state.nextReceivableCycle = uint32(j+1);
        }
    }


    

}