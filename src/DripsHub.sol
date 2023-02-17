// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Drips, DripsConfig, DripsHistory, DripsConfigImpl, DripsReceiver} from "./Drips.sol";
import {Managed} from "./Managed.sol";
import {Splits, SplitsReceiver} from "./Splits.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

using SafeERC20 for IERC20;

/// @notice The user metadata.
/// The key and the value are not standardized by the protocol, it's up to the user
/// to establish and follow conventions to ensure compatibility with the consumers.
struct UserMetadata {
    /// @param key The metadata key
    bytes32 key;
    /// @param value The metadata value
    bytes value;
}

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
    /// @notice Maximum number of drips receivers of a single user.
    /// Limits cost of changes in drips configuration.
    uint256 public constant MAX_DRIPS_RECEIVERS = _MAX_DRIPS_RECEIVERS;
    /// @notice The additional decimals for all amtPerSec values.
    uint8 public constant AMT_PER_SEC_EXTRA_DECIMALS = _AMT_PER_SEC_EXTRA_DECIMALS;
    /// @notice The multiplier for all amtPerSec values.
    uint160 public constant AMT_PER_SEC_MULTIPLIER = _AMT_PER_SEC_MULTIPLIER;
    /// @notice Maximum number of splits receivers of a single user. Limits the cost of splitting.
    uint256 public constant MAX_SPLITS_RECEIVERS = _MAX_SPLITS_RECEIVERS;
    /// @notice The total splits weight of a user
    uint32 public constant TOTAL_SPLITS_WEIGHT = _TOTAL_SPLITS_WEIGHT;
    /// @notice The offset of the controlling driver ID in the user ID.
    /// In other words the controlling driver ID is the highest 32 bits of the user ID.
    uint256 public constant DRIVER_ID_OFFSET = 224;
    /// @notice The total amount the contract can store of each token.
    /// It's the minimum of _MAX_TOTAL_DRIPS_BALANCE and _MAX_TOTAL_SPLITS_BALANCE.
    uint256 public constant MAX_TOTAL_BALANCE = _MAX_TOTAL_DRIPS_BALANCE;
    /// @notice On every timestamp `T`, which is a multiple of `cycleSecs`, the receivers
    /// gain access to drips received during `T - cycleSecs` to `T - 1`.
    /// Always higher than 1.
    uint32 public immutable cycleSecs;
    /// @notice The minimum amtPerSec of a drip. It's 1 token per cycle.
    uint160 public immutable minAmtPerSec;
    /// @notice The ERC-1967 storage slot holding a single `DripsHubStorage` structure.
    bytes32 private immutable _dripsHubStorageSlot = _erc1967Slot("eip1967.dripsHub.storage");

    /// @notice Emitted when a driver is registered
    /// @param driverId The driver ID
    /// @param driverAddr The driver address
    event DriverRegistered(uint32 indexed driverId, address indexed driverAddr);

    /// @notice Emitted when a driver address is updated
    /// @param driverId The driver ID
    /// @param oldDriverAddr The old driver address
    /// @param newDriverAddr The new driver address
    event DriverAddressUpdated(
        uint32 indexed driverId, address indexed oldDriverAddr, address indexed newDriverAddr
    );

    /// @notice Emitted by the user to broadcast metadata.
    /// The key and the value are not standardized by the protocol, it's up to the user
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param userId The ID of the user emitting metadata
    /// @param key The metadata key
    /// @param value The metadata value
    event UserMetadataEmitted(uint256 indexed userId, bytes32 indexed key, bytes value);

    struct DripsHubStorage {
        /// @notice The next driver ID that will be used when registering.
        uint32 nextDriverId;
        /// @notice Driver addresses. The key is the driver ID, the value is the driver address.
        mapping(uint32 => address) driverAddresses;
        /// @notice The total amount currently stored in DripsHub of each token.
        mapping(IERC20 => uint256) totalBalances;
    }

    /// @param cycleSecs_ The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time of funds being frozen
    /// between being taken from the users' drips balances and being receivable by their receivers.
    /// High value makes receiving cheaper by making it process less cycles for a given time range.
    /// Must be higher than 1.
    constructor(uint32 cycleSecs_)
        Drips(cycleSecs_, _erc1967Slot("eip1967.drips.storage"))
        Splits(_erc1967Slot("eip1967.splits.storage"))
    {
        cycleSecs = Drips._cycleSecs;
        minAmtPerSec = Drips._minAmtPerSec;
    }

    /// @notice A modifier making functions callable only by the driver controlling the user ID.
    /// @param userId The user ID.
    modifier onlyDriver(uint256 userId) {
        uint32 driverId = uint32(userId >> DRIVER_ID_OFFSET);
        _assertCallerIsDriver(driverId);
        _;
    }

    function _assertCallerIsDriver(uint32 driverId) internal view {
        require(driverAddress(driverId) == msg.sender, "Callable only by the driver");
    }

    /// @notice Registers a driver.
    /// The driver is assigned a unique ID and a range of user IDs it can control.
    /// That range consists of all 2^224 user IDs with highest 32 bits equal to the driver ID.
    /// Every driver ID is assigned only to a single address,
    /// but a single address can have multiple driver IDs assigned to it.
    /// @param driverAddr The address of the driver.
    /// @return driverId The registered driver ID.
    function registerDriver(address driverAddr) public whenNotPaused returns (uint32 driverId) {
        DripsHubStorage storage dripsHubStorage = _dripsHubStorage();
        driverId = dripsHubStorage.nextDriverId++;
        dripsHubStorage.driverAddresses[driverId] = driverAddr;
        emit DriverRegistered(driverId, driverAddr);
    }

    /// @notice Returns the driver address.
    /// @param driverId The driver ID to look up.
    /// @return driverAddr The address of the driver.
    /// If the driver hasn't been registered yet, returns address 0.
    function driverAddress(uint32 driverId) public view returns (address driverAddr) {
        return _dripsHubStorage().driverAddresses[driverId];
    }

    /// @notice Updates the driver address. Must be called from the current driver address.
    /// @param driverId The driver ID.
    /// @param newDriverAddr The new address of the driver.
    function updateDriverAddress(uint32 driverId, address newDriverAddr) public whenNotPaused {
        _assertCallerIsDriver(driverId);
        _dripsHubStorage().driverAddresses[driverId] = newDriverAddr;
        emit DriverAddressUpdated(driverId, msg.sender, newDriverAddr);
    }

    /// @notice Returns the driver ID which will be assigned for the next registered driver.
    /// @return driverId The next driver ID.
    function nextDriverId() public view returns (uint32 driverId) {
        return _dripsHubStorage().nextDriverId;
    }

    /// @notice Returns the total amount currently stored in DripsHub of the given token.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @return balance The balance of the token.
    function totalBalance(IERC20 erc20) public view returns (uint256 balance) {
        return _dripsHubStorage().totalBalances[erc20];
    }

    /// @notice Counts cycles from which drips can be collected.
    /// This function can be used to detect that there are
    /// too many cycles to analyze in a single transaction.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
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
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivableAmt The amount which would be received
    function receiveDripsResult(uint256 userId, IERC20 erc20, uint32 maxCycles)
        public
        view
        returns (uint128 receivableAmt)
    {
        (receivableAmt,,,,) = Drips._receiveDripsResult(userId, _assetId(erc20), maxCycles);
    }

    /// @notice Receive drips for the user.
    /// Received drips cycles won't need to be analyzed ever again.
    /// Calling this function does not collect but makes the funds ready to be split and collected.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param maxCycles The maximum number of received drips cycles.
    /// If too low, receiving will be cheap, but may not cover many cycles.
    /// If too high, receiving may become too expensive to fit in a single transaction.
    /// @return receivedAmt The received amount
    function receiveDrips(uint256 userId, IERC20 erc20, uint32 maxCycles)
        public
        whenNotPaused
        returns (uint128 receivedAmt)
    {
        uint256 assetId = _assetId(erc20);
        receivedAmt = Drips._receiveDrips(userId, assetId, maxCycles);
        if (receivedAmt > 0) {
            Splits._addSplittable(userId, assetId, receivedAmt);
        }
    }

    /// @notice Receive drips from the currently running cycle from a single sender.
    /// It doesn't receive drips from the previous, finished cycles, to do that use `receiveDrips`.
    /// Squeezed funds won't be received in the next calls to `squeezeDrips` or `receiveDrips`.
    /// Only funds dripped before `block.timestamp` can be squeezed.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @param historyHash The sender's history hash which was valid right before
    /// they set up the sequence of configurations described by `dripsHistory`.
    /// @param dripsHistory The sequence of the sender's drips configurations.
    /// It can start at an arbitrary past configuration, but must describe all the configurations
    /// which have been used since then including the current one, in the chronological order.
    /// Only drips described by `dripsHistory` will be squeezed.
    /// If `dripsHistory` entries have no receivers, they won't be squeezed.
    /// @return amt The squeezed amount.
    function squeezeDrips(
        uint256 userId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) public whenNotPaused returns (uint128 amt) {
        uint256 assetId = _assetId(erc20);
        amt = Drips._squeezeDrips(userId, assetId, senderId, historyHash, dripsHistory);
        if (amt > 0) {
            Splits._addSplittable(userId, assetId, amt);
        }
    }

    /// @notice Calculate effects of calling `squeezeDrips` with the given parameters.
    /// See its documentation for more details.
    /// @param userId The ID of the user receiving drips to squeeze funds for.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param senderId The ID of the user sending drips to squeeze funds from.
    /// @param historyHash The sender's history hash which was valid right before `dripsHistory`.
    /// @param dripsHistory The sequence of the sender's drips configurations.
    /// @return amt The squeezed amount.
    function squeezeDripsResult(
        uint256 userId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        DripsHistory[] memory dripsHistory
    ) public view returns (uint128 amt) {
        (amt,,,,) =
            Drips._squeezeDripsResult(userId, _assetId(erc20), senderId, historyHash, dripsHistory);
    }

    /// @notice Returns user's received but not split yet funds.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @return amt The amount received but not split yet.
    function splittable(uint256 userId, IERC20 erc20) public view returns (uint128 amt) {
        return Splits._splittable(userId, _assetId(erc20));
    }

    /// @notice Calculate the result of splitting an amount using the current splits configuration.
    /// @param userId The user ID
    /// @param currReceivers The list of the user's current splits receivers.
    /// It must be exactly the same as the last list set for the user with `setSplits`.
    /// @param amount The amount being split.
    /// @return collectableAmt The amount made collectable for the user
    /// on top of what was collectable before.
    /// @return splitAmt The amount split to the user's splits receivers
    function splitResult(uint256 userId, SplitsReceiver[] memory currReceivers, uint128 amount)
        public
        view
        returns (uint128 collectableAmt, uint128 splitAmt)
    {
        return Splits._splitResult(userId, currReceivers, amount);
    }

    /// @notice Splits the user's splittable funds among receivers.
    /// The entire splittable balance of the given asset is split.
    /// All split funds are split using the current splits configuration.
    /// Because the user can update their splits configuration at any time,
    /// it is possible that calling this function will be frontrun,
    /// and all the splittable funds will become splittable only using the new configuration.
    /// The user must be trusted with how funds sent to them will be splits,
    /// in the end they can do with their funds whatever they want by changing the configuration.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param currReceivers The list of the user's current splits receivers.
    /// It must be exactly the same as the last list set for the user with `setSplits`.
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
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @return amt The collectable amount.
    function collectable(uint256 userId, IERC20 erc20) public view returns (uint128 amt) {
        return Splits._collectable(userId, _assetId(erc20));
    }

    /// @notice Collects user's received already split funds
    /// and transfers them out of the drips hub contract to msg.sender.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @return amt The collected amount
    function collect(uint256 userId, IERC20 erc20)
        public
        whenNotPaused
        onlyDriver(userId)
        returns (uint128 amt)
    {
        amt = Splits._collect(userId, _assetId(erc20));
        _decreaseTotalBalance(erc20, amt);
        erc20.safeTransfer(msg.sender, amt);
    }

    /// @notice Gives funds from the user to the receiver.
    /// The receiver can split and collect them immediately.
    /// Transfers the funds to be given from the user's wallet to the drips hub contract.
    /// @param userId The user ID
    /// @param receiver The receiver
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param amt The given amount
    function give(uint256 userId, uint256 receiver, IERC20 erc20, uint128 amt)
        public
        whenNotPaused
        onlyDriver(userId)
    {
        _increaseTotalBalance(erc20, amt);
        Splits._give(userId, receiver, _assetId(erc20), amt);
        erc20.safeTransferFrom(msg.sender, address(this), amt);
    }

    /// @notice Current user drips state.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
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

    /// @notice User's drips balance at a given timestamp
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param currReceivers The current drips receivers list.
    /// It must be exactly the same as the last list set for the user with `setDrips`.
    /// @param timestamp The timestamps for which balance should be calculated.
    /// It can't be lower than the timestamp of the last call to `setDrips`.
    /// If it's bigger than `block.timestamp`, then it's a prediction assuming
    /// that `setDrips` won't be called before `timestamp`.
    /// @return balance The user balance on `timestamp`
    function balanceAt(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver[] memory currReceivers,
        uint32 timestamp
    ) public view returns (uint128 balance) {
        return Drips._balanceAt(userId, _assetId(erc20), currReceivers, timestamp);
    }

    /// @notice Sets the user's drips configuration.
    /// Transfers funds between the user's wallet and the drips hub contract
    /// to fulfil the change of the drips balance.
    /// @param userId The user ID
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param currReceivers The current drips receivers list.
    /// It must be exactly the same as the last list set for the user with `setDrips`.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the user to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @param maxEndHint1 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The first hint for finding the maximum end time when all drips stop due to funds
    /// running out after the balance is updated and the new receivers list is applied.
    /// Hints have no effect on the results of calling this function, except potentially saving gas.
    /// Hints are Unix timestamps used as the starting points for binary search for the time
    /// when funds run out in the range of timestamps from the current block's to `2^32`.
    /// Hints lower than the current timestamp are ignored.
    /// You can provide zero, one or two hints. The order of hints doesn't matter.
    /// Hints are the most effective when one of them is lower than or equal to
    /// the last timestamp when funds are still dripping, and the other one is strictly larger
    /// than that timestamp,the smaller the difference between such hints, the higher gas savings.
    /// The savings are the highest possible when one of the hints is equal to
    /// the last timestamp when funds are still dripping, and the other one is larger by 1.
    /// It's worth noting that the exact timestamp of the block in which this function is executed
    /// may affect correctness of the hints, especially if they're precise.
    /// Hints don't provide any benefits when balance is not enough to cover
    /// a single second of dripping or is enough to cover all drips until timestamp `2^32`.
    /// Even inaccurate hints can be useful, and providing a single hint
    /// or two hints that don't enclose the time when funds run out can still save some gas.
    /// Providing poor hints that don't reduce the number of binary search steps
    /// may cause slightly higher gas usage than not providing any hints.
    /// @param maxEndHint2 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The second hint for finding the maximum end time, see `maxEndHint1` docs for more details.
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        uint256 userId,
        IERC20 erc20,
        DripsReceiver[] memory currReceivers,
        int128 balanceDelta,
        DripsReceiver[] memory newReceivers,
        // slither-disable-next-line similar-names
        uint32 maxEndHint1,
        uint32 maxEndHint2
    ) public whenNotPaused onlyDriver(userId) returns (int128 realBalanceDelta) {
        if (balanceDelta > 0) {
            _increaseTotalBalance(erc20, uint128(balanceDelta));
        }
        realBalanceDelta = Drips._setDrips(
            userId,
            _assetId(erc20),
            currReceivers,
            balanceDelta,
            newReceivers,
            maxEndHint1,
            maxEndHint2
        );
        if (realBalanceDelta > 0) {
            erc20.safeTransferFrom(msg.sender, address(this), uint128(realBalanceDelta));
        } else if (realBalanceDelta < 0) {
            _decreaseTotalBalance(erc20, uint128(-realBalanceDelta));
            erc20.safeTransfer(msg.sender, uint128(-realBalanceDelta));
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
    ) public pure returns (bytes32 dripsHistoryHash) {
        return Drips._hashDripsHistory(oldDripsHistoryHash, dripsHash, updateTime, maxEnd);
    }

    /// @notice Sets user splits configuration. The configuration is common for all assets.
    /// Nothing happens to the currently splittable funds, but when they are split
    /// after this function finishes, the new splits configuration will be used.
    /// Because anybody can call `split`, calling this function may be frontrun
    /// and all the currently splittable funds will be split using the old splits configuration.
    /// @param userId The user ID
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    /// If the sum of weights of all receivers is less than `_TOTAL_SPLITS_WEIGHT`,
    /// some funds won't be split, but they will be left for the user to collect.
    /// It's valid to include the user's own `userId` in the list of receivers,
    /// but funds split to themselves return to their splittable balance and are not collectable.
    /// This is usually unwanted, because if splitting is repeated,
    /// funds split to themselves will be again split using the current configuration.
    /// Splitting 100% to self effectively blocks splitting unless the configuration is updated.
    function setSplits(uint256 userId, SplitsReceiver[] memory receivers)
        public
        whenNotPaused
        onlyDriver(userId)
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
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// @return receiversHash The hash of the list of splits receivers.
    function hashSplits(SplitsReceiver[] memory receivers)
        public
        pure
        returns (bytes32 receiversHash)
    {
        return Splits._hashSplits(receivers);
    }

    /// @notice Emits user metadata.
    /// The keys and the values are not standardized by the protocol, it's up to the user
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param userId The user ID.
    /// @param userMetadata The list of user metadata.
    function emitUserMetadata(uint256 userId, UserMetadata[] calldata userMetadata)
        public
        whenNotPaused
        onlyDriver(userId)
    {
        for (uint256 i = 0; i < userMetadata.length; i++) {
            UserMetadata calldata metadata = userMetadata[i];
            emit UserMetadataEmitted(userId, metadata.key, metadata.value);
        }
    }

    /// @notice Returns the DripsHub storage.
    /// @return storageRef The storage.
    function _dripsHubStorage() internal view returns (DripsHubStorage storage storageRef) {
        bytes32 slot = _dripsHubStorageSlot;
        // slither-disable-next-line assembly
        assembly {
            storageRef.slot := slot
        }
    }

    function _increaseTotalBalance(IERC20 erc20, uint128 amt) internal {
        mapping(IERC20 => uint256) storage totalBalances = _dripsHubStorage().totalBalances;
        require(totalBalances[erc20] + amt <= MAX_TOTAL_BALANCE, "Total balance too high");
        totalBalances[erc20] += amt;
    }

    function _decreaseTotalBalance(IERC20 erc20, uint128 amt) internal {
        _dripsHubStorage().totalBalances[erc20] -= amt;
    }

    /// @notice Generates an asset ID for the ERC-20 token
    /// @param erc20 The ERC-20 token
    /// @return assetId The asset ID
    function _assetId(IERC20 erc20) internal pure returns (uint256 assetId) {
        return uint160(address(erc20));
    }
}
