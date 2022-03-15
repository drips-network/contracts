// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

struct DripsReceiver {
    uint256 userId;
    uint128 amtPerSec;
}

struct SplitsReceiver {
    uint256 userId;
    uint32 weight;
}

/// @notice Drips hub contract. Automatically drips and splits funds between users.
///
/// The user can transfer some funds to their drips balance in the contract
/// and configure a list of receivers, to whom they want to drip these funds.
/// As soon as the drips balance is enough to cover at least 1 second of dripping
/// to the configured receivers, the funds start dripping automatically.
/// Every second funds are deducted from the drips balance and moved to their receivers' accounts.
/// The process stops automatically when the drips balance is not enough to cover another second.
///
/// The user can have any number of independent configurations and drips balances by using accounts.
/// An account is identified by the user address and an account identifier.
/// Accounts of different users are separate entities, even if they have the same identifiers.
/// An account can be used to drip or give, but not to receive funds.
///
/// Every user has a receiver balance, in which they have funds received from other users.
/// The dripped funds are added to the receiver balances in global cycles.
/// Every `cycleSecs` seconds the drips hub adds dripped funds to the receivers' balances,
/// so recently dripped funds may not be collectable immediately.
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
/// The contract assumes that all amounts in the system can be stored in signed 128-bit integers.
/// It's guaranteed to be safe only when working with assets with supply lower than `2 ^ 127`.
abstract contract DripsHub {
    /// @notice On every timestamp `T`, which is a multiple of `cycleSecs`, the receivers
    /// gain access to drips collected during `T - cycleSecs` to `T - 1`.
    uint64 public immutable cycleSecs;
    /// @notice Timestamp at which all drips must be finished
    uint64 internal constant MAX_TIMESTAMP = type(uint64).max - 2;
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits cost of changes in drips configuration.
    uint32 public constant MAX_DRIPS_RECEIVERS = 100;
    /// @notice Maximum number of splits receivers of a single user.
    /// Limits cost of collecting.
    uint32 public constant MAX_SPLITS_RECEIVERS = 200;
    /// @notice The total splits weight of a user
    uint32 public constant TOTAL_SPLITS_WEIGHT = 1_000_000;
    /// @notice Number of bits in the sub-account part of userId
    uint256 public constant BITS_SUB_ACCOUNT = 224;

    /// @notice Emitted when drips from a user to a receiver are updated.
    /// Funds are being dripped on every second between the event block's timestamp (inclusively)
    /// and`endTime` (exclusively) or until the timestamp of the next drips update (exclusively).
    /// @param userId The dripping user ID.
    /// @param receiver The receiver user ID
    /// @param assetId The used asset ID
    /// @param amtPerSec The new amount per second dripped from the user
    /// to the receiver or 0 if the drips are stopped
    /// @param endTime The timestamp when dripping will stop,
    /// always larger than the block timestamp or equal to it if the drips are stopped
    event Dripping(
        uint256 indexed userId,
        uint256 indexed receiver,
        uint256 assetId,
        uint128 amtPerSec,
        uint64 endTime
    );

    /// @notice Emitted when the drips configuration of a user is updated.
    /// @param userId The user ID.
    /// @param assetId The used asset ID
    /// @param balance The new drips balance. These funds will be dripped to the receivers.
    /// @param receivers The new list of the drips receivers.
    event DripsUpdated(
        uint256 indexed userId,
        uint256 assetId,
        uint128 balance,
        DripsReceiver[] receivers
    );

    /// @notice Emitted when the user's splits are updated.
    /// @param user The user
    /// @param receivers The list of the user's splits receivers.
    event SplitsUpdated(uint256 indexed user, SplitsReceiver[] receivers);

    /// @notice Emitted when a user collects funds
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param collected The collected amount
    event Collected(address indexed user, uint256 assetId, uint128 collected);

    /// @notice Emitted when funds are split from a user to a receiver.
    /// This is caused by the user collecting received funds.
    /// @param user The user
    /// @param receiver The splits receiver user ID
    /// @param assetId The used asset ID
    /// @param amt The amount split to the receiver
    event Split(address indexed user, uint256 indexed receiver, uint256 assetId, uint128 amt);

    /// @notice Emitted when funds are made collectable after splitting.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param amt The amount made collectable for the user on top of what was collectable before.
    event Collectable(address indexed user, uint256 assetId, uint128 amt);

    /// @notice Emitted when drips are received and are ready to be split.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param amt The received amount.
    /// @param receivableCycles The number of cycles which still can be received.
    event ReceivedDrips(
        address indexed user,
        uint256 assetId,
        uint128 amt,
        uint64 receivableCycles
    );

    /// @notice Emitted when funds are given from the user to the receiver.
    /// @param userId The user ID
    /// @param receiver The receiver user ID
    /// @param assetId The used asset ID
    /// @param amt The given amount
    event Given(uint256 indexed userId, uint256 indexed receiver, uint256 assetId, uint128 amt);

    struct DripsHubStorage {
        /// @notice User drips states.
        /// The keys are the user ID and the asset ID.
        mapping(uint256 => mapping(uint256 => DripsState)) dripsStates;
        /// @notice User splits states.
        /// The key is the user ID.
        mapping(uint256 => SplitsState) splitsStates;
        /// @notice The last created account ID. The next one will have ID lastAccountId + 1.
        uint32 lastAccountId;
        /// @notice Account owners. The key is the account ID, the value is the owner address.
        mapping(uint32 => address) accountsOwners;
    }

    struct DripsState {
        /// @notice User drips configuration hashes, see `hashDrips`.
        bytes32 dripsHash;
        // The next cycle to be collected
        uint64 nextCollectedCycle;
        /// @notice The changes of collected amounts on specific cycle.
        /// The keys are cycles, each cycle `C` becomes collectable on timestamp `C * cycleSecs`.
        /// Values for cycles before `nextCollectedCycle` are guaranteed to be zeroed.
        /// This means that the value of `amtDeltas[nextCollectedCycle].thisCycle` is always
        /// relative to 0 or in other words it's an absolute value independent from other cycles.
        mapping(uint64 => AmtDelta) amtDeltas;
    }

    struct AmtDelta {
        /// @notice Amount delta applied on this cycle
        int128 thisCycle;
        /// @notice Amount delta applied on the next cycle
        int128 nextCycle;
    }

    struct SplitsState {
        /// @notice The user's splits configuration hash, see `hashSplits`.
        bytes32 splitsHash;
        /// @notice The user's splits balance. The key is the asset ID.
        mapping(uint256 => SplitsBalance) balances;
    }

    struct SplitsBalance {
        /// @notice The not yet split balance, must be split before collecting by the user.
        uint128 unsplit;
        /// @notice The already split balance, ready to be collected by the user.
        uint128 split;
    }

    /// @param _cycleSecs The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being collectable by their receivers.
    /// High value makes collecting cheaper by making it process less cycles for a given time range.
    constructor(uint64 _cycleSecs) {
        cycleSecs = _cycleSecs;
    }

    modifier onlyAccountOwner(uint256 userId) {
        uint32 accountId = uint32(userId >> BITS_SUB_ACCOUNT);
        if (accountId == 0) {
            // Account ID 0 is for msg.sender verification sub-accounts
            require(
                address(uint160(userId)) == msg.sender,
                "Callable only by the address equal to the user sub-account"
            );
        } else {
            require(
                accountOwner(accountId) == msg.sender,
                "Callable only by the owner of the user account"
            );
        }
        _;
    }

    /// @notice Creates an account.
    /// Assigns it an ID and lets its owner perform actions on behalf of all its sub-accounts.
    /// Multiple accounts can be registered for a single address, it will own all of them.
    /// @return accountId The new account ID.
    function createAccount(address owner) public virtual returns (uint32 accountId) {
        DripsHubStorage storage dripsHubStorage = _dripsHubStorage();
        accountId = dripsHubStorage.lastAccountId + 1;
        dripsHubStorage.lastAccountId = accountId;
        dripsHubStorage.accountsOwners[accountId] = owner;
    }

    /// @notice Returns account owner.
    /// @param accountId The account to look up.
    /// @return owner The owner of the account. If the account doesn't exist, returns address 0.
    function accountOwner(uint32 accountId) public view returns (address owner) {
        return _dripsHubStorage().accountsOwners[accountId];
    }

    /// @notice Returns the ID which will be assigned for the next created account.
    /// @return accountId The account ID.
    function nextAccountId() public view returns (uint32 accountId) {
        return _dripsHubStorage().lastAccountId + 1;
    }

    /// @notice Returns the contract storage.
    /// @return dripsHubStorage The storage.
    function _dripsHubStorage()
        internal
        view
        virtual
        returns (DripsHubStorage storage dripsHubStorage);

    /// @notice Returns amount of received funds available for collection for a user.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectedAmt The collected amount
    /// @return splitAmt The amount split to the user's splits receivers
    function collectableAll(
        address user,
        uint256 assetId,
        SplitsReceiver[] memory currReceivers
    ) public view returns (uint128 collectedAmt, uint128 splitAmt) {
        _assertCurrSplits(user, currReceivers);
        uint256 userId = calcUserId(user);
        SplitsBalance storage balance = _dripsHubStorage().splitsStates[userId].balances[assetId];

        // Collectable independently from cycles
        collectedAmt += balance.unsplit;

        // Collectable from cycles
        (uint128 receivableAmt, ) = receivableDrips(user, assetId, type(uint64).max);
        collectedAmt += receivableAmt;

        // split when collected
        if (collectedAmt > 0 && currReceivers.length > 0) {
            uint32 splitsWeight = 0;
            for (uint256 i = 0; i < currReceivers.length; i++) {
                splitsWeight += currReceivers[i].weight;
            }
            splitAmt = uint128((uint160(collectedAmt) * splitsWeight) / TOTAL_SPLITS_WEIGHT);
            collectedAmt -= splitAmt;
        }

        // Already split
        collectedAmt += balance.split;
    }

    /// @notice Collects all received funds available for the user
    /// and transfers them out of the drips hub contract to that user's wallet.
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectedAmt The collected amount
    /// @return splitAmt The amount split to the user's splits receivers
    function collectAll(uint256 assetId, SplitsReceiver[] memory currReceivers)
        public
        virtual
        returns (uint128 collectedAmt, uint128 splitAmt)
    {
        receiveDrips(msg.sender, assetId, type(uint64).max);
        (, splitAmt) = split(msg.sender, assetId, currReceivers);
        collectedAmt = collect(assetId);
    }

    /// @notice Counts cycles from which drips can be collected.
    /// This function can be used to detect that there are
    /// too many cycles to analyze in a single transaction.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @return cycles The number of cycles which can be flushed
    function receivableDripsCycles(address user, uint256 assetId)
        public
        view
        returns (uint64 cycles)
    {
        uint256 userId = calcUserId(user);
        uint64 collectedCycle = _dripsHubStorage().dripsStates[userId][assetId].nextCollectedCycle;
        if (collectedCycle == 0) return 0;
        uint64 currFinishedCycle = _currTimestamp() / cycleSecs;
        return currFinishedCycle + 1 - collectedCycle;
    }

    /// @notice Calculate effects of calling `receiveDrips` with the given parameters.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivableAmt The amount which would be received
    /// @return receivableCycles The number of cycles which would still be receivable after the call
    function receivableDrips(
        address user,
        uint256 assetId,
        uint64 maxCycles
    ) public view returns (uint128 receivableAmt, uint64 receivableCycles) {
        uint64 allReceivableCycles = receivableDripsCycles(user, assetId);
        uint64 receivedCycles = maxCycles < allReceivableCycles ? maxCycles : allReceivableCycles;
        receivableCycles = allReceivableCycles - receivedCycles;
        uint256 userId = calcUserId(user);
        DripsState storage dripsState = _dripsHubStorage().dripsStates[userId][assetId];
        uint64 collectedCycle = dripsState.nextCollectedCycle;
        int128 cycleAmt = 0;
        for (uint256 i = 0; i < receivedCycles; i++) {
            cycleAmt += dripsState.amtDeltas[collectedCycle].thisCycle;
            receivableAmt += uint128(cycleAmt);
            cycleAmt += dripsState.amtDeltas[collectedCycle].nextCycle;
            collectedCycle++;
        }
    }

    /// @notice Receive drips from uncollected cycles of the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// Calling this function does not collect but makes the funds ready to be split and collected.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The received amount
    /// @return receivableCycles The number of cycles which still can be received
    function receiveDrips(
        address user,
        uint256 assetId,
        uint64 maxCycles
    ) public virtual returns (uint128 receivedAmt, uint64 receivableCycles) {
        receivableCycles = receivableDripsCycles(user, assetId);
        uint64 cycles = maxCycles < receivableCycles ? maxCycles : receivableCycles;
        receivableCycles -= cycles;
        receivedAmt = _receiveDripsInternal(user, assetId, cycles);
        if (receivedAmt > 0)
            _dripsHubStorage()
                .splitsStates[calcUserId(user)]
                .balances[assetId]
                .unsplit += receivedAmt;
        emit ReceivedDrips(user, assetId, receivedAmt, receivableCycles);
    }

    /// @notice Returns user's received but not split yet funds.
    /// @param user The user.
    /// @param assetId The used asset ID.
    /// @return amt The amount received but not split yet.
    function splittable(address user, uint256 assetId) public view returns (uint128 amt) {
        return _dripsHubStorage().splitsStates[calcUserId(user)].balances[assetId].unsplit;
    }

    /// @notice Splits user's received but not split yet funds among receivers.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the user's current splits receivers.
    /// @return collectableAmt The amount made collectable for the user
    /// on top of what was collectable before.
    /// @return splitAmt The amount split to the user's splits receivers
    function split(
        address user,
        uint256 assetId,
        SplitsReceiver[] memory currReceivers
    ) public virtual returns (uint128 collectableAmt, uint128 splitAmt) {
        _assertCurrSplits(user, currReceivers);
        mapping(uint256 => SplitsState) storage splitsStates = _dripsHubStorage().splitsStates;
        uint256 userId = calcUserId(user);
        SplitsBalance storage balance = splitsStates[userId].balances[assetId];

        collectableAmt = balance.unsplit;
        if (collectableAmt == 0) return (0, 0);

        balance.unsplit = 0;
        uint32 splitsWeight = 0;
        for (uint256 i = 0; i < currReceivers.length; i++) {
            splitsWeight += currReceivers[i].weight;
            uint128 currSplitAmt = uint128(
                (uint160(collectableAmt) * splitsWeight) / TOTAL_SPLITS_WEIGHT - splitAmt
            );
            splitAmt += currSplitAmt;
            uint256 receiver = currReceivers[i].userId;
            splitsStates[receiver].balances[assetId].unsplit += currSplitAmt;
            emit Split(user, receiver, assetId, currSplitAmt);
        }
        collectableAmt -= splitAmt;
        balance.split += collectableAmt;
        emit Collectable(user, assetId, collectableAmt);
    }

    /// @notice Returns user's received funds already split and ready to be collected.
    /// @param user The user.
    /// @param assetId The used asset ID.
    /// @return amt The collectable amount.
    function collectable(address user, uint256 assetId) public view returns (uint128 amt) {
        return _dripsHubStorage().splitsStates[calcUserId(user)].balances[assetId].split;
    }

    /// @notice Collects user's received already split funds
    /// and transfers them out of the drips hub contract to that user's wallet.
    /// @param assetId The used asset ID
    /// @return amt The collected amount
    function collect(uint256 assetId) public virtual returns (uint128 amt) {
        uint256 userId = calcUserId(msg.sender);
        SplitsBalance storage balance = _dripsHubStorage().splitsStates[userId].balances[assetId];
        amt = balance.split;
        balance.split = 0;
        emit Collected(msg.sender, assetId, amt);
        _transfer(assetId, int128(amt));
    }

    /// @notice Collects and clears user's cycles
    /// @param user The user
    /// @param assetId The used asset ID
    /// @param count The number of flushed cycles.
    /// @return collectedAmt The collected amount
    function _receiveDripsInternal(
        address user,
        uint256 assetId,
        uint64 count
    ) internal returns (uint128 collectedAmt) {
        if (count == 0) return 0;
        DripsState storage dripsState = _dripsHubStorage().dripsStates[calcUserId(user)][assetId];
        uint64 cycle = dripsState.nextCollectedCycle;
        int128 cycleAmt = 0;
        for (uint256 i = 0; i < count; i++) {
            cycleAmt += dripsState.amtDeltas[cycle].thisCycle;
            collectedAmt += uint128(cycleAmt);
            cycleAmt += dripsState.amtDeltas[cycle].nextCycle;
            delete dripsState.amtDeltas[cycle];
            cycle++;
        }
        // The next cycle delta must be relative to the last collected cycle, which got zeroed.
        // In other words the next cycle delta must be an absolute value.
        if (cycleAmt != 0) dripsState.amtDeltas[cycle].thisCycle += cycleAmt;
        dripsState.nextCollectedCycle = cycle;
    }

    /// @notice Gives funds from the user or their account to the receiver.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the user's wallet to the drips hub contract.
    /// @param userId The user ID
    /// @param receiver The receiver
    /// @param assetId The used asset ID
    /// @param amt The given amount
    function _give(
        uint256 userId,
        uint256 receiver,
        uint256 assetId,
        uint128 amt
    ) internal onlyAccountOwner(userId) {
        _dripsHubStorage().splitsStates[receiver].balances[assetId].unsplit += amt;
        emit Given(userId, receiver, assetId, amt);
        _transfer(assetId, -int128(amt));
    }

    /// @notice Current user's drips hash, see `hashDrips`.
    /// @param user The user
    /// @param assetId The used asset ID
    /// @return currDripsHash The current user's drips hash
    function dripsHash(address user, uint256 assetId) public view returns (bytes32 currDripsHash) {
        return dripsHash(calcUserId(user), assetId);
    }

    /// @notice Current user drips hash, see `hashDrips`.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @return currDripsHash The current user account's drips hash
    function dripsHash(uint256 userId, uint256 assetId)
        public
        view
        returns (bytes32 currDripsHash)
    {
        return _dripsHubStorage().dripsStates[userId][assetId].dripsHash;
    }

    /// @notice Sets the user's or the account's drips configuration.
    /// Transfers funds between the user's wallet and the drips hub contract
    /// to fulfill the change of the drips balance.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param lastUpdate The timestamp of the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user or the account.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the user or the account to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return newBalance The new drips balance of the user or the account.
    /// Pass it as `lastBalance` when updating that user or the account for the next time.
    /// @return realBalanceDelta The actually applied drips balance change.
    function _setDrips(
        uint256 userId,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers
    ) internal onlyAccountOwner(userId) returns (uint128 newBalance, int128 realBalanceDelta) {
        _assertCurrDrips(userId, assetId, lastUpdate, lastBalance, currReceivers);
        uint128 newAmtPerSec = _assertDripsReceiversValid(newReceivers);
        uint128 currAmtPerSec = _totalDripsAmtPerSec(currReceivers);
        uint64 currEndTime = _dripsEndTime(lastUpdate, lastBalance, currAmtPerSec);
        (newBalance, realBalanceDelta) = _updateDripsBalance(
            lastUpdate,
            lastBalance,
            currEndTime,
            currAmtPerSec,
            balanceDelta
        );
        uint64 newEndTime = _dripsEndTime(_currTimestamp(), newBalance, newAmtPerSec);
        _updateDripsReceiversStates(
            userId,
            assetId,
            currReceivers,
            currEndTime,
            newReceivers,
            newEndTime
        );
        _storeNewDrips(userId, assetId, newBalance, newReceivers);
        emit DripsUpdated(userId, assetId, newBalance, newReceivers);
        _transfer(assetId, -realBalanceDelta);
    }

    /// @notice Validates a list of drips receivers.
    /// @param receivers The list of drips receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @return totalAmtPerSec The total amount per second of all drips receivers.
    function _assertDripsReceiversValid(DripsReceiver[] memory receivers)
        internal
        pure
        returns (uint128 totalAmtPerSec)
    {
        require(receivers.length <= MAX_DRIPS_RECEIVERS, "Too many drips receivers");
        uint256 amtPerSec = 0;
        uint256 prevReceiver;
        for (uint256 i = 0; i < receivers.length; i++) {
            uint128 amt = receivers[i].amtPerSec;
            require(amt != 0, "Drips receiver amtPerSec is zero");
            amtPerSec += amt;
            uint256 receiver = receivers[i].userId;
            if (i > 0) {
                require(prevReceiver != receiver, "Duplicate drips receivers");
                require(prevReceiver < receiver, "Drips receivers not sorted by user ID");
            }
            prevReceiver = receiver;
        }
        require(amtPerSec <= type(uint128).max, "Total drips receivers amtPerSec too high");
        return uint128(amtPerSec);
    }

    /// @notice Calculates the total amount per second of all the drips receivers.
    /// @param receivers The list of the receivers.
    /// It must have passed `_assertDripsReceiversValid` in the past.
    /// @return totalAmtPerSec The total amount per second of all the drips receivers
    function _totalDripsAmtPerSec(DripsReceiver[] memory receivers)
        internal
        pure
        returns (uint128 totalAmtPerSec)
    {
        uint256 length = receivers.length;
        uint256 i = 0;
        while (i < length) {
            // Safe, because `receivers` passed `_assertDripsReceiversValid` in the past
            unchecked {
                totalAmtPerSec += receivers[i++].amtPerSec;
            }
        }
    }

    /// @notice Updates drips balance.
    /// @param lastUpdate The timestamp of the last drips update.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update.
    /// If this is the first update, pass zero.
    /// @param currEndTime Time when drips were supposed to end according to the last drips update.
    /// @param currAmtPerSec The total amount per second of all drips receivers
    /// according to the last drips update.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @return newBalance The new drips balance.
    /// Pass it as `lastBalance` when updating for the next time.
    /// @return realBalanceDelta The actually applied drips balance change.
    /// If positive, this is the amount which should be transferred from the user to the drips hub,
    /// or if negative, from the drips hub to the user.
    function _updateDripsBalance(
        uint64 lastUpdate,
        uint128 lastBalance,
        uint64 currEndTime,
        uint128 currAmtPerSec,
        int128 balanceDelta
    ) internal view returns (uint128 newBalance, int128 realBalanceDelta) {
        if (currEndTime > _currTimestamp()) currEndTime = _currTimestamp();
        uint128 dripped = (currEndTime - lastUpdate) * currAmtPerSec;
        int128 currBalance = int128(lastBalance - dripped);
        int136 balance = currBalance + int136(balanceDelta);
        if (balance < 0) balance = 0;
        return (uint128(uint136(balance)), int128(balance - currBalance));
    }

    /// @notice Updates the user's or the account's drips receivers' states.
    /// It applies the effects of the change of the drips configuration.
    /// @param userId The user ID.
    /// @param assetId The used asset ID
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user or the account.
    /// If this is the first update, pass an empty array.
    /// @param currEndTime Time when drips were supposed to end according to the last drips update.
    /// @param newReceivers  The list of the drips receivers of the user or the account to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @param newEndTime Time when drips will end according to the new drips configuration.
    function _updateDripsReceiversStates(
        uint256 userId,
        uint256 assetId,
        DripsReceiver[] memory currReceivers,
        uint64 currEndTime,
        DripsReceiver[] memory newReceivers,
        uint64 newEndTime
    ) internal {
        // Skip iterating over `currReceivers` if dripping has run out
        uint256 currIdx = currEndTime > _currTimestamp() ? 0 : currReceivers.length;
        // Skip iterating over `newReceivers` if no new dripping is started
        uint256 newIdx = newEndTime > _currTimestamp() ? 0 : newReceivers.length;
        while (true) {
            // Each iteration gets the next drips update and applies it on the receiver state.
            // A drips update is composed of two drips receiver configurations,
            // one current and one new, or from a single drips receiver configuration
            // if the drips receiver is being added or removed.
            bool pickCurr = currIdx < currReceivers.length;
            bool pickNew = newIdx < newReceivers.length;
            if (!pickCurr && !pickNew) break;
            if (pickCurr && pickNew) {
                // There are two candidate drips receiver configurations to create a drips update.
                // Pick both if they describe the same receiver or the one with a lower address.
                // The one with a higher address won't be used in this iteration.
                // Because drips receivers lists are sorted by addresses and deduplicated,
                // all matching pairs of drips receiver configurations will be found.
                uint256 currReceiver = currReceivers[currIdx].userId;
                uint256 newReceiver = newReceivers[newIdx].userId;
                pickCurr = currReceiver <= newReceiver;
                pickNew = newReceiver <= currReceiver;
            }
            // The drips update parameters
            uint256 receiver;
            int128 currAmtPerSec = 0;
            int128 newAmtPerSec = 0;
            if (pickCurr) {
                receiver = currReceivers[currIdx].userId;
                currAmtPerSec = int128(currReceivers[currIdx].amtPerSec);
                // Clear the obsolete drips end
                _setDelta(receiver, currEndTime, assetId, currAmtPerSec);
                currIdx++;
            }
            if (pickNew) {
                receiver = newReceivers[newIdx].userId;
                newAmtPerSec = int128(newReceivers[newIdx].amtPerSec);
                // Apply the new drips end
                _setDelta(receiver, newEndTime, assetId, -newAmtPerSec);
                newIdx++;
            }
            // Apply the drips update since now
            _setDelta(receiver, _currTimestamp(), assetId, newAmtPerSec - currAmtPerSec);
            uint64 eventEndTime = newAmtPerSec == 0 ? _currTimestamp() : newEndTime;
            emit Dripping(userId, receiver, assetId, uint128(newAmtPerSec), eventEndTime);
            // The receiver may have never been used
            if (!pickCurr) {
                DripsState storage dripsState = _dripsHubStorage().dripsStates[receiver][assetId];
                // The receiver has never been used, initialize it
                if (dripsState.nextCollectedCycle == 0) {
                    dripsState.nextCollectedCycle = _currTimestamp() / cycleSecs + 1;
                }
            }
        }
    }

    /// @notice Calculates the timestamp when dripping will end.
    /// @param startTime Time when dripping is started.
    /// @param startBalance The drips balance when dripping is started.
    /// @param totalAmtPerSec The total amount per second of all the drips receivers
    /// @return dripsEndTime The dripping end time.
    function _dripsEndTime(
        uint64 startTime,
        uint128 startBalance,
        uint128 totalAmtPerSec
    ) internal pure returns (uint64 dripsEndTime) {
        if (totalAmtPerSec == 0) return startTime;
        uint256 endTime = startTime + uint256(startBalance / totalAmtPerSec);
        return endTime > MAX_TIMESTAMP ? MAX_TIMESTAMP : uint64(endTime);
    }

    /// @notice Asserts that the drips configuration is the currently used one.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param lastUpdate The timestamp of the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param lastBalance The drips balance after the last drips update of the user or the account.
    /// If this is the first update, pass zero.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the user or the account.
    /// If this is the first update, pass an empty array.
    function _assertCurrDrips(
        uint256 userId,
        uint256 assetId,
        uint64 lastUpdate,
        uint128 lastBalance,
        DripsReceiver[] memory currReceivers
    ) internal view {
        bytes32 expectedHash = _dripsHubStorage().dripsStates[userId][assetId].dripsHash;
        bytes32 actualHash = hashDrips(lastUpdate, lastBalance, currReceivers);
        require(actualHash == expectedHash, "Invalid current drips configuration");
    }

    /// @notice Stores the hash of the new drips configuration to be used in `_assertCurrDrips`.
    /// @param userId The user ID
    /// @param assetId The used asset ID
    /// @param newBalance The user or the account drips balance.
    /// @param newReceivers The list of the drips receivers of the user or the account.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    function _storeNewDrips(
        uint256 userId,
        uint256 assetId,
        uint128 newBalance,
        DripsReceiver[] memory newReceivers
    ) internal {
        bytes32 newDripsHash = hashDrips(_currTimestamp(), newBalance, newReceivers);
        _dripsHubStorage().dripsStates[userId][assetId].dripsHash = newDripsHash;
    }

    /// @notice Calculates the hash of the drips configuration.
    /// It's used to verify if drips configuration is the previously set one.
    /// @param update The timestamp of the drips update.
    /// If the drips have never been updated, pass zero.
    /// @param balance The drips balance.
    /// If the drips have never been updated, pass zero.
    /// @param receivers The list of the drips receivers.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// If the drips have never been updated, pass an empty array.
    /// @return dripsConfigurationHash The hash of the drips configuration
    function hashDrips(
        uint64 update,
        uint128 balance,
        DripsReceiver[] memory receivers
    ) public pure returns (bytes32 dripsConfigurationHash) {
        if (update == 0 && balance == 0 && receivers.length == 0) return bytes32(0);
        return keccak256(abi.encode(receivers, update, balance));
    }

    /// @notice Sets user splits configuration.
    /// @param userId The user ID
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    function _setSplits(uint256 userId, SplitsReceiver[] memory receivers)
        internal
        onlyAccountOwner(userId)
    {
        _assertSplitsValid(receivers);
        _dripsHubStorage().splitsStates[userId].splitsHash = hashSplits(receivers);
        emit SplitsUpdated(userId, receivers);
    }

    /// @notice Validates a list of splits receivers
    /// @param receivers The list of splits receivers
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    function _assertSplitsValid(SplitsReceiver[] memory receivers) internal pure {
        require(receivers.length <= MAX_SPLITS_RECEIVERS, "Too many splits receivers");
        uint64 totalWeight = 0;
        uint256 prevReceiver;
        for (uint256 i = 0; i < receivers.length; i++) {
            uint32 weight = receivers[i].weight;
            require(weight != 0, "Splits receiver weight is zero");
            totalWeight += weight;
            uint256 receiver = receivers[i].userId;
            if (i > 0) {
                require(prevReceiver != receiver, "Duplicate splits receivers");
                require(prevReceiver < receiver, "Splits receivers not sorted by user ID");
            }
            prevReceiver = receiver;
        }
        require(totalWeight <= TOTAL_SPLITS_WEIGHT, "Splits weights sum too high");
    }

    /// @notice Current user's splits hash, see `hashSplits`.
    /// @param userId The user ID
    /// @return currSplitsHash The current user's splits hash
    function splitsHash(uint256 userId) public view returns (bytes32 currSplitsHash) {
        return _dripsHubStorage().splitsStates[userId].splitsHash;
    }

    /// @notice Asserts that the list of splits receivers is the user's currently used one.
    /// @param user The user
    /// @param currReceivers The list of the user's current splits receivers.
    function _assertCurrSplits(address user, SplitsReceiver[] memory currReceivers) internal view {
        require(
            hashSplits(currReceivers) ==
                _dripsHubStorage().splitsStates[calcUserId(user)].splitsHash,
            "Invalid current splits receivers"
        );
    }

    /// @notice Calculates the hash of the list of splits receivers.
    /// @param receivers The list of the splits receivers.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// @return receiversHash The hash of the list of splits receivers.
    function hashSplits(SplitsReceiver[] memory receivers)
        public
        pure
        returns (bytes32 receiversHash)
    {
        if (receivers.length == 0) return bytes32(0);
        return keccak256(abi.encode(receivers));
    }

    /// @notice Called when funds need to be transferred between the user and the drips hub.
    /// The function must be called no more than once per transaction.
    /// @param assetId The used asset ID
    /// @param amt The transferred amount.
    /// Positive to transfer funds to the user, negative to transfer from them.
    function _transfer(uint256 assetId, int128 amt) internal virtual;

    /// @notice Sets amt delta of a user on a given timestamp
    /// @param userId The user ID
    /// @param timestamp The timestamp from which the delta takes effect
    /// @param assetId The used asset ID
    /// @param amtPerSecDelta Change of the per-second receiving rate
    function _setDelta(
        uint256 userId,
        uint64 timestamp,
        uint256 assetId,
        int128 amtPerSecDelta
    ) internal {
        if (amtPerSecDelta == 0) return;
        // In order to set a delta on a specific timestamp it must be introduced in two cycles.
        // The cycle delta is split proportionally based on how much this cycle is affected.
        // The next cycle has the rest of the delta applied, so the update is fully completed.
        uint64 thisCycle = timestamp / cycleSecs + 1;
        uint64 nextCycleSecs = timestamp % cycleSecs;
        uint64 thisCycleSecs = cycleSecs - nextCycleSecs;
        AmtDelta storage amtDelta = _dripsHubStorage().dripsStates[userId][assetId].amtDeltas[
            thisCycle
        ];
        amtDelta.thisCycle += int128(uint128(thisCycleSecs)) * amtPerSecDelta;
        amtDelta.nextCycle += int128(uint128(nextCycleSecs)) * amtPerSecDelta;
    }

    function calcUserId(address user) public pure returns (uint256) {
        return uint160(user);
    }

    function _currTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp);
    }
}
