// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Drips, DripsConfig, DripsHistory, DripsConfigImpl, DripsReceiver} from "./Drips.sol";
import {Managed} from "./Managed.sol";
import {Splits, SplitsReceiver} from "./Splits.sol";
import {IReserve} from "./Reserve.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice Drips hub contract. Automatically drips and splits funds between users.
///
/// The user can transfer some funds to their drips balance in the contract
/// and configure a list of receivers, to whom they want to drip these funds.
/// As soon as the drips balance is enough to cover at least 1 second of dripping
/// to the configured receivers, the funds start dripping automatically.
/// Every second funds are deducted from the drips balance and moved to their receivers.
/// The process stops automatically when the drips balance is not enough to cover another second.
///
/// Every user has a receiver balance, in which they have funds received from other users.
/// The dripped funds are added to the receiver balances in global cycles.
/// Every `cycleSecs` seconds the drips hub adds dripped funds to the receivers' balances,
/// so recently dripped funds may not be receivable immediately.
/// `cycleSecs` is a constant configured when the drips hub is deployed.
/// The receiver balance is independent from the drips balance,
/// to drip received funds they need to be first collected and then added to the drips balance.
///
/// The user can share collected funds with other users by using splits.
/// When collecting, the user gives each of their splits receivers a fraction of the received funds.
/// Funds received from splits are available for collection immediately regardless of the cycle.
/// They aren't exempt from being split, so they too can be split when collected.
/// Users can build chains and networks of splits between each other.
/// Anybody can request collection of funds for any user,
/// which can be used to enforce the flow of funds in the network of splits.
///
/// The concept of something happening periodically, e.g. every second or every `cycleSecs` are
/// only high-level abstractions for the user, Ethereum isn't really capable of scheduling work.
/// The actual implementation emulates that behavior by calculating the results of the scheduled
/// events based on how many seconds have passed and only when the user needs their outcomes.
///
/// The contract can store at most `type(int128).max` which is `2 ^ 127 - 1` units of each token.
contract DripsHub is Managed, Drips, Splits {
    /// @notice The address of the ERC-20 reserve which the drips hub works with
    IReserve public immutable reserve;
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits cost of changes in drips configuration.
    uint8 public constant MAX_DRIPS_RECEIVERS = _MAX_DRIPS_RECEIVERS;
    /// @notice The additional decimals for all amtPerSec values.
    uint8 public constant AMT_PER_SEC_EXTRA_DECIMALS = _AMT_PER_SEC_EXTRA_DECIMALS;
    /// @notice The multiplier for all amtPerSec values.
    uint256 public constant AMT_PER_SEC_MULTIPLIER = _AMT_PER_SEC_MULTIPLIER;
    /// @notice Maximum number of splits receivers of a single user.
    /// Limits cost of collecting.
    uint32 public constant MAX_SPLITS_RECEIVERS = _MAX_SPLITS_RECEIVERS;
    /// @notice The total splits weight of a user
    uint32 public constant TOTAL_SPLITS_WEIGHT = _TOTAL_SPLITS_WEIGHT;
    /// @notice The offset of the controlling app ID in the user ID.
    /// In other words the controlling app ID is the higest 32 bits of the user ID.
    uint256 public constant APP_ID_OFFSET = 224;
    /// @notice The total amount the contract can store of each token.
    uint256 public constant MAX_TOTAL_BALANCE = _MAX_TOTAL_DRIPS_BALANCE;
    /// @notice The ERC-1967 storage slot holding a single `DripsHubStorage` structure.
    bytes32 private immutable _storageSlot = erc1967Slot("eip1967.dripsHub.storage");

    /// @notice Emitted when an app is registered
    /// @param appId The app ID
    /// @param appAddr The app address
    event AppRegistered(uint32 indexed appId, address indexed appAddr);

    /// @notice Emitted when an app address is updated
    /// @param appId The app ID
    /// @param oldAppAddr The old app address
    /// @param newAppAddr The new app address
    event AppAddressUpdated(
        uint32 indexed appId, address indexed oldAppAddr, address indexed newAppAddr
    );

    struct DripsHubStorage {
        /// @notice The next app ID that will be used when registering.
        uint32 nextAppId;
        /// @notice App addresses. The key is the app ID, the value is the app address.
        mapping(uint32 => address) appAddrs;
        /// @notice The total amount currently stored in DripsHub of each token.
        mapping(IERC20 => uint256) totalBalances;
    }

    /// @param cycleSecs_ The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being receivable by their receivers.
    /// High value makes receiving cheaper by making it process less cycles for a given time range.
    /// Must be higher than 1.
    /// @param reserve_ The address of the ERC-20 reserve which the drips hub will work with
    constructor(uint32 cycleSecs_, IReserve reserve_)
        Drips(cycleSecs_, erc1967Slot("eip1967.drips.storage"))
        Splits(erc1967Slot("eip1967.splits.storage"))
    {
        reserve = reserve_;
    }

    /// @notice A modifier making functions callable only by the app controlling the user ID.
    /// @param userId The user ID.
    modifier onlyApp(uint256 userId) {
        uint32 appId = uint32(userId >> APP_ID_OFFSET);
        _assertCallerIsApp(appId);
        _;
    }

    function _assertCallerIsApp(uint32 appId) internal view {
        require(appAddress(appId) == msg.sender, "Callable only by the app");
    }

    /// @notice Registers an app.
    /// The app is assigned a unique ID and a range of user IDs it can control.
    /// That range consists of all 2^224 user IDs with highest 32 bits equal to the app ID.
    /// Multiple apps can have the same address, it can then control all of them.
    /// @return appId The registered app ID.
    function registerApp(address appAddr) public whenNotPaused returns (uint32 appId) {
        DripsHubStorage storage dripsHubStorage = _dripsHubStorage();
        appId = dripsHubStorage.nextAppId++;
        dripsHubStorage.appAddrs[appId] = appAddr;
        emit AppRegistered(appId, appAddr);
    }

    /// @notice Returns the app address.
    /// @param appId The app ID to look up.
    /// @return appAddr The address of the app.
    /// If the app hasn't been registered yet, returns address 0.
    function appAddress(uint32 appId) public view returns (address appAddr) {
        return _dripsHubStorage().appAddrs[appId];
    }

    /// @notice Updates the app address. Must be called from the current app address.
    /// @param appId The app ID.
    /// @param newAppAddr The new address of the app.
    function updateAppAddress(uint32 appId, address newAppAddr) public whenNotPaused {
        _assertCallerIsApp(appId);
        _dripsHubStorage().appAddrs[appId] = newAppAddr;
        emit AppAddressUpdated(appId, msg.sender, newAppAddr);
    }

    /// @notice Returns the app ID which will be assigned for the next registered app.
    /// @return appId The next app ID.
    function nextAppId() public view returns (uint32 appId) {
        return _dripsHubStorage().nextAppId;
    }

    /// @notice Returns the cycle length in seconds.
    /// On every timestamp `T`, which is a multiple of `cycleSecs`, the receivers
    /// gain access to drips received during `T - cycleSecs` to `T - 1`.
    /// Always higher than 1.
    /// @return cycleSecs_ The cycle length in seconds.
    function cycleSecs() public view returns (uint32 cycleSecs_) {
        return Drips._cycleSecs;
    }

    /// @notice Returns the total amount currently stored in DripsHub of the given token.
    /// @param erc20 The ERC-20 token
    /// @return balance The balance of the token.
    function totalBalance(IERC20 erc20) public view returns (uint256 balance) {
        return _dripsHubStorage().totalBalances[erc20];
    }

    /// @notice Returns amount of received funds available for collection for a user.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectedAmt The collected amount
    /// @return splitAmt The amount split to the user's splits receivers
    function collectableAll(uint256 userId, IERC20 erc20, SplitsReceiver[] memory currReceivers)
        public
        view
        returns (uint128 collectedAmt, uint128 splitAmt)
    {
        uint256 assetId = _assetId(erc20);
        // Receivable from cycles
        (uint128 receivedAmt,) = Drips._receivableDrips(userId, assetId, type(uint32).max);
        // Collectable independently from cycles
        receivedAmt += Splits._splittable(userId, assetId);
        // Split when collected
        (collectedAmt, splitAmt) = Splits._splitResults(userId, currReceivers, receivedAmt);
        // Already split
        collectedAmt += Splits._collectable(userId, assetId);
    }

    /// @notice Collects all received funds available for the user
    /// and transfers them out of the drips hub contract to msg.sender.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectedAmt The collected amount
    /// @return splitAmt The amount split to the user's splits receivers
    function collectAll(uint256 userId, IERC20 erc20, SplitsReceiver[] memory currReceivers)
        public
        whenNotPaused
        returns (uint128 collectedAmt, uint128 splitAmt)
    {
        receiveDrips(userId, erc20, type(uint32).max);
        (, splitAmt) = split(userId, erc20, currReceivers);
        collectedAmt = collect(userId, erc20);
    }

    /// @notice Counts cycles from which drips can be collected.
    /// This function can be used to detect that there are
    /// too many cycles to analyze in a single transaction.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @return cycles The number of cycles which can be flushed
    function receivableDripsCycles(uint256 userId, IERC20 erc20)
        public
        view
        returns (uint32 cycles)
    {
        return Drips._receivableDripsCycles(userId, _assetId(erc20));
    }

    /// @notice Calculate effects of calling `receiveDrips` with the given parameters.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivableAmt The amount which would be received
    /// @return receivableCycles The number of cycles which would still be receivable after the call
    function receivableDrips(uint256 userId, IERC20 erc20, uint32 maxCycles)
        public
        view
        returns (uint128 receivableAmt, uint32 receivableCycles)
    {
        return Drips._receivableDrips(userId, _assetId(erc20), maxCycles);
    }

    /// @notice Receive drips for the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// Calling this function does not collect but makes the funds ready to be split and collected.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The received amount
    /// @return receivableCycles The number of cycles which still can be received
    function receiveDrips(uint256 userId, IERC20 erc20, uint32 maxCycles)
        public
        whenNotPaused
        returns (uint128 receivedAmt, uint32 receivableCycles)
    {
        uint256 assetId = _assetId(erc20);
        (receivedAmt, receivableCycles) = Drips._receiveDrips(userId, assetId, maxCycles);
        if (receivedAmt > 0) {
            Splits._give(userId, userId, assetId, receivedAmt);
        }
    }

    /// @notice Receive drips from the currently running cycle from a single sender.
    /// It doesn't receive drips from the previous, finished cycles, to do that use `receiveDrips`.
    /// Squeezed funds won't be received in the next calls to `squeezeDrips` or `receiveDrips`.
    /// Only funds dripped from `nextSqueezedDrips` to `block.timestamp` can be squeezed.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param erc20 The used ERC-20 token.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @param historyHash The sender's history hash which was valid right before
    /// they set up the sequence of configurations described by `dripsHistory`.
    /// @param dripsHistory The sequence of the sender's drips configurations.
    /// It can start at an arbitrary past configuration, but must describe all the configurations
    /// which have been used since then including the current one, in the chronological order.
    /// Only drips described by `dripsHistory` will be squeezed.
    /// If `dripsHistory` entries have no receivers, they won't be squeezed.
    /// The next call to `squeezeDrips` will be able to squeeze only funds which
    /// have been dripped after the last timestamp squeezed in this call.
    /// This may cause some funds to be unreceivable until the current cycle ends
    /// and they can be received using `receiveDrips`.
    /// @return amt The squeezed amount.
    /// @return nextSqueezed The next timestamp that can be squeezed.
    function squeezeDrips(
        uint256 userId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    )
        public
        whenNotPaused
        returns (uint128 amt, uint32 nextSqueezed)
    {
        uint256 assetId = _assetId(erc20);
        (amt, nextSqueezed) =
            Drips._squeezeDrips(userId, assetId, senderId, historyHash, dripsHistory);
        if (amt > 0) {
            Splits._give(userId, userId, assetId, amt);
        }
    }

    /// @notice Calculate effects of calling `squeezeDrips` with the given parameters.
    /// See its documentation for more details.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param erc20 The used ERC-20 token.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @param historyHash The sender's history hash which was valid right before `dripsHistory`.
    /// @param dripsHistory The sequence of the sender's drips configurations.
    /// @return amt The squeezed amount.
    /// @return nextSqueezed The next timestamp that can be squeezed.
    function squeezableDrips(
        uint256 userId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    )
        public
        view
        returns (uint128 amt, uint32 nextSqueezed)
    {
        return Drips._squeezableDrips(userId, _assetId(erc20), senderId, historyHash, dripsHistory);
    }

    /// @notice Get the next timestamp for which the user can squeeze drips from the sender.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param erc20 The used ERC-20 token.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @return nextSqueezed The next timestamp that can be squeezed.
    function nextSqueezedDrips(uint256 userId, IERC20 erc20, uint256 senderId)
        public
        view
        returns (uint32 nextSqueezed)
    {
        return Drips._nextSqueezedDrips(userId, _assetId(erc20), senderId);
    }

    /// @notice Returns user's received but not split yet funds.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// @return amt The amount received but not split yet.
    function splittable(uint256 userId, IERC20 erc20) public view returns (uint128 amt) {
        return Splits._splittable(userId, _assetId(erc20));
    }

    /// @notice Splits user's received but not split yet funds among receivers.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectableAmt The amount made collectable for the user
    /// on top of what was collectable before.
    /// @return splitAmt The amount split to the user's splits receivers
    function split(uint256 userId, IERC20 erc20, SplitsReceiver[] memory currReceivers)
        public
        whenNotPaused
        returns (uint128 collectableAmt, uint128 splitAmt)
    {
        return Splits._split(userId, _assetId(erc20), currReceivers);
    }

    /// @notice Returns user's received funds already split and ready to be collected.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// @return amt The collectable amount.
    function collectable(uint256 userId, IERC20 erc20) public view returns (uint128 amt) {
        return Splits._collectable(userId, _assetId(erc20));
    }

    /// @notice Collects user's received already split funds
    /// and transfers them out of the drips hub contract to msg.sender.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @return amt The collected amount
    function collect(uint256 userId, IERC20 erc20)
        public
        whenNotPaused
        onlyApp(userId)
        returns (uint128 amt)
    {
        amt = Splits._collect(userId, _assetId(erc20));
        decreaseTotalBalance(erc20, amt);
        reserve.withdraw(erc20, msg.sender, amt);
    }

    /// @notice Gives funds from the user to the receiver.
    /// The receiver can split and collect them immediately.
    /// Transfers the funds to be given from the user's wallet to the drips hub contract.
    /// @param userId The user ID
    /// @param receiver The receiver
    /// @param erc20 The used ERC-20 token
    /// @param amt The given amount
    function give(uint256 userId, uint256 receiver, IERC20 erc20, uint128 amt)
        public
        whenNotPaused
        onlyApp(userId)
    {
        increaseTotalBalance(erc20, amt);
        Splits._give(userId, receiver, _assetId(erc20), amt);
        reserve.deposit(erc20, msg.sender, amt);
    }

    /// @notice Current user drips state.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @return dripsHash The current drips receivers list hash, see `hashDrips`
    /// @return dripsHistoryHash The current drips history hash, see `hashDripsHistory`.
    /// @return updateTime The time when drips have been configured for the last time
    /// @return balance The balance when drips have been configured for the last time
    /// @return maxEnd The current maximum end time of drips
    function dripsState(uint256 userId, IERC20 erc20)
        public
        view
        returns (
            bytes32 dripsHash,
            bytes32 dripsHistoryHash,
            uint32 updateTime,
            uint128 balance,
            uint32 maxEnd
        )
    {
        return Drips._dripsState(userId, _assetId(erc20));
    }

    /// @notice User drips balance at a given timestamp
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @param receivers The current drips receivers list
    /// @param timestamp The timestamps for which balance should be calculated.
    /// It can't be lower than the timestamp of the last call to `setDrips`.
    /// If it's bigger than `block.timestamp`, then it's a prediction assuming
    /// that `setDrips` won't be called before `timestamp`.
    /// @return balance The user balance on `timestamp`
    function balanceAt(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver[] memory receivers,
        uint32 timestamp
    )
        public
        view
        returns (uint128 balance)
    {
        return Drips._balanceAt(userId, _assetId(erc20), receivers, timestamp);
    }

    /// @notice Sets the user's drips configuration.
    /// Transfers funds between the user's wallet and the drips hub contract
    /// to fulfill the change of the drips balance.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the user to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the user.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    )
        public
        whenNotPaused
        onlyApp(userId)
        returns (uint128 newBalance, int128 realBalanceDelta)
    {
        if (balanceDelta > 0) {
            increaseTotalBalance(erc20, uint128(balanceDelta));
        }
        (newBalance, realBalanceDelta) =
            Drips._setDrips(userId, _assetId(erc20), currReceivers, balanceDelta, newReceivers);
        if (realBalanceDelta > 0) {
            reserve.deposit(erc20, msg.sender, uint128(realBalanceDelta));
        } else if (realBalanceDelta < 0) {
            decreaseTotalBalance(erc20, uint128(-realBalanceDelta));
            reserve.withdraw(erc20, msg.sender, uint128(-realBalanceDelta));
        }
    }

    /// @notice Calculates the hash of the drips configuration.
    /// It's used to verify if drips configuration is the previously set one.
    /// @param receivers The list of the drips receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// If the drips have never been updated, pass an empty array.
    /// @return dripsHash The hash of the drips configuration
    function hashDrips(DripsReceiver[] memory receivers) public pure returns (bytes32 dripsHash) {
        return Drips._hashDrips(receivers);
    }

    /// @notice Calculates the hash of the drips history after the drips configuration is updated.
    /// @param oldDripsHistoryHash The history hash which was valid before the drips were updated.
    /// The `dripsHistoryHash` of a user before they set drips for the first time is `0`.
    /// @param dripsHash The hash of the drips receivers being set.
    /// @param updateTime The timestamp when the drips are updated.
    /// @param maxEnd The maximum end of the drips being set.
    /// @return dripsHistoryHash The hash of the updated drips history.
    function hashDripsHistory(
        bytes32 oldDripsHistoryHash,
        bytes32 dripsHash,
        uint32 updateTime,
        uint32 maxEnd
    )
        public
        pure
        returns (bytes32 dripsHistoryHash)
    {
        return Drips._hashDripsHistory(oldDripsHistoryHash, dripsHash, updateTime, maxEnd);
    }

    /// @notice Sets user splits configuration.
    /// @param userId The user ID
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' id's, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    function setSplits(uint256 userId, SplitsReceiver[] memory receivers)
        public
        whenNotPaused
        onlyApp(userId)
    {
        Splits._setSplits(userId, receivers);
    }

    /// @notice Current user's splits hash, see `hashSplits`.
    /// @param userId The user ID
    /// @return currSplitsHash The current user's splits hash
    function splitsHash(uint256 userId) public view returns (bytes32 currSplitsHash) {
        return Splits._splitsHash(userId);
    }

    /// @notice Calculates the hash of the list of splits receivers.
    /// @param receivers The list of the splits receivers.
    /// Must be sorted by the splits receivers' id's, deduplicated and without 0 weights.
    /// @return receiversHash The hash of the list of splits receivers.
    function hashSplits(SplitsReceiver[] memory receivers)
        public
        pure
        returns (bytes32 receiversHash)
    {
        return Splits._hashSplits(receivers);
    }

    /// @notice Returns the DripsHub storage.
    /// @return storageRef The storage.
    function _dripsHubStorage() internal view returns (DripsHubStorage storage storageRef) {
        bytes32 slot = _storageSlot;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            storageRef.slot := slot
        }
    }

    function increaseTotalBalance(IERC20 erc20, uint128 amt) internal {
        mapping(IERC20 => uint256) storage totalBalances = _dripsHubStorage().totalBalances;
        require(totalBalances[erc20] + amt <= MAX_TOTAL_BALANCE, "Total balance too high");
        totalBalances[erc20] += amt;
    }

    function decreaseTotalBalance(IERC20 erc20, uint128 amt) internal {
        _dripsHubStorage().totalBalances[erc20] -= amt;
    }

    /// @notice Generates an asset ID for the ERC-20 token
    /// @param erc20 The ERC-20 token
    /// @return assetId The asset ID
    function _assetId(IERC20 erc20) internal pure returns (uint256 assetId) {
        return uint160(address(erc20));
    }
}
