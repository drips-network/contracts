/*
    This is a specification file for smart contract
    verification with the Certora prover.

    For more information,
    visit: https://www.certora.com/

    This file is run with scripts/...
*/




/**************************************************
 *                LINKED CONTRACTS                *
 **************************************************/
// Declaration of contracts used in the spec

using Reserve as reserve
using ERC20 as IERC20
//using UpdateReceiverStatesHarness as DH  // if using with UpdateReceiverStatesHarness.sol
using DripsHubHarness as DH  // if using with DripsHubHarness.sol

//using DripsConfigImpl for DripsConfig global;
//using DripsConfigImpl as DCI
// using UUPSUpgradeable as UUPSUpgradeable

/*
struct SplitsReceiver {
    /// @notice The user ID.
    uint256 userId;
    /// @notice The splits weight. Must never be zero.
    /// The user will be getting `weight / _TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the splitting user.
    uint32 weight;
}
*/

/**************************************************
 *              METHODS DECLARATIONS              *
 **************************************************/
methods {
    // Harness method getters:
    //getMaxDripsReceivers() returns (uint8) envfree
    //getAmtPerSec() returns (uint192) envfree
    getCycleSecs() returns (uint32) envfree
    _helperCreateConfig(uint192, uint32, uint32) returns (uint256) envfree
    setDripsReceiverLocalArr(bool, uint, uint256, uint256) envfree
    getDripsReceiverLocalLength(bool) envfree
    getRelevantStateVars(uint256, uint256, uint32) envfree
    getDripsReceiverLocalArr(bool, uint) returns (uint256, uint192, uint32, uint32) envfree

    //erc1967Slot(string) returns (bytes32) envfree
    //_dripsState(uint256, uint256) envfree
    
    // Summarizing external functions:

    // ./src/Drips.sol
    // summarizing with NONDET to resolve timeout of setDrips()

        // _dripsStorage is view only, doesn't change state

        // _hashDrips only does hashing
        /*
        _hashDrips(DripsReceiver[] memory receivers) */
        //////////_hashDrips((uint256, uint256)[] receivers) => NONDET

        // _balanceAt is view only but iterates over the other _balanceAt
        /*
        _balanceAt(
            uint256 userId,
            uint256 assetId,
            DripsReceiver[] memory receivers,
            uint32 timestamp
        ) */
        /*
        _balanceAt(
            uint256 userId,
            uint256 assetId,
            (uint256, uint256)[] receivers,
            uint32 timestamp
        ) => NONDET */

        /*
        _balanceAt(
            uint128 lastBalance,
            uint32 lastUpdate,
            uint32 maxEnd,
            DripsReceiver[] memory receivers,
            uint32 timestamp
        ) */
        /*
        _balanceAt(
            uint128 lastBalance,
            uint32 lastUpdate,
            uint32 maxEnd,
            (uint256, uint256)[] receivers,
            uint32 timestamp
        ) => NONDET */

        // _calcMaxEnd
        /*
        _calcMaxEnd(uint128 balance, DripsReceiver[] memory receivers) */
        //////////_calcMaxEnd(uint128 balance, (uint256, uint256)[] receivers) => NONDET

        // _updateReceiverStates
        /*
        _updateReceiverStates(
            mapping(uint256 => DripsState) storage states,
            DripsReceiver[] memory currReceivers,
            uint32 lastUpdate,
            uint32 currMaxEnd,
            DripsReceiver[] memory newReceivers,
            uint32 newMaxEnd
        ) => NONDET */

        /********** the below is NOT working well
        // when commenting out all the _updateReceiverStates() function -> no timeout!
        _updateReceiverStates(
            // mapping(uint256 => (bytes32, mapping(uint256 => uint32), bytes32, uint32, uint32, uint32, uint128, mapping(uint32 => (int128, int128)))) states,
            (uint256) states, // probably written wrong! to check how mapping translates to abi
            (uint256, uint256)[] currReceivers,
            uint32 lastUpdate,
            uint32 currMaxEnd,
            (uint256, uint256)[] newReceivers,
            uint32 newMaxEnd
        )
        **********/

        /*
        struct DripsState {
        bytes32 dripsHistoryHash;
        mapping(uint256 => uint32) nextSqueezed;
        bytes32 dripsHash;
        uint32 nextReceivableCycle;
        uint32 updateTime;
        uint32 maxEnd;
        uint128 balance;
        mapping(uint32 => AmtDelta) amtDeltas;
        }

        struct AmtDelta {
        int128 thisCycle;
        int128 nextCycle;
        }
        */

        // _currTimestamp is view only, doesn't change state, return current timestamp

        // _hashDripsHistory - is view only, doesn't change state, calculates keccak256
        /*
        _hashDripsHistory(
            bytes32 oldDripsHistoryHash,
            bytes32 dripsHash,
            uint32 updateTime,
            uint32 maxEnd
        ) returns (bytes32 dripsHistoryHash) => NONDET */

        // _drippedAmt
        /*
        _drippedAmt(
            uint256 amtPerSec,
            uint256 start,
            uint256 end
        ) returns (uint256 amt) => NONDET */
    



    /*
    // lib/openzeppelin-contracts/contracts/mocks/UUPS/UUPSLegacy.sol
    upgradeTo(address) => NONDET
    upgradeToAndCall(address, bytes) => NONDET
    */

    // lib/openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol
    proxiableUUID() returns (bytes32) => CONSTANT
    upgradeToAndCall(address, bytes) => NONDET
    /*
    upgradeTo(address newImplementation) => NONDET
    upgradeToAndCall(address newImplementation, bytes data) => NONDET

    _upgradeToAndCallUUPS(
        address newImplementation,
        bytes data,
        bool forceCall
    ) => NONDET
    */

    /*
    // lib/openzeppelin-contracts/contracts/utils/Address.sol
    functionDelegateCall(
        address target,
        bytes data,
        string errorMessage
    ) returns (bytes memory) => NONDET
    */

    // src/Reserve.sol -> IReserve
    withdraw(
        address token,
        address to,
        uint256 amt
    ) => DISPATCHER(true);

    deposit(
        address token,
        address from,
        uint256 amt
    ) => DISPATCHER(true);

    transfer(
        address to,
        uint256 amount
    ) returns (bool) => DISPATCHER(true);
    
    transferFrom(
        address from,
        address to,
        uint256 amount
    ) returns (bool) => DISPATCHER(true);


    // src/Reserve.sol -> IReservePlugin
    afterStart(address token, uint256 amt) => NONDET
    afterDeposition(address token, uint256 amt) => NONDET
    beforeWithdrawal(address token, uint256 amt) => NONDET
    beforeEnd(address token, uint256 amt) => NONDET

}


/**************************************************
 *                  DEFINITIONS                   *
 **************************************************/

// definition all_public_swap_methods(method f) returns bool =
//         f.selector == swap(address, address, uint256, uint256, address).selector ||
//         f.selector == swapFor(address, address, uint256, uint256, address, address).selector;

// filtered {f -> !all_public_swap_methods(f) && !f.isView}

/**************************************************
 *                GHOSTS AND HOOKS                *
 **************************************************/




/**************************************************
 *               CVL FUNCS & DEFS                 *
 **************************************************/

function getReserveContract() returns address {
    return reserve;
}

function requireValidSlots() returns bool {
    env e;
    bytes32 pausedSlotMustValue = 0x2d3dd64cfe36f9c22b4321979818bccfbeada88f68e06ff08869db50f24e4d58;  // eip1967.managed.paused
    //bytes32 pausedSlotMustValue = erc1967Slot("eip1967.managed.paused");
    bytes32 _dripsHubStorageSlotMustValue = 0xe2eace0883e57721da7c6d5421826cf6852312431246618b5b53d0cb70e28a0a;  // eip1967.dripsHub.storage
    //bytes32 _dripsHubStorageSlotMustValue = erc1967Slot("eip1967.dripsHub.storage");
    bytes32 _dripsStorageSlotMustValue = 0xf94794517c2a8c0bbc93f8232e73a9c0381c83eecda81a4f8a722dc7055c6f2b;  // eip1967.drips.storage
    //bytes32 _dripsStorageSlotMustValue = erc1967Slot("eip1967.drips.storage")
    bytes32 _splitsStorageSlotMustValue = 0x4a4773e83022ffd434f8ef4bde63b284fd5172dc2a7b5e180d8b7135f9af9712;  // eip1967.splits.storage
    //bytes32 _splitsStorageSlotMustValue = erc1967Slot("eip1967.splits.storage")

    return  (pausedSlot(e) == pausedSlotMustValue) &&
            (_storageSlot(e) == _dripsHubStorageSlotMustValue) &&
            (_dripsStorageSlot(e) == _dripsStorageSlotMustValue) &&
            (_splitsStorageSlot(e) == _splitsStorageSlotMustValue);
}

/**************************************************
 *                 VALID STATES                   *
 **************************************************/
// Describe expressions over the system's variables
// that should always hold.
// Usually implemented via invariants 

/*
// Validity of amount of receivers
// Number of a sender’s drip receivers little equal to MAX_DRIPS_RECEIVERS
invariant isValidAmountOfReceivers()  // NOT FINISHED!
    // currReceivers.length <= maxSplitsReceivers

    100 == getMaxDripsReceivers()  // MUST BE CHANGED!
    //filtered { f -> !f.isView && !f.isFallback && f.selector != initialize(address,(address,uint256,uint256,uint256,(uint256,uint256,uint256))).selector }


// Validity of amount per second
// The amount per second being dripped. Must never be zero.
invariant amtPerSecMustNeverBeZero()
    getAmtPerSec() != 0  // NOT WORKING, NEED TO PASS struct DripsReceiver
*/


/**************************************************
 *               STATE TRANSITIONS                *
 **************************************************/
// Describe validity of state changes by taking into
// account when something can change or who may change




/**************************************************
 *                METHOD INTEGRITY                *
 **************************************************/
 // Describe the integrity of a specific method




/**************************************************
 *             HIGH-LEVEL PROPERTIES              *
 **************************************************/
// Describe more than one element of the system,
// might be even cross-system, usually implemented
// as invariant or parametric rule,
// sometimes require the usage of ghost




/**************************************************
 *                 RISK ANALYSIS                  *
 **************************************************/
// Reasoning about the assets of the user\system and
// from point of view of what should never happen 




/**************************************************
 *                      MISC                      *
 **************************************************/

//  rules for info and checking the ghost and tool
//  expecting to fail

rule sanity(method f){

    //uint32 cycleSecs = getCycleSecs();
    //require cycleSecs == 2;

    //setupState();
    env e;
    calldataarg args;
    f(e,args);
    assert false;
}


rule sanitySimple(){
    env e;
    calldataarg args;
    helperUpdateReceiverStates(e,args);
    assert false;
}


rule asTimePassesReceivableDripsGrow(){
    env e; env e1; env e2;
    calldataarg args;

    require requireValidSlots();

    uint256 dripperId;
    address erc20;
    int128 balanceDeltaBefore;

    uint256 receiverId;
    uint192 amtPerSec;      uint32 start;           uint32 duration;

    // setup one new receiver only
    require getDripsReceiverLocalLength(false) == 0; // false -> sets the currReceivers
    require getDripsReceiverLocalLength(true) == 1;
    require start == e.block.timestamp;

    DH.DripsConfig configBefore = _helperCreateConfig(amtPerSec, start, duration);
    setDripsReceiverLocalArr(true, 0, receiverId, configBefore);
    
    _newHelperSetDrips(e, dripperId, erc20, balanceDeltaBefore);

    // calculate the ReceivableDripsBefore of the receiver
    uint128 ReceivableDripsBefore; uint32 receivableCyclesBefore;
    // type(uint32).max = 2^32 - 1 = 4294967295
    require e1.block.timestamp > e.block.timestamp;
    ReceivableDripsBefore, receivableCyclesBefore = receivableDrips(e1, receiverId, erc20, 4294967295);

    // calculate the ReceivableDripsAfter of the receiver
    uint128 ReceivableDripsAfter; uint32 receivableCyclesAfter;
    // type(uint32).max = 2^32 - 1 = 4294967295
    require e2.block.timestamp > e1.block.timestamp;
    require e2.block.timestamp < 4294967295;
    ReceivableDripsAfter, receivableCyclesAfter = receivableDrips(e2, receiverId, erc20, 4294967295);

    assert ReceivableDripsAfter >= ReceivableDripsBefore;

    //helperUpdateReceiverStates(e,args);
    //assert false;
}


rule cyclesAdditivity{
    env e1;
    env e2;
    address erc20;
    uint32 maxCycles;
    uint256 userId;
    uint256 assetId;
    uint32 from1;
    uint32 to1;
    uint32 from2;
    uint32 to2;

    require to_mathint(maxCycles) == 2^32-1;
    //require e2.block.timestamp > e1.block.timestamp;
    storage init = lastStorage;

    from1, to1 = _receivableDripsCyclesRange(e1, userId, assetId);
    from2, to2 = _receivableDripsCyclesRange(e2, userId, assetId);

    //require to1-from1 == 2;
    //require to2-from2 == 3;
    require e2.block.timestamp > e1.block.timestamp;
    require e2.block.timestamp < 4294967295;

    uint128 receivableAmt1; uint32 receivableCycles1;
    receivableAmt1, receivableCycles1 = _receivableDrips(e1, userId, assetId, maxCycles);
        _receiveDrips(e1, userId, assetId, maxCycles);
    uint128 receivableAmt2; uint32 receivableCycles2;
    receivableAmt2, receivableCycles2 = _receivableDrips(e2, userId, assetId, maxCycles);

    uint128 receivableAmt12; uint32 receivableCycles12;
    receivableAmt12, receivableCycles12 = _receivableDrips(e2, userId, assetId, maxCycles) at init;

    assert receivableAmt12 == receivableAmt1 + receivableAmt2;

    //assert false;
}


// checks if the re-write of _updateReceiverStates() in the harness
// performs the same functionality without using while(true) loop
rule updateReceiverStatesEquivalency() {
    env e;
    require requireValidSlots();

    // limit the input size of the function
    require getDripsReceiverLocalLength(false) == 1; // false -> sets the currReceivers
    require getDripsReceiverLocalLength(true) == 1;
    uint256 currReceiverId; uint192 currAmtPerSec; uint32 currStart; uint32 currDuration;
    currReceiverId, currAmtPerSec, currStart, currDuration = getDripsReceiverLocalArr(false, 0);

    uint256 newReceiverId; uint192 newAmtPerSec; uint32 newStart; uint32 newDuration;
    newReceiverId, newAmtPerSec, newStart, newDuration = getDripsReceiverLocalArr(true, 0);

    //require currReceiverId != newReceiverId;  // with this requirement the rule passes!

    uint256 assetId;
    uint32 lastUpdate;
    uint32 currMaxEnd;
    uint32 newMaxEnd;

    storage init = lastStorage;
    uint256 userId;
    uint32 cycle;

    // adding a requirement for initial valid states (makes the rule weaker)
    int128 thisCycleInit; int128 nextCycleInit; uint32 nextReceivableCycleInit;
    thisCycleInit, nextCycleInit, nextReceivableCycleInit = getRelevantStateVars(assetId, userId, cycle);
    require thisCycleInit == 0;
    require nextCycleInit == 0;
    require nextReceivableCycleInit == 0;

    // run the simplified function
    helperUpdateReceiverStates(e, assetId, lastUpdate, currMaxEnd, newMaxEnd);
    int128 thisCycle; int128 nextCycle; uint32 nextReceivableCycle;
    thisCycle, nextCycle, nextReceivableCycle = getRelevantStateVars(assetId, userId, cycle);

    // run the original function with same init state
    helperUpdateReceiverStatesOriginal(e, assetId, lastUpdate, currMaxEnd, newMaxEnd) at init;
    int128 thisCycleOrig; int128 nextCycleOrig; uint32 nextReceivableCycleOrig;
    thisCycleOrig, nextCycleOrig, nextReceivableCycleOrig = getRelevantStateVars(assetId, userId, cycle);

    require (userId == currReceiverId) || (userId == newReceiverId);  // help the solver by limiting scope

    assert thisCycle == thisCycleOrig;
    assert nextCycle == nextCycleOrig;
    assert nextReceivableCycle == nextReceivableCycleOrig;

    //assert false;  //rule sanity
}



rule settingSameDripsDoesntChangeReceivableDrips(){
    env e; env e1; env e2;
    calldataarg args;

    uint256 dripperId;
    address erc20;

    require requireValidSlots();

    // set both the inputs for currReceivers and newReceivers to be the same
    require getDripsReceiverLocalLength(false) == 1; // false -> sets the currReceivers
    require getDripsReceiverLocalLength(true) == 1;
    uint256 currReceiverId; uint192 currAmtPerSec; uint32 currStart; uint32 currDuration;
    currReceiverId, currAmtPerSec, currStart, currDuration = getDripsReceiverLocalArr(false, 0);

    uint256 newReceiverId; uint192 newAmtPerSec; uint32 newStart; uint32 newDuration;
    newReceiverId, newAmtPerSec, newStart, newDuration = getDripsReceiverLocalArr(true, 0);

    require currReceiverId == newReceiverId;
    require currAmtPerSec == newAmtPerSec;
    require currStart == newStart;
    require currDuration == newDuration;

    // call updateReceiverStates() with the parameters above
    uint256 assetId;
    uint32 lastUpdate;
    uint32 currMaxEnd;
    uint32 newMaxEnd;
    helperUpdateReceiverStates(e, assetId, lastUpdate, currMaxEnd, newMaxEnd);

    uint256 userId; uint32 cycle;

    int128 thisCycleBefore; int128 nextCycleBefore; uint32 nextReceivableCycleBefore;
    thisCycleBefore, nextCycleBefore, nextReceivableCycleBefore = getRelevantStateVars(assetId, userId, cycle);

    /*
    // calculate the ReceivableDripsBefore of the receiver
    uint128 ReceivableDripsBefore; uint32 receivableCyclesBefore;
    // type(uint32).max = 2^32 - 1 = 4294967295
    require e1.block.timestamp > e.block.timestamp;
    ReceivableDripsBefore, receivableCyclesBefore = receivableDrips(e1, currReceiverId, erc20, 4294967295);
    */

    // call again updateReceiverStates() with the same parameters as the previous call
    require e2.block.timestamp > e1.block.timestamp;
    helperUpdateReceiverStates(e2, assetId, lastUpdate, currMaxEnd, newMaxEnd);


    int128 thisCycleAfter; int128 nextCycleAfter; uint32 nextReceivableCycleAfter;
    thisCycleAfter, nextCycleAfter, nextReceivableCycleAfter = getRelevantStateVars(assetId, userId, cycle);


    /*
    // calculate the ReceivableDripsAfter of the receiver
    uint128 ReceivableDripsAfter; uint32 receivableCyclesAfter;
    require e2.block.timestamp < 4294967295;
    ReceivableDripsAfter, receivableCyclesAfter = receivableDrips(e2, currReceiverId, erc20, 4294967295);
    */

    assert thisCycleBefore == thisCycleAfter;
    assert nextCycleBefore == nextCycleAfter;
    assert nextReceivableCycleBefore == nextReceivableCycleAfter;
    //assert ReceivableDripsAfter == ReceivableDripsBefore;

    //assert false;
}

rule whoChangedBalanceOfUserId(method f, uint256 userId) {
    env eB;
    env eF;

    require requireValidSlots();

    calldataarg args;
    uint256 assetId;


    bytes32 dripsHashBefore;
    bytes32 dripsHistoryHashBefore;
    uint32 updateTimeBefore;
    uint128 balanceBefore;
    uint32 maxEndBefore;

    dripsHashBefore,
     dripsHistoryHashBefore,
     updateTimeBefore,
     balanceBefore,
     maxEndBefore = _dripsState(eB, userId, assetId);

    f(eF,args);  // call any function

    bytes32 dripsHashAfter;
    bytes32 dripsHistoryHashAfter;
    uint32 updateTimeAfter;
    uint128 balanceAfter;
    uint32 maxEndAfter;

    dripsHashAfter,
     dripsHistoryHashAfter,
     updateTimeAfter,
     balanceAfter,
     maxEndAfter = _dripsState(eF, userId, assetId);


    assert balanceBefore == balanceAfter, "balanceOfUser changed";
}


rule whoChangedBalanceOfToken(method f, address erc20)
    // filtered{f->f.selector==pause().selector}
    // filtered {f -> f.isView}
    // filtered { f -> !f.isView &&
    //                 !f.isFallback &&
    //                 f.selector != setDrips(uint256,address,(uint256,uint256)[],int128,(uint256,uint256)[]).selector }
 {
    env e;
    calldataarg args;

    require requireValidSlots();

    bytes32 pausedSlotBefore = pausedSlot(e);  // eip1967.managed.paused
    bytes32 _storageSlotBefore = _storageSlot(e);  // eip1967.dripsHub.storage

    uint256 balanceBefore = totalBalance(e, erc20);

    f(e,args);

    bytes32 _storageSlotAfter = _storageSlot(e);
    bytes32 pausedSlotAfter = pausedSlot(e);

    uint256 balanceAfter = totalBalance(e, erc20);

    assert balanceBefore == balanceAfter, "balanceOfToken changed";

    //assert false;
}

rule receiverCannotLoseMoney() {
    require requireValidSlots();
    // at any time it is impossible that receivableDrips(user) < 0;
    env e1; env e2;
    require e1.block.timestamp < e2.block.timestamp;
    require e2.block.timestamp < 4294967295;

    uint256 userId;
    address erc20;
    uint32 maxCycles;

    uint128 receivableAmtBefore;
    uint32 receivableCyclesBefore;

    uint128 receivableAmtAfter;
    uint32 receivableCyclesAfter;


    receivableAmtBefore, receivableCyclesBefore = receivableDrips(e1, userId, erc20, maxCycles);
    receivableAmtAfter, receivableCyclesAfter = receivableDrips(e2, userId, erc20, maxCycles);

    assert receivableAmtBefore <= receivableAmtAfter;
}

// rule ifTheOnlyOneDripperStopsReceivableDripsCanNotIncrease()
// {
//     // make sure there is only one sender and one receiver
//     // make sure the sender is dripping to the receiver
//     // calculate the _receivableDrips(receiver) before dripping stops
//     // stop the dripping
//     // calculate the _receivableDrips(receiver) after dripping stops
//     // after == before
// }


// rule startDrippingToUserCannotDecreaseReceivableAmt()
// {
//     // make sure that the dripper was not sending to the user:
//     // require currReceivers.length == 0;

//     // check the receivable balance of the user before:
//     // (uint128 receivedAmtBefore, ) = Drips._receivableDrips(userId, assetId, type(uint32).max);

//     // start sending to the user

//     // check the receivable balance of the user after:
//     // (uint128 receivedAmtAfter, ) = Drips._receivableDrips(userId, assetId, type(uint32).max);

//     // assert receivedAmtAfter > receivedAmtBefore
// }

rule integrityOfPast(method f)
{
    require requireValidSlots();

    env e0;                 address erc20;
    calldataarg args;       uint256 dripperId;      uint256 receiverId;

    require erc20 == 0x100;
    require dripperId == 1;
    require receiverId == 2;

    // setup one dripper and one receiver with start dripping timestamp of now
    uint192 amtPerSec;      uint32 start;           uint32 duration;

    require amtPerSec == 1;
    require start == 5;
    require duration == 100;

    DH.DripsConfig configBefore = _helperCreateConfig(amtPerSec, start, duration);

    require e0.block.timestamp == start;

    int128 balanceDelta;

    DH.DripsReceiver currReceiverBefore;
    require currReceiverBefore.userId == 0; // this will force passing empty currReceivers

    DH.DripsReceiver newReceiverBefore;
    require newReceiverBefore.userId == receiverId;
    require receiverId != 0;
    require newReceiverBefore.config == configBefore;

    //_helperSetDrips01(e0, dripperId, erc20, currReceiverBefore, balanceDelta, newReceiverBefore);
    //helperSetDrips01(e0, dripperId, erc20, currReceiverBefore, balanceDelta, newReceiverBefore);

    // let at least one cycle pass
    uint32 cycleSecs = getCycleSecs();

    require cycleSecs == 2;

    env e1;
    require e1.block.timestamp > e0.block.timestamp + cycleSecs;

    // calculate the ReceivableDripsBefore of the receiver
    // collectableAll() can be used if the user has also set splits
    uint128 ReceivableDripsBefore; uint32 receivableCyclesBefore;
    // type(uint32).max = 2^32 - 1 = 4294967295
    ReceivableDripsBefore, receivableCyclesBefore = receivableDrips(e1, receiverId, erc20, 4294967295);

    // change the dripper configuration to start dripping to the receiver in the future
    // i.e. try to alter the past, as if the past dripping did not occur
    // use the same amtPerSec and duration, only change the start time to the future
    uint32 newStart;
    require newStart > e1.block.timestamp + 10 * cycleSecs;
    DH.DripsConfig configAfter = _helperCreateConfig(amtPerSec, newStart, duration);

    DH.DripsReceiver newReceiverAfter;
    require newReceiverAfter.userId == receiverId;
    require receiverId != 0;
    require newReceiverAfter.config == configAfter;

    //_helperSetDrips11(e1, dripperId, erc20, newReceiverBefore, balanceDelta, newReceiverAfter);
    //setDrips(e1, dripperId, erc20, _helperArrOfStruct(e1, newReceiverBefore), balanceDelta, _helperArrOfStruct(e1, newReceiverAfter));
    //helperSetDrips11(e1, dripperId, erc20, newReceiverBefore, balanceDelta, newReceiverAfter);

    // calculate again the ReceivableDripsAfter of the receiver
    // at a time before the newStart begins
    env e2;
    require e2.block.timestamp > e1.block.timestamp;
    require e2.block.timestamp < newStart;
    uint128 ReceivableDripsAfter; uint32 receivableCyclesAfter;
    // type(uint32).max = 2^32 - 1 = 4294967295
    ReceivableDripsAfter, receivableCyclesAfter = receivableDrips(e2, receiverId, erc20, 4294967295);

    // validate that the past dripping stays, i.e. what was already dripped is still receivable
    assert ReceivableDripsBefore == ReceivableDripsAfter;

    assert false; // sanity
}


rule integrityOfSplit() {
    require requireValidSlots();
    env e;
    uint256 userId;
    address erc20;
    uint128 splittableBefore;
    
    splittableBefore = splittable(e, userId, erc20);

    uint128 collectableAmt; uint128 splitAmt;

    collectableAmt, splitAmt = helperSplit(e, userId, erc20);

    assert splittableBefore == collectableAmt + splitAmt;

    //assert false;  // sanity
}


rule integrityOfCollectAll() {
    require requireValidSlots();
    env e;
    require e.block.timestamp < 4294967295; // type(uint32).max = 2^32 - 1 = 4294967295
    //require e.block.timestamp == 1000000;
    uint256 userId;
    address erc20;
    uint256 balanceBefore; uint256 balanceAfter;

    helperCollectAll(e, userId, erc20);    
    balanceBefore = totalBalance(e, erc20);

    helperCollectAll(e, userId, erc20);    
    balanceAfter = totalBalance(e, erc20);

    assert balanceBefore == balanceAfter;

    //assert false;  // sanity
}

// rule singleUserTimeUpdateNotChangingOtherUserBalance(method f, uint256 userId) {
//     env e; env eB; env eF;
//     calldataarg args;

//     // uint8 i;

//     // userId1 and userId2 - receivers Id
//     uint256 assetId; uint256 userId1; uint256 userId2;
//     require userId != userId1; // != userId2;
//     require userId1 < userId2; // sorted
//     require userId != userId2;

//     // step 1 - balance before of user2
//     bytes32 dripsHashBefore; bytes32 dripsHistoryHashBefore;
//     uint32 updateTimeBefore; uint128 balanceBefore; uint32 maxEndBefore;

//     dripsHashBefore, dripsHistoryHashBefore, updateTimeBefore,
//      balanceBefore, maxEndBefore = _dripsState(eB, userId2, assetId);
    
//     // assert false; // false 0
    
//     // step 2 - setup user1 changes and then call _updateReceiverStates()
//     /*  //setting values to config by create:
//         uint192 _amtPerSec;
//         uint32 _start;
//         uint32 _duration;
    

//     require _amtPerSec != 0;
//     */
//     DH.DripsConfig configOld1;// = create(_amtPerSec, _start, _duration);
//     DH.DripsConfig configOld2;// = DH.create(_amtPerSec+1, _start+1, _duration+1);
//     DH.DripsConfig configNew1;// = DH.create(_amtPerSec+2, _start+2, _duration+2);
//    // DH.DripsConfig configNew2;

//     require configOld1 != configNew1;
//     // require configOld2 == configNew2;

//     DH.DripsReceiver receiverOld1;
//     require receiverOld1.userId == userId1;
//     require receiverOld1.config == configOld1;
    
//     DH.DripsReceiver receiverOld2;
//     require receiverOld2.userId == userId2;
//     require receiverOld2.config == configOld2;
    
//     DH.DripsReceiver receiverNew1;
//     require receiverNew1.userId == userId1;
//     require receiverNew1.config == configNew1;
    
    


//     // DripsReceiver[] memory currReceivers;
//     // DripsReceiver[] memory newReceivers;
//     // currReceivers[i].userId = userId1;
//     // currReceivers[i].config = configCurr;
//     // require sorted
//     // require no duplicate
//     // require amtPerSec != 0
//     // require(i < _MAX_DRIPS_RECEIVERS,"");
//     // require currReceivers == newReceivers;

//     // newReceivers[i].config = configNew; // the only change in newReceivers is configNew of userId2

//     // DripsState storage state = _dripsStorage().states[assetId][userId];
//     // uint32 lastUpdate = state.updateTime;
//     // uint32 currMaxEnd = state.maxEnd;

//     // uint32 newMaxEnd = sizeof(uint32);
    

//     // assert false;  // false 1
//      //assert configOld2 != configNew2;  //returned 0


//     _helperUpdateReceiverStates( e,
//             receiverOld1,
//             receiverOld2,
//             receiverNew1,
//             assetId,
//             userId
//         );

//     //assert false;  // false 2

//     // step 3 - balance after of user2
//     bytes32 dripsHashAfter; bytes32 dripsHistoryHashAfter;
//     uint32 updateTimeAfter; uint128 balanceAfter; uint32 maxEndAfter;

//     dripsHashAfter, dripsHistoryHashAfter, updateTimeAfter, 
//      balanceAfter, maxEndAfter = _dripsState(eF, userId2, assetId);
    
    
//     // check that balance of user2 was not modified
//     assert balanceBefore == balanceAfter, "balanceOfUser2 changed";

//     assert false;
// }


// rule helperTest(method f, uint256 userId) {
//     env e; 
//     uint256 assetId;
//     DH.DripsReceiver receiverOld1;
//     DH.DripsReceiver receiverOld2;
//     DH.DripsReceiver receiverNew1;


//     _helperUpdateReceiverStates( e,
//             receiverOld1,
//             receiverOld2,
//             receiverNew1,
//             assetId,
//             userId
//         );

//     assert false;  // false 2
//     }


// rule unrelatedUserBalanceNotChangingParametric(
//         method f, uint256 senderId, uint256 receiverId, uint256 assetId) {
//     env e; env eB; env eF;
//     calldataarg args;

//     // step 1 - balance before of receiverId
//     bytes32 dripsHashBefore; bytes32 dripsHistoryHashBefore;
//     uint32 updateTimeBefore; uint128 balanceBefore; uint32 maxEndBefore;

//     dripsHashBefore, dripsHistoryHashBefore, updateTimeBefore,
//      balanceBefore, maxEndBefore = _dripsState(eB, receiverId, assetId);
    
//     uint256 userId1; uint256 config1;
//     uint256 userId2; uint256 config2;
//     uint256 userId3; uint256 config3;

//     userId1, config1, userId2, config2, userId3, config3 = unpackArgs(e, args);

//     DH.DripsReceiver argsReceiver1;
//     require argsReceiver1.userId == userId1;
//     require argsReceiver1.config == config1;
//     DH.DripsReceiver argsReceiver2;
//     require argsReceiver2.userId == userId2;
//     require argsReceiver2.config == config2;
//     DH.DripsReceiver argsReceiver3;
//     require argsReceiver3.userId == userId3;
//     require argsReceiver3.config == config3;


//     require argsReceiver1.userId != receiverId;
//     require argsReceiver2.userId != receiverId;
//     require argsReceiver3.userId != receiverId;

//     f(e, args);

//     //assert false;  // false 2

//     // step 3 - balance after of user2
//     bytes32 dripsHashAfter; bytes32 dripsHistoryHashAfter;
//     uint32 updateTimeAfter; uint128 balanceAfter; uint32 maxEndAfter;

//     dripsHashAfter, dripsHistoryHashAfter, updateTimeAfter, 
//      balanceAfter, maxEndAfter = _dripsState(eF, receiverId, assetId);
    
    
//     // check that balance of user2 was not modified
//     assert balanceBefore == balanceAfter, "balanceOf receiverId changed";

//     //assert false;
// }



// SetDrips - different options:
// ------------------------------
// curr         new
// id1          -
// -            id1
// id1          id1
// id1          id2


// State vars affected by _updateReceiverStates():
// ------------------------------------------------
// _dripsStorage().states[assetId][currRecv.userId].amtDeltas[_cycleOf(timestamp)].thisCycle
// _dripsStorage().states[assetId][currRecv.userId].amtDeltas[__].nextCycle
// _dripsStorage().states[assetId][currRecv.userId].nextReceivableCycle
// 
// _dripsStorage().states[assetId][newRecv.userId].amtDeltas[__].thisCycle
// _dripsStorage().states[assetId][newRecv.userId].amtDeltas[__].nextCycle
// _dripsStorage().states[assetId][newRecv.userId].nextReceivableCycle


// State vars affected by _setDrips() in addition to the above:
// -----------------------------------
// _dripsStorage().states[assetId][userId].updateTime
// _dripsStorage().states[assetId][userId].maxEnd
// _dripsStorage().states[assetId][userId].balance
// _dripsStorage().states[assetId][userId].dripsHistoryHash
// _dripsStorage().states[assetId][userId].dripsHash
