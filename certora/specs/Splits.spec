//// ## Verification of Splits.sol
//// 
//// `Splits.sol` is part of the Drips protocol
//// 
//// The splits functionality, as explained in DripsHub.sol by the developers:
//// The user can share collected funds with other users by using splits.
//// When collecting, the user gives each of their splits receivers a fraction of the received funds.
//// Funds received from splits are available for collection immediately regardless of the cycle.
//// They aren't exempt from being split, so they too can be split when collected.
//// Users can build chains and networks of splits between each other.
//// Anybody can request collection of funds for any user,
//// which can be used to enforce the flow of funds in the network of splits.
//// 
//// ### Assumptions and Simplifications
//// - All the internal methods are wrapped in CVT callable versions
//// - Dummy functions used to control the SplitsReceiver[] receivers
//// - When testing the split weight functionality we safely assumed weight < _TOTAL_SPLITS_WEIGHT
////   since the method _assertSplitsValid() validates them before assignment
//// 
//// ### Properties


/// @notice Calculate results of splitting an amount using the current splits configuration.
/// We verify that amount == collectableAmt + splitAmt
/// Since compiling with Solidity >0.8.0 there are no overflows
rule correctnessOfSplitResults() {
    env e; uint256 userId; uint128 amount; uint128 collectableAmt; uint128 splitAmt;

    collectableAmt, splitAmt = splitResults(e, userId, true, amount);

    assert amount == collectableAmt + splitAmt;
}


/// @notice Splits user's received but not split yet funds among receivers.
/// @param collectableAmt The amount made collectable for the user
/// @param splitAmt The amount split to the user's splits receivers
rule correctnessOfSplit() {
    env e; uint256 userId; uint256 assetId; uint128 collectableAmt; uint128 splitAmt;

    uint128 splittableBefore;   uint128 collectableBefore;
    uint128 splittableAfter;    uint128 collectableAfter;
    
    splittableBefore = splittable(e, userId, assetId);
    collectableBefore = collectable(e, userId, assetId);

    collectableAmt, splitAmt = split(e, userId, assetId, true);

    splittableAfter = splittable(e, userId, assetId);
    collectableAfter = collectable(e, userId, assetId);

    assert splittableBefore >= splittableAfter;
    assert collectableBefore + collectableAmt == collectableAfter;
    assert splittableBefore + collectableBefore >= splittableAfter + collectableAfter;
}


/// @notice Collects user's received already split funds
/// After collection, no more collectable balance should be immediately available
rule integrityOfCollect() {
    env e; uint256 userId; uint256 assetId;
    uint128 collectedAmt; uint128 collectableAfter;

    collectedAmt = collect(e, userId, assetId);
    collectableAfter = collectable(e, userId, assetId);

    assert collectableAfter == 0;
}


/// @notice Calling the method collect() should never revert
rule revertCharacteristicsOfCollect() {
    env e; uint256 userId; uint256 assetId; uint128 collectedAmt;

    require e.msg.sender != 0;  // safe assumption that prevents revert
    require e.msg.value == 0;  // safe assumption that prevents revert

    collectedAmt = collect@withrevert(e, userId, assetId);
    assert !lastReverted;
}


/// @notice The method give() gives funds from the user to the receiver.
/// @param amt The given amount
/// After give of amt, the splittable of the receiver should increase exactly by amt
rule correctnessOfGive() {
    env e; uint256 userId; uint256 receiver; uint256 assetId; uint128 amt;
    uint128 splittableBefore; uint128 splittableAfter;

    splittableBefore = splittable(e, receiver, assetId);
    give(e, userId, receiver, assetId, amt);
    splittableAfter = splittable(e, receiver, assetId);

    assert splittableAfter == splittableBefore + amt;
}


/// @notice The method give() gives funds from the user to the receiver.
/// The splittable of any other user that is not receiver should not change
rule splittableOfNonReceiverNotAffectedByGive() {
    env e; uint256 userId; uint256 receiver; uint256 assetId; uint128 amt;
    uint256 otherUser; uint128 splittableBefore; uint128 splittableAfter;

    require otherUser != receiver;

    splittableBefore = splittable(e, otherUser, assetId);
    give(e, userId, receiver, assetId, amt);
    splittableAfter = splittable(e, otherUser, assetId);

    assert splittableAfter == splittableBefore;
}


/// @notice the method hashSplits() Calculates the hash of the list of splits receivers.
/// We use boolean selector to operate on two different lists of splits receivers.
/// We verify that two calculated hashes are the same only if they got exactly the same input
/// We also verify that different inputs must generate different hashes
rule correctnessOfHashSplits() {
    env e; uint256 index; uint256 length1; uint256 length2;  
    uint256 userId1; uint32 weight1; uint256 userId2; uint32 weight2;
    bytes32 receiversHash1; bytes32 receiversHash2;

    length1 = getCurrSplitsReceiverLocaLength(e, true);
    length2 = getCurrSplitsReceiverLocaLength(e, false);

    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index);
    userId2, weight2 = getCurrSplitsReceiverLocalArr(e, false, index);

    receiversHash1 = hashSplits(e, true);
    receiversHash2 = hashSplits(e, false);

    assert (receiversHash1 == receiversHash2) => ((length1 == length2) && (userId1 == userId2) && (weight1 == weight2));
}


/// @notice Integrity of split:
/// UserA has received drips and he has splittable > 0
/// UserA has a list of splitters that should get some of the drips received
/// UserA calls split()
/// UserB is on the list of UserA's splitters, therefore "userB's splittable should NOT decrease"
/// UserC is NOT on the list of UserA's splitters, therefore "userC's splittable should NOT change"
/// UserA's collectable should NOT decrease, UserB and UserC's collectable should NOT change
rule integrityOfSplit() {
    env e; uint256 assetId;
    uint256 userA_Id; uint256 userB_Id; uint256 userC_Id; uint256 userD_Id;
    
    require userA_Id != userB_Id;   require userA_Id != userD_Id;
    require userA_Id != userC_Id;   require userB_Id != userD_Id;
    require userB_Id != userC_Id;   require userC_Id != userD_Id;

    // obtaining splittable/collectable states before calling split()
    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId);
    require userA_splittableBefore > 0;
    uint128 userA_collectableBefore = collectable(e, userA_Id, assetId);
    uint128 userB_splittableBefore = splittable(e, userB_Id, assetId);
    uint128 userB_collectableBefore = collectable(e, userB_Id, assetId);
    uint128 userC_splittableBefore = splittable(e, userC_Id, assetId);
    uint128 userC_collectableBefore = collectable(e, userC_Id, assetId);
    uint128 userD_splittableBefore = splittable(e, userD_Id, assetId);
    uint128 userD_collectableBefore = collectable(e, userD_Id, assetId);

    // setting up the currReceivers[] of userA
    uint256 index1; uint256 userId1; uint32 weight1;
    uint256 index2; uint256 userId2; uint32 weight2;
    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);
    userId2, weight2 = getCurrSplitsReceiverLocalArr(e, true, index2);

    require index1 != index2;     // different indexes sample different splitReceivers
    require userId1 == userB_Id;  // userB is on the list of splitReceivers of userA
    require userId2 != userC_Id;  // the second splitReceiver is not userC
    require userId2 != userA_Id;  // the second splitReceiver is not the splitter itself
    require userId2 == userD_Id;  // since we run with loop_iter 2, there are max 2 receivers

    // calling the split() on userA
    uint128 userA_collectableAmt;   uint128 userA_splitAmt;
    userA_collectableAmt, userA_splitAmt = split(e, userA_Id, assetId, true);

    // obtaining splittable/collectable states after calling split()
    uint128 userA_splittableAfter = splittable(e, userA_Id, assetId);
    uint128 userA_collectableAfter = collectable(e, userA_Id, assetId);
    uint128 userB_splittableAfter = splittable(e, userB_Id, assetId);
    uint128 userB_collectableAfter = collectable(e, userB_Id, assetId);
    uint128 userC_splittableAfter = splittable(e, userC_Id, assetId);
    uint128 userC_collectableAfter = collectable(e, userC_Id, assetId);
    uint128 userD_splittableAfter = splittable(e, userD_Id, assetId);
    uint128 userD_collectableAfter = collectable(e, userD_Id, assetId);


    // the expectation:
    // UserA's splittable should NOT increase
    assert userA_splittableAfter <= userA_splittableBefore;
    assert userA_splittableAfter == 0; // it should be zero

    // UserB is on the list of UserA's splitters, therefore "userB's splittable should NOT decrease"
    assert userB_splittableAfter >= userB_splittableBefore;

    // UserC is NOT on the list of UserA's splitters, therefore "userC's splittable should NOT change"
    assert userC_splittableAfter == userC_splittableBefore;

    // UserA's collectable should NOT decrease, UserB and UserC's collectable should NOT change
    assert userA_collectableAfter >= userA_collectableBefore;
    assert userB_collectableAfter == userB_collectableBefore;
    assert userC_collectableAfter == userC_collectableBefore;

    // The increase of the splittable of the receivers userB and userD should be equal the splittable of userA
    assert (userB_splittableAfter - userB_splittableBefore) +
           (userD_splittableAfter - userD_splittableBefore) +
           (userA_collectableAfter - userA_collectableBefore) == userA_splittableBefore;
}


/// @notice Different assets should not interfere with each other
/// operations over one assetId1 should not affect anything related to other assetId2
/// calling split on userA with assetId1 should NOT affect 
/// the splittable and collectable for any user's assetId2
rule assetsDoNotInterfereEachOther() {
    env e; uint256 assetId1; uint256 assetId2; uint256 userA_Id; uint256 userB_Id;

    // make sure the users/assets are not the same
    require userA_Id != userB_Id;
    require assetId1 != assetId2;

    // recording the state before split()
    uint128 userA_splittableAssetId1_Before = splittable(e, userA_Id, assetId1);
    uint128 userA_collectableAssetId1_Before = collectable(e, userA_Id, assetId1);
    uint128 userA_splittableAssetId2_Before = splittable(e, userA_Id, assetId2);
    uint128 userA_collectableAssetId2_Before = collectable(e, userA_Id, assetId2);

    uint128 userB_splittableAssetId1_Before = splittable(e, userB_Id, assetId1);
    uint128 userB_collectableAssetId1_Before = collectable(e, userB_Id, assetId1);
    uint128 userB_splittableAssetId2_Before = splittable(e, userB_Id, assetId2);
    uint128 userB_collectableAssetId2_Before = collectable(e, userB_Id, assetId2);

    // calling the split() for userA over assertId1
    uint128 userA_collectableAmtAssetId1; uint128 userA_splitAmtAssetId1;
    userA_collectableAmtAssetId1, userA_splitAmtAssetId1 = split(e, userA_Id, assetId1, true);

    // recording the state after split()
    uint128 userA_splittableAssetId1_After = splittable(e, userA_Id, assetId1);
    uint128 userA_collectableAssetId1_After = collectable(e, userA_Id, assetId1);
    uint128 userA_splittableAssetId2_After = splittable(e, userA_Id, assetId2);
    uint128 userA_collectableAssetId2_After = collectable(e, userA_Id, assetId2);

    uint128 userB_splittableAssetId1_After = splittable(e, userB_Id, assetId1);
    uint128 userB_collectableAssetId1_After = collectable(e, userB_Id, assetId1);
    uint128 userB_splittableAssetId2_After = splittable(e, userB_Id, assetId2);
    uint128 userB_collectableAssetId2_After = collectable(e, userB_Id, assetId2);

    // the expectation:
    // splittable and collectable for any user's assetId2 stays the same
    assert userA_splittableAssetId2_After == userA_splittableAssetId2_Before;
    assert userA_collectableAssetId2_After == userA_collectableAssetId2_Before;

    assert userB_splittableAssetId2_After == userB_splittableAssetId2_Before;
    assert userB_collectableAssetId2_After == userB_collectableAssetId2_Before;
    // the collectable of userB's assetId1 should not be affected by the split
    assert userB_collectableAssetId1_After == userB_collectableAssetId1_Before;
    // the splittable of userB's assetId1 should not decrease
    assert userB_splittableAssetId1_After >= userB_splittableAssetId1_Before;
}


/// @notice Money is not lost or created in the system when split() is called:
/// UserA has splittable balance and one splits receiver - userB,
/// then split() is called on userA
/// We verify that the sum (splittable + collectable) of (userA + userB)
/// are invariant of the split
rule moneyNotLostOrCreatedDuringSplit() {
    env e; uint256 assetId;
    uint256 userA_Id; uint256 userB_Id;

    // setting up the currReceivers[] of userA
    uint256 length; uint256 index1; uint256 userId1; uint32 weight1;
    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);
    length = getCurrSplitsReceiverLocaLength(e, true);
    require length == 1;            // only one splitsReceiver
    require userId1 == userB_Id;    // making sure it is userB (not limiting it to be userA)
    require weight1 <= 1000000;     // safe assumptions since the function _assertSplitsValid()
                                    // verified that totalWeight <= _TOTAL_SPLITS_WEIGHT upon _setSplits()
                                    // we required that there is only one receiver, therefore totalWeight = weight1
                                    // _TOTAL_SPLITS_WEIGHT == 1000000, hence the assumption above is safe

    // recording the state before split()
    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId);
    uint128 userA_collectableBefore = collectable(e, userA_Id, assetId);
    uint128 userB_splittableBefore = splittable(e, userB_Id, assetId);
    uint128 userB_collectableBefore = collectable(e, userB_Id, assetId);

    // calling the split() on userA
    uint128 userA_collectableAmt;   uint128 userA_splitAmt;
    userA_collectableAmt, userA_splitAmt = split(e, userA_Id, assetId, true);

    // recording the state after split()
    uint128 userA_splittableAfter = splittable(e, userA_Id, assetId);
    uint128 userA_collectableAfter = collectable(e, userA_Id, assetId);
    uint128 userB_splittableAfter = splittable(e, userB_Id, assetId);
    uint128 userB_collectableAfter = collectable(e, userB_Id, assetId);

    // the expectation:
    uint128 moneyBefore = userA_splittableBefore + userA_collectableBefore + userB_splittableBefore + userB_collectableBefore;
    uint128 moneyAfter = userA_splittableAfter + userA_collectableAfter + userB_splittableAfter + userB_collectableAfter;
    assert moneyBefore == moneyAfter;
}


/// @notice We verify that splitResults() and split() return the same (collectableAmt, splitAmt)
/// UserA has splittable balance and configured two split receivers - userB, userC
/// first we call splitResults() upon userA with amount = userA.splittable
/// then we call split() upon userA
/// We expect that the returned values of both functions will be the same
rule sameReturnOfSplitAndSplitResults() {
    env e; uint256 assetId; uint256 userA_Id; uint256 userB_Id; uint256 userC_Id;
    require userA_Id != userB_Id;   require userA_Id != userC_Id;   require userB_Id != userC_Id;

    // setting up the currReceivers[] of userA
    uint256 length = getCurrSplitsReceiverLocaLength(e, true);
    uint256 index1; uint256 userId1; uint32 weight1;
    uint256 index2; uint256 userId2; uint32 weight2;

    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);
    userId2, weight2 = getCurrSplitsReceiverLocalArr(e, true, index2);

    require length == 2;
    require index1 != index2;
    require userId1 == userB_Id;
    require userId2 == userC_Id;
    require weight1 > 0;
    require weight2 > 0;
    require weight1 + weight2 <= 1000000;  // safe assumptions
    // safe assumptions since the function _assertSplitsValid()
    // verified that totalWeight <= _TOTAL_SPLITS_WEIGHT upon _setSplits()
    // we force the receivers to be only two, therefore totalWeight = weight1 + weight2
    // _TOTAL_SPLITS_WEIGHT == 1000000, hence the assumption above is safe

    // calling splitResults() upon userA with amount = userA.splittable
    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId);
    uint128 userA_splitAmt_splitResults; uint128 userA_collectableAmt_splitResults;
    userA_collectableAmt_splitResults, userA_splitAmt_splitResults = splitResults(e, userA_Id, true, userA_splittableBefore);
    
    // calling split() on userA
    uint128 userA_collectableAmt_split; uint128 userA_splitAmt_split;
    userA_collectableAmt_split, userA_splitAmt_split = split(e, userA_Id, assetId, true);

    // the expectation:
    assert userA_collectableAmt_split == userA_collectableAmt_splitResults;
    assert userA_splitAmt_split == userA_splitAmt_splitResults;
}


/// @notice Split receiver should get money upon calling split()
/// UserA has splittable balance and one splits receiver - userB,
/// then split() is called on userA
/// We expect that the splittable balance of userB will increase
///
/// Note: this rule fails!
/// In cases when userB weight is small, the calculation for the split
/// will be rounded down to zero, therefore the receiver will get nothing!
///
/// Possible abuse vector:
/// split is called every time when the splittable balance of userA is so low, 
/// so that rounding error will cause the splitReceiver userB to get zero
/// as a result userA will get all the splittable to himself
///
/// Severity: low
/// The one who will benefit the abuse is the splitter,
/// but he is also the one that in advance decided who
/// are going to be his splitReceivers
rule splitReceiverShouldGetMoneyUponSplit() {
    env e; uint256 assetId; uint256 userA_Id; uint256 userB_Id;
    require userA_Id != userB_Id;

    // setting up the currReceivers[] of userA
    uint256 length1 = getCurrSplitsReceiverLocaLength(e, true);
    require length1 == 1;  // only one receiver
    uint256 index1; uint256 userId1; uint32 weight1;
    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);

    require userId1 == userB_Id;
    require weight1 <= 1000000;  // safe assumption
    require weight1 > 0;         // safe assumption
    // safe assumptions since the function _assertSplitsValid()
    // verified that totalWeight <= _TOTAL_SPLITS_WEIGHT upon _setSplits()
    // we required that there is only one receiver, therefore totalWeight = weight1
    // _TOTAL_SPLITS_WEIGHT == 1000000, hence the assumption above is safe
    // also _assertSplitsValid() verified that weight != 0

    // recording the state before split()
    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId);
    require userA_splittableBefore > 0;
    uint128 userA_collectableBefore = collectable(e, userA_Id, assetId);
    uint128 userB_splittableBefore = splittable(e, userB_Id, assetId);
    uint128 userB_collectableBefore = collectable(e, userB_Id, assetId);

    // calling the split() on userA
    uint128 userA_collectableAmt; uint128 userA_splitAmt;
    userA_collectableAmt, userA_splitAmt = split(e, userA_Id, assetId, true);

    // recording the state after split()
    uint128 userA_splittableAfter = splittable(e, userA_Id, assetId);
    uint128 userA_collectableAfter = collectable(e, userA_Id, assetId);
    uint128 userB_splittableAfter = splittable(e, userB_Id, assetId);
    uint128 userB_collectableAfter = collectable(e, userB_Id, assetId);

    // the expectation: the splittable balance of userB should increase
    assert userB_splittableAfter > userB_splittableBefore;
}

/// @notice Users with same weights should get same amount upon split()
/// UserA has splittable balance and configured two split receivers - userB, userC
/// both userB and userC have the same split weights
/// then split() is called on userA
/// We expect that the splittable balances of userB and userC will increase by the same amount (up to 1 point)
rule equalSplitWeightsResultEqualSplittableIncrease() {
    env e; uint256 assetId; uint256 userA_Id; uint256 userB_Id; uint256 userC_Id;


    // all the 3 users are different
    require userA_Id != userB_Id; require userA_Id != userC_Id; require userB_Id != userC_Id;


    // setting up the currReceivers[] of userA
    uint256 index1; uint256 userId1; uint32 weight1; uint256 index2; uint256 userId2; uint32 weight2;
    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);
    userId2, weight2 = getCurrSplitsReceiverLocalArr(e, true, index2);
    uint256 length = getCurrSplitsReceiverLocaLength(e, true);

    require length == 2;            // only two split receivers
    require index1 != index2;       // different indexes sample different splitReceivers
    require userId1 == userB_Id;
    require userId2 == userC_Id;
    require weight1 == weight2;
    require weight1 <= 500000;      // safe assumption since MAX _TOTAL_SPLITS_WEIGHT == 1000000
    require weight1 > 0;            // safe assumption

    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId); 
    uint128 userB_splittableBefore = splittable(e, userB_Id, assetId);
    uint128 userC_splittableBefore = splittable(e, userC_Id, assetId);
    require userA_splittableBefore > 0; // there is a splittable amount to be split

    // calling the split() on userA
    uint128 userA_collectableAmt;   uint128 userA_splitAmt;
    userA_collectableAmt, userA_splitAmt = split(e, userA_Id, assetId, true);

    uint128 userA_splittableAfter = splittable(e, userA_Id, assetId);
    uint128 userB_splittableAfter = splittable(e, userB_Id, assetId);
    uint128 userC_splittableAfter = splittable(e, userC_Id, assetId);

    // the expectation:
    // the splittable balances of userB and userC will increase by the same amount
    // in case of rounding - diffrence between amounts can be 1
    uint128 userB_splittableChange = userB_splittableAfter - userB_splittableBefore;
    uint128 userC_splittableChange = userC_splittableAfter - userC_splittableBefore;
    assert ((userC_splittableChange == userB_splittableChange) || 
            (userB_splittableChange == userC_splittableChange + 1) || 
            (userC_splittableChange == userB_splittableChange + 1));    
}

/*
/// @notice The sanity rule should always fail.
rule sanity {
    method f; env e; calldataarg args;

    f(e, args);

    assert false, 
        "This rule should always fail";
}
*/


/// @notice front running split() does not affect receiver
/// userA has a single splitReceiver userC
/// userB also has the same single splitReceiver UserC
/// we want to verify split() can be called on userA successfully
/// even if someone front runs it and calls splits() first on userB
/// no assumptions about userA, userB, userC
rule cannotFrontRunSplitGeneralCase() {
    env e; env e2; uint256 assetId; uint256 userA_Id; uint256 userB_Id; uint256 userC_Id;
    uint128 userA_collectableAmt; uint128 userA_splitAmt;
    uint128 userA_collectableAmt2; uint128 userA_splitAmt2;
    uint128 userB_collectableAmt; uint128 userB_splitAmt;
    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId);
    uint128 userB_splittableBefore = splittable(e, userB_Id, assetId);
    uint128 userC_splittableBefore = splittable(e, userC_Id, assetId);
    uint128 userA_collectableBefore = collectable(e, userA_Id, assetId);
    uint128 userB_collectableBefore = collectable(e, userB_Id, assetId);
    uint128 userC_collectableBefore = collectable(e, userC_Id, assetId);

    // prevents overflow of the splittable of the receiver userC:
    require userA_splittableBefore + userB_splittableBefore + userC_splittableBefore < 2^128;
    // prevents overflow of the collectable of the splitters userA and userB:
    require userA_collectableBefore + userA_splittableBefore < 2^128;
    require userB_collectableBefore + userB_splittableBefore < 2^128;
    // prevents overflow in the edge cases of (userC == userA) or (userC == userB):
    require userA_collectableBefore + userA_splittableBefore + userB_splittableBefore < 2^128;
    require userB_collectableBefore + userB_splittableBefore + userA_splittableBefore < 2^128;
    
    // setting up the currReceivers[] of userA and userB to be the same - singe receiver userC
    uint256 length1 = getCurrSplitsReceiverLocaLength(e, true);
    require length1 == 1;  // only one receiver
    uint256 index1; uint256 userId1; uint32 weight1;
    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);

    require userId1 == userC_Id;
    require weight1 <= 1000000;  // safe assumption
    require weight1 > 0;  // safe assumption
    // safe assumptions since the function _assertSplitsValid()
    // verified that totalWeight <= _TOTAL_SPLITS_WEIGHT upon _setSplits()
    // we required that there is only one receiver, therefore totalWeight = weight1
    // _TOTAL_SPLITS_WEIGHT == 1000000, hence the assumption above is safe
    // also _assertSplitsValid() verified that weight != 0

    storage initStorage = lastStorage;

    userA_collectableAmt, userA_splitAmt = split(e, userA_Id, assetId, true);
    uint128 userC_splittableAfterSplitA = splittable(e, userC_Id, assetId);
    
    userB_collectableAmt, userB_splitAmt = split(e, userB_Id, assetId, true) at initStorage;
    uint128 userC_splittableAfterSplitB = splittable(e, userC_Id, assetId);

    userA_collectableAmt2, userA_splitAmt2 = split@withrevert(e, userA_Id, assetId, true);
    assert !lastReverted;
}


/// @notice front running split() does not affect receiver
/// userA has a single splitReceiver userC
/// userB also has the same single splitReceiver UserC
/// we want to verify split() can be called on userA successfully
/// even if someone front runs it and calls splits() first on userB
/// first we prove in the case userA != userB != userC
rule cannotFrontRunSplitDifferentUsers() {
    env e; env e2; uint256 assetId; uint256 userA_Id; uint256 userB_Id; uint256 userC_Id;
    uint128 userA_collectableAmt; uint128 userA_splitAmt;
    uint128 userA_collectableAmt2; uint128 userA_splitAmt2;
    uint128 userB_collectableAmt; uint128 userB_splitAmt;
    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId);
    uint128 userB_splittableBefore = splittable(e, userB_Id, assetId);
    uint128 userC_splittableBefore = splittable(e, userC_Id, assetId);
    uint128 userA_collectableBefore = collectable(e, userA_Id, assetId);
    uint128 userB_collectableBefore = collectable(e, userB_Id, assetId);
    uint128 userC_collectableBefore = collectable(e, userC_Id, assetId);

    require userA_Id != userB_Id;
    require userA_Id != userC_Id;
    require userB_Id != userC_Id;

    // prevents overflow of the splittable of the receiver userC:
    require userA_splittableBefore + userB_splittableBefore + userC_splittableBefore < 2^128;
    // prevents overflow of the collectable of the splitters userA and userB:
    //require userA_collectableBefore + userA_splittableBefore < 2^128;
    //require userB_collectableBefore + userB_splittableBefore < 2^128;
    // prevents overflow in the edge cases of (userC == userA) or (userC == userB):
    //require userA_collectableBefore + userA_splittableBefore + userB_splittableBefore < 2^128;
    //require userB_collectableBefore + userB_splittableBefore + userA_splittableBefore < 2^128;
    
    // setting up the currReceivers[] of userA and userB to be the same - singe receiver userC
    uint256 length1 = getCurrSplitsReceiverLocaLength(e, true);
    require length1 == 1;  // only one receiver
    uint256 index1; uint256 userId1; uint32 weight1;
    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);

    require userId1 == userC_Id;
    require weight1 <= 1000000;  // safe assumption
    require weight1 > 0;  // safe assumption
    // safe assumptions since the function _assertSplitsValid()
    // verified that totalWeight <= _TOTAL_SPLITS_WEIGHT upon _setSplits()
    // we required that there is only one receiver, therefore totalWeight = weight1
    // _TOTAL_SPLITS_WEIGHT == 1000000, hence the assumption above is safe
    // also _assertSplitsValid() verified that weight != 0

    storage initStorage = lastStorage;

    userA_collectableAmt, userA_splitAmt = split(e, userA_Id, assetId, true);
    uint128 userC_splittableAfterSplitA = splittable(e, userC_Id, assetId);
    
    userB_collectableAmt, userB_splitAmt = split(e, userB_Id, assetId, true) at initStorage;
    uint128 userC_splittableAfterSplitB = splittable(e, userC_Id, assetId);

    userA_collectableAmt2, userA_splitAmt2 = split@withrevert(e, userA_Id, assetId, true);
    assert !lastReverted;
}


/// next we prove in the case (userA != userB) with appropriate require
rule cannotFrontRunSplitTwoSameUsers() {
    env e; env e2; uint256 assetId; uint256 userA_Id; uint256 userB_Id; uint256 userC_Id;
    uint128 userA_collectableAmt; uint128 userA_splitAmt;
    uint128 userA_collectableAmt2; uint128 userA_splitAmt2;
    uint128 userB_collectableAmt; uint128 userB_splitAmt;
    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId);
    uint128 userB_splittableBefore = splittable(e, userB_Id, assetId);
    uint128 userC_splittableBefore = splittable(e, userC_Id, assetId);
    uint128 userA_collectableBefore = collectable(e, userA_Id, assetId);
    uint128 userB_collectableBefore = collectable(e, userB_Id, assetId);
    uint128 userC_collectableBefore = collectable(e, userC_Id, assetId);

    require ( (userA_Id != userB_Id) && 
             ((userC_Id == userA_Id) || (userC_Id == userB_Id)) );

    // prevents overflow in the edge cases of (userC == userA) or (userC == userB):
    require userA_collectableBefore + userA_splittableBefore + userB_splittableBefore < 2^128;
    require userB_collectableBefore + userB_splittableBefore + userA_splittableBefore < 2^128;
    
    // setting up the currReceivers[] of userA and userB to be the same - singe receiver userC
    uint256 length1 = getCurrSplitsReceiverLocaLength(e, true);
    require length1 == 1;  // only one receiver
    uint256 index1; uint256 userId1; uint32 weight1;
    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);

    require userId1 == userC_Id;
    require weight1 <= 1000000;  // safe assumption
    require weight1 > 0;  // safe assumption
    // safe assumptions since the function _assertSplitsValid()
    // verified that totalWeight <= _TOTAL_SPLITS_WEIGHT upon _setSplits()
    // we required that there is only one receiver, therefore totalWeight = weight1
    // _TOTAL_SPLITS_WEIGHT == 1000000, hence the assumption above is safe
    // also _assertSplitsValid() verified that weight != 0

    storage initStorage = lastStorage;

    userA_collectableAmt, userA_splitAmt = split(e, userA_Id, assetId, true);
    uint128 userC_splittableAfterSplitA = splittable(e, userC_Id, assetId);
    
    userB_collectableAmt, userB_splitAmt = split(e, userB_Id, assetId, true) at initStorage;
    uint128 userC_splittableAfterSplitB = splittable(e, userC_Id, assetId);

    userA_collectableAmt2, userA_splitAmt2 = split@withrevert(e, userA_Id, assetId, true);
    assert !lastReverted;
}


/// finally we prove in the edge case (userA == userB == userC)
rule cannotFrontRunSplitThreeSameUsers() {
    env e; env e2; uint256 assetId; uint256 userA_Id; uint256 userB_Id; uint256 userC_Id;
    uint128 userA_collectableAmt; uint128 userA_splitAmt;
    uint128 userA_collectableAmt2; uint128 userA_splitAmt2;
    uint128 userB_collectableAmt; uint128 userB_splitAmt;
    uint128 userA_splittableBefore = splittable(e, userA_Id, assetId);
    uint128 userB_splittableBefore = splittable(e, userB_Id, assetId);
    uint128 userC_splittableBefore = splittable(e, userC_Id, assetId);
    uint128 userA_collectableBefore = collectable(e, userA_Id, assetId);
    uint128 userB_collectableBefore = collectable(e, userB_Id, assetId);
    uint128 userC_collectableBefore = collectable(e, userC_Id, assetId);

    require ( (userA_Id == userB_Id) && (userB_Id == userC_Id) );

    // prevents overflow in the edge cases of (userA == userB == userC):
    require userA_collectableBefore + userA_splittableBefore < 2^128;    
    
    // setting up the currReceivers[] of userA and userB to be the same - singe receiver userC
    uint256 length1 = getCurrSplitsReceiverLocaLength(e, true);
    require length1 == 1;  // only one receiver
    uint256 index1; uint256 userId1; uint32 weight1;
    userId1, weight1 = getCurrSplitsReceiverLocalArr(e, true, index1);

    require userId1 == userC_Id;
    require weight1 <= 1000000;  // safe assumption
    require weight1 > 0;  // safe assumption
    // safe assumptions since the function _assertSplitsValid()
    // verified that totalWeight <= _TOTAL_SPLITS_WEIGHT upon _setSplits()
    // we required that there is only one receiver, therefore totalWeight = weight1
    // _TOTAL_SPLITS_WEIGHT == 1000000, hence the assumption above is safe
    // also _assertSplitsValid() verified that weight != 0

    storage initStorage = lastStorage;

    userA_collectableAmt, userA_splitAmt = split(e, userA_Id, assetId, true);
    uint128 userC_splittableAfterSplitA = splittable(e, userC_Id, assetId);
    
    userB_collectableAmt, userB_splitAmt = split(e, userB_Id, assetId, true) at initStorage;
    uint128 userC_splittableAfterSplitB = splittable(e, userC_Id, assetId);

    userA_collectableAmt2, userA_splitAmt2 = split@withrevert(e, userA_Id, assetId, true);
    assert !lastReverted;
}
