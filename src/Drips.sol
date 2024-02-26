// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import {DripsLib} from "./DripsLib.sol";
import "./IDrips.sol";
import {Streams} from "./Streams.sol";
import {Managed} from "./Managed.sol";
import {Splits} from "./Splits.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice The implementation of `IDrips`, see its documentation for more details.
contract Drips is IDrips, Managed, Streams, Splits {
    /// @notice The ERC-1967 storage slot holding a single `DripsStorage` structure.
    bytes32 private immutable _dripsStorageSlot = _erc1967Slot("eip1967.drips.storage");

    struct DripsStorage {
        /// @notice The next driver ID that will be used when registering.
        uint32 nextDriverId;
        /// @notice Driver addresses.
        mapping(uint32 driverId => address) driverAddresses;
        /// @notice The balance of each token currently stored in the protocol.
        mapping(IERC20 erc20 => Balance) balances;
    }

    /// @notice The balance currently stored in the protocol.
    struct Balance {
        /// @notice The balance currently stored in the protocol in streaming.
        /// It's the sum of all the funds of all the users
        /// that are in the streams balances, are squeezable or are receivable.
        uint128 streams;
        /// @notice The balance currently stored in the protocol in splitting.
        /// It's the sum of all the funds of all the users that are splittable or are collectable.
        uint128 splits;
    }

    /// @param cycleSecs_ The length of cycleSecs to be used in the contract instance.
    /// Low value makes funds more available by shortening the average time
    /// of funds being frozen between being taken from the accounts'
    /// streams balance and being receivable by their receivers.
    /// High value makes receiving cheaper by making it process less cycles for a given time range.
    /// Must be higher than 1.
    constructor(uint32 cycleSecs_)
        Streams(cycleSecs_, _erc1967Slot("eip1967.streams.storage"))
        Splits(_erc1967Slot("eip1967.splits.storage"))
    {
        return;
    }

    /// @notice A modifier making functions callable only by the driver controlling the account.
    /// @param accountId The account ID.
    modifier onlyDriver(uint256 accountId) {
        // `accountId` has value:
        // `driverId (32 bits) | driverCustomData (224 bits)`
        // By bit shifting we get value:
        // `zeros (224 bits) | driverId (32 bits)`
        // By casting down we get value:
        // `driverId (32 bits)`
        uint32 driverId = uint32(accountId >> DripsLib.DRIVER_ID_OFFSET);
        _assertCallerIsDriver(driverId);
        _;
    }

    /// @inheritdoc IDrips
    function cycleSecs() public view returns (uint32 cycleSecs_) {
        return Streams._cycleSecs;
    }

    /// @notice Verifies that the caller controls the given driver ID and reverts otherwise.
    /// @param driverId The driver ID.
    function _assertCallerIsDriver(uint32 driverId) internal view {
        require(driverAddress(driverId) == msg.sender, "Callable only by the driver");
    }

    /// @inheritdoc IDrips
    function registerDriver(address driverAddr) public onlyProxy returns (uint32 driverId) {
        require(driverAddr != address(0), "Driver registered for 0 address");
        DripsStorage storage dripsStorage = _dripsStorage();
        driverId = dripsStorage.nextDriverId++;
        dripsStorage.driverAddresses[driverId] = driverAddr;
        emit DriverRegistered(driverId, driverAddr);
    }

    /// @inheritdoc IDrips
    function driverAddress(uint32 driverId) public view onlyProxy returns (address driverAddr) {
        return _dripsStorage().driverAddresses[driverId];
    }

    /// @inheritdoc IDrips
    function updateDriverAddress(uint32 driverId, address newDriverAddr) public onlyProxy {
        _assertCallerIsDriver(driverId);
        _dripsStorage().driverAddresses[driverId] = newDriverAddr;
        emit DriverAddressUpdated(driverId, msg.sender, newDriverAddr);
    }

    /// @inheritdoc IDrips
    function nextDriverId() public view onlyProxy returns (uint32 driverId) {
        return _dripsStorage().nextDriverId;
    }

    /// @inheritdoc IDrips
    function balances(IERC20 erc20)
        public
        view
        onlyProxy
        returns (uint256 streamsBalance, uint256 splitsBalance)
    {
        Balance storage balance = _dripsStorage().balances[erc20];
        return (balance.streams, balance.splits);
    }

    /// @notice Increases the balance of the given token currently stored in streams.
    /// No funds are transferred, all the tokens are expected to be already held by Drips.
    /// The new total balance is verified to have coverage in the held tokens
    /// and to be within the limit of `DripsLib.MAX_TOTAL_BALANCE`.
    /// @param erc20 The used ERC-20 token.
    /// @param amt The amount to increase the streams balance by.
    function _increaseStreamsBalance(IERC20 erc20, uint128 amt) internal {
        _verifyBalanceIncrease(erc20, amt);
        _dripsStorage().balances[erc20].streams += amt;
    }

    /// @notice Decreases the balance of the given token currently stored in streams.
    /// No funds are transferred, but the tokens held by Drips
    /// above the total balance become withdrawable.
    /// @param erc20 The used ERC-20 token.
    /// @param amt The amount to decrease the streams balance by.
    function _decreaseStreamsBalance(IERC20 erc20, uint128 amt) internal {
        _dripsStorage().balances[erc20].streams -= amt;
    }

    /// @notice Increases the balance of the given token currently stored in splits.
    /// No funds are transferred, all the tokens are expected to be already held by Drips.
    /// The new total balance is verified to have coverage in the held tokens
    /// and to be within the limit of `DripsLib.MAX_TOTAL_BALANCE`.
    /// @param erc20 The used ERC-20 token.
    /// @param amt The amount to increase the splits balance by.
    function _increaseSplitsBalance(IERC20 erc20, uint128 amt) internal {
        _verifyBalanceIncrease(erc20, amt);
        _dripsStorage().balances[erc20].splits += amt;
    }

    /// @notice Decreases the balance of the given token currently stored in splits.
    /// No funds are transferred, but the tokens held by Drips
    /// above the total balance become withdrawable.
    /// @param erc20 The used ERC-20 token.
    /// @param amt The amount to decrease the splits balance by.
    function _decreaseSplitsBalance(IERC20 erc20, uint128 amt) internal {
        _dripsStorage().balances[erc20].splits -= amt;
    }

    /// @notice Moves the balance of the given token currently stored in streams to splits.
    /// No funds are transferred, all the tokens are already held by Drips.
    /// @param erc20 The used ERC-20 token.
    /// @param amt The amount to decrease the splits balance by.
    function _moveBalanceFromStreamsToSplits(IERC20 erc20, uint128 amt) internal {
        Balance storage balance = _dripsStorage().balances[erc20];
        balance.streams -= amt;
        balance.splits += amt;
    }

    /// @notice Verifies that the balance of streams or splits can be increased by the given amount.
    /// The sum of streaming and splitting balances is checked to not exceed
    /// `DripsLib.MAX_TOTAL_BALANCE` or the amount of tokens held by the Drips.
    /// @param erc20 The used ERC-20 token.
    /// @param amt The amount to increase the streams or splits balance by.
    function _verifyBalanceIncrease(IERC20 erc20, uint128 amt) internal view {
        (uint256 streamsBalance, uint256 splitsBalance) = balances(erc20);
        uint256 newTotalBalance = streamsBalance + splitsBalance + amt;
        require(newTotalBalance <= DripsLib.MAX_TOTAL_BALANCE, "Total balance too high");
        require(newTotalBalance <= erc20.balanceOf(address(this)), "Token balance too low");
    }

    /// @inheritdoc IDrips
    function withdraw(IERC20 erc20, address receiver, uint256 amt) public onlyProxy {
        (uint256 streamsBalance, uint256 splitsBalance) = balances(erc20);
        uint256 withdrawable = erc20.balanceOf(address(this)) - streamsBalance - splitsBalance;
        require(amt <= withdrawable, "Withdrawal amount too high");
        emit Withdrawn(erc20, receiver, amt);
        SafeERC20.safeTransfer(erc20, receiver, amt);
    }

    /// @inheritdoc IDrips
    function receivableStreamsCycles(uint256 accountId, IERC20 erc20)
        public
        view
        onlyProxy
        returns (uint32 cycles)
    {
        return Streams._receivableStreamsCycles(accountId, erc20);
    }

    /// @inheritdoc IDrips
    function receiveStreamsResult(uint256 accountId, IERC20 erc20, uint32 maxCycles)
        public
        view
        onlyProxy
        returns (uint128 receivableAmt)
    {
        (receivableAmt,,,,) = Streams._receiveStreamsResult(accountId, erc20, maxCycles);
    }

    /// @inheritdoc IDrips
    function receiveStreams(uint256 accountId, IERC20 erc20, uint32 maxCycles)
        public
        onlyProxy
        returns (uint128 receivedAmt)
    {
        receivedAmt = Streams._receiveStreams(accountId, erc20, maxCycles);
        if (receivedAmt != 0) {
            _moveBalanceFromStreamsToSplits(erc20, receivedAmt);
            Splits._addSplittable(accountId, erc20, receivedAmt);
        }
    }

    /// @inheritdoc IDrips
    function squeezeStreams(
        uint256 accountId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        StreamsHistory[] memory streamsHistory
    ) public onlyProxy returns (uint128 amt) {
        amt = Streams._squeezeStreams(accountId, erc20, senderId, historyHash, streamsHistory);
        if (amt != 0) {
            _moveBalanceFromStreamsToSplits(erc20, amt);
            Splits._addSplittable(accountId, erc20, amt);
        }
    }

    /// @inheritdoc IDrips
    function squeezeStreamsResult(
        uint256 accountId,
        IERC20 erc20,
        uint256 senderId,
        bytes32 historyHash,
        StreamsHistory[] memory streamsHistory
    ) public view onlyProxy returns (uint128 amt) {
        (amt,,,,) =
            Streams._squeezeStreamsResult(accountId, erc20, senderId, historyHash, streamsHistory);
    }

    /// @inheritdoc IDrips
    function splittable(uint256 accountId, IERC20 erc20)
        public
        view
        onlyProxy
        returns (uint128 amt)
    {
        return Splits._splittable(accountId, erc20);
    }

    /// @inheritdoc IDrips
    function splitResult(uint256 accountId, SplitsReceiver[] calldata currReceivers, uint128 amount)
        public
        view
        onlyProxy
        returns (uint128 collectableAmt, uint128 splitAmt)
    {
        return Splits._splitResult(accountId, currReceivers, amount);
    }

    /// @inheritdoc IDrips
    function split(uint256 accountId, IERC20 erc20, SplitsReceiver[] calldata currReceivers)
        public
        onlyProxy
        returns (uint128 collectableAmt, uint128 splitAmt)
    {
        return Splits._split(accountId, erc20, currReceivers);
    }

    /// @inheritdoc IDrips
    function collectable(uint256 accountId, IERC20 erc20)
        public
        view
        onlyProxy
        returns (uint128 amt)
    {
        return Splits._collectable(accountId, erc20);
    }

    /// @inheritdoc IDrips
    function collect(uint256 accountId, IERC20 erc20)
        public
        onlyProxy
        onlyDriver(accountId)
        returns (uint128 amt)
    {
        amt = Splits._collect(accountId, erc20);
        if (amt != 0) _decreaseSplitsBalance(erc20, amt);
    }

    /// @inheritdoc IDrips
    function give(uint256 accountId, uint256 receiver, IERC20 erc20, uint128 amt)
        public
        onlyProxy
        onlyDriver(accountId)
    {
        if (amt != 0) _increaseSplitsBalance(erc20, amt);
        Splits._give(accountId, receiver, erc20, amt);
    }

    /// @inheritdoc IDrips
    function streamsState(uint256 accountId, IERC20 erc20)
        public
        view
        onlyProxy
        returns (
            bytes32 streamsHash,
            bytes32 streamsHistoryHash,
            uint32 updateTime,
            uint128 balance,
            uint32 maxEnd
        )
    {
        return Streams._streamsState(accountId, erc20);
    }

    /// @inheritdoc IDrips
    function balanceAt(
        uint256 accountId,
        IERC20 erc20,
        StreamReceiver[] memory currReceivers,
        uint32 timestamp
    ) public view onlyProxy returns (uint128 balance) {
        return Streams._balanceAt(accountId, erc20, currReceivers, timestamp);
    }

    /// @inheritdoc IDrips
    function setStreams(
        uint256 accountId,
        IERC20 erc20,
        StreamReceiver[] memory currReceivers,
        int128 balanceDelta,
        StreamReceiver[] memory newReceivers,
        MaxEndHints maxEndHints
    ) public onlyProxy onlyDriver(accountId) returns (int128 realBalanceDelta) {
        if (balanceDelta > 0) _increaseStreamsBalance(erc20, uint128(balanceDelta));
        realBalanceDelta = Streams._setStreams(
            accountId, erc20, currReceivers, balanceDelta, newReceivers, maxEndHints
        );
        if (realBalanceDelta < 0) _decreaseStreamsBalance(erc20, uint128(-realBalanceDelta));
    }

    /// @inheritdoc IDrips
    function hashStreams(StreamReceiver[] memory receivers)
        public
        pure
        returns (bytes32 streamsHash)
    {
        return Streams._hashStreams(receivers);
    }

    /// @inheritdoc IDrips
    function hashStreamsHistory(
        bytes32 oldStreamsHistoryHash,
        bytes32 streamsHash,
        uint32 updateTime,
        uint32 maxEnd
    ) public pure returns (bytes32 streamsHistoryHash) {
        return Streams._hashStreamsHistory(oldStreamsHistoryHash, streamsHash, updateTime, maxEnd);
    }

    /// @inheritdoc IDrips
    function setSplits(uint256 accountId, SplitsReceiver[] calldata receivers)
        public
        onlyProxy
        onlyDriver(accountId)
    {
        Splits._setSplits(accountId, receivers);
    }

    /// @inheritdoc IDrips
    function splitsHash(uint256 accountId) public view onlyProxy returns (bytes32 currSplitsHash) {
        return Splits._splitsHash(accountId);
    }

    /// @inheritdoc IDrips
    function hashSplits(SplitsReceiver[] calldata receivers)
        public
        pure
        returns (bytes32 receiversHash)
    {
        return Splits._hashSplits(receivers);
    }

    /// @inheritdoc IDrips
    function emitAccountMetadata(uint256 accountId, AccountMetadata[] calldata accountMetadata)
        public
        onlyProxy
        onlyDriver(accountId)
    {
        unchecked {
            for (uint256 i = 0; i < accountMetadata.length; i++) {
                AccountMetadata calldata metadata = accountMetadata[i];
                emit AccountMetadataEmitted(accountId, metadata.key, metadata.value);
            }
        }
    }

    /// @notice Returns the Drips storage.
    /// @return storageRef The storage.
    function _dripsStorage() internal view returns (DripsStorage storage storageRef) {
        bytes32 slot = _dripsStorageSlot;
        // slither-disable-next-line assembly
        assembly {
            storageRef.slot := slot
        }
    }
}
