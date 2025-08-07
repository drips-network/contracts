// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {AccountMetadata, Drips, StreamReceiver, IERC20, SplitsReceiver} from "./Drips.sol";
import {DriverTransferUtils} from "./DriverTransferUtils.sol";
import {Managed} from "./Managed.sol";
import {StorageSlot} from "openzeppelin-contracts/utils/StorageSlot.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";

/// @notice A Drips driver implementing account identification controlled by the oracle.
/// The oracle may support up to 128 sources and each source has an independent space of names.
/// Each source and name pair has a single account ID deterministically assigned
/// and may have its ownership looked up by the oracle.
/// By default the accounts have no owners and they can't be controlled by anybody,
/// use `updateOwnerByLit` to update the owner using signed payload obtained from the oracle.
contract RepoDriver is DriverTransferUtils, Managed {
    /// @notice The Drips address used by this driver.
    Drips public immutable drips;
    /// @notice The driver ID which this driver uses when calling Drips.
    uint32 public immutable driverId;
    /// @notice The name of the chain where the contract is deployed.
    /// Oracle payloads are accepted only if they are signed for this chain name.
    bytes32 public immutable chain;

    /// @notice Returns account ownership storage.
    /// @return accountOwner The storage.
    function _accountOwner(uint256 accountId)
        internal
        view
        returns (AccountOwner storage accountOwner)
    {
        RepoDriverStorage storage repoDriverStorage;
        bytes32 slot = _repoDriverStorageSlot;
        // slither-disable-next-line assembly
        assembly {
            repoDriverStorage.slot := slot
        }
        return repoDriverStorage.accountOwners[accountId];
    }

    /// @notice The ERC-1967 storage slot holding a single `RepoDriverStorage` structure.
    /// This value is an immutable so it can be pre-calculated and cached in the constructor
    /// for the `_accountOwner` function so it doesn't need to be calculated during runtime.
    bytes32 private immutable _repoDriverStorageSlot = _erc1967Slot("eip1967.repoDriver.storage");

    /// @notice Returns the Lit oracle address storage slot.
    /// @return litOracleAddressSlot The storage.
    function _litOracle()
        internal
        view
        returns (StorageSlot.AddressSlot storage litOracleAddressSlot)
    {
        return StorageSlot.getAddressSlot(_litOracleAddressSlot);
    }

    /// @notice The ERC-1967 storage slot holding the Lit oracle address.
    /// This value is an immutable so it can be pre-calculated and cached in the constructor
    /// for the `_litOracle` function so it doesn't need to be calculated during runtime.
    bytes32 private immutable _litOracleAddressSlot = _erc1967Slot("eip1967.repoDriver.lit.oracle");

    /// @notice Emitted when the account ownership is updated.
    /// @param accountId The ID of the account.
    /// @param owner The new owner of the repository.
    event OwnerUpdated(uint256 indexed accountId, address owner);

    /// @notice Emitted when an account ID is seen in a call.
    /// @param accountId The ID of the account.
    /// @param sourceId The source for the oracle to look up the account ownership.
    /// @param name The source-specific name identifying the account.
    event AccountIdSeen(uint256 indexed accountId, uint8 sourceId, bytes name);

    struct RepoDriverStorage {
        /// @notice The owners of the accounts.
        mapping(uint256 accountId => AccountOwner) accountOwners;
    }

    struct AccountOwner {
        /// @notice The current owner of the account.
        address owner;
        /// @notice The timestamp when the oracle looked up the account ownership.
        uint32 timestamp;
    }

    modifier onlyOwner(uint256 accountId) {
        require(_msgSender() == ownerOf(accountId), "Caller is not the account owner");
        _;
    }

    /// @param drips_ The Drips contract to use.
    /// @param forwarder The ERC-2771 forwarder to trust. May be the zero address.
    /// @param driverId_ The driver ID to use when calling Drips.
    /// @param chain_ The name of the chain where the contract is deployed.
    /// Oracle payloads are accepted only if they are signed for this chain name.
    constructor(Drips drips_, address forwarder, uint32 driverId_, bytes32 chain_)
        DriverTransferUtils(forwarder)
    {
        drips = drips_;
        driverId = driverId_;
        chain = chain_;
    }

    /// @notice Returns the address of the Drips contract to use for ERC-20 transfers.
    function _drips() internal view override returns (Drips) {
        return drips;
    }

    /// @notice Calculates the account ID.
    /// Every account ID is a 256-bit integer constructed by concatenating:
    /// `driverId (32 bits) | sourceId (7 bits) | isHash (1 bit) | nameEncoded (216 bits)`.
    /// When `name` is at most 27 bytes long, `isHash` is 0
    /// and nameEncoded` is `name` right-padded with zeros.
    /// When `name` is longer than 27 bytes, `isHash` is 1
    /// and `nameEncoded` is the lower 27 bytes of the hash of `name`.
    /// @param sourceId The source for the oracle to look up the account ownership.
    /// @param name The source-specific name identifying the account.
    /// @return accountId The account ID.
    function calcAccountId(uint8 sourceId, bytes calldata name)
        public
        view
        returns (uint256 accountId)
    {
        require(sourceId >> 7 == 0, "Source ID too high");
        bool isHash = name.length > 27;
        // Use the lower 27 bytes of the hash of the name or the raw name right-padded with zeros.
        uint216 nameEncoded = isHash ? uint216(uint256(keccak256(name))) : uint216(bytes27(name));
        // By assignment we get `accountId` value:
        // `zeros (224 bits) | driverId (32 bits)`
        accountId = driverId;
        // By bit shifting we get `accountId` value:
        // `zeros (217 bits) | driverId (32 bits) | zeros (7 bits)`
        // By bit masking we get `accountId` value:
        // `zeros (217 bits) | driverId (32 bits) | sourceId (7 bits)`
        accountId = (accountId << 7) | sourceId;
        // By bit shifting we get `accountId` value:
        // `zeros (216 bits) | driverId (32 bits) | sourceId (7 bits) | zeros (1 bit)`
        // By bit masking we get `accountId` value:
        // `zeros (216 bits) | driverId (32 bits) | sourceId (7 bits) | isHash (1 bit)`
        accountId = (accountId << 1) | (isHash ? 1 : 0);
        // By bit shifting we get `accountId` value:
        // `driverId (32 bits) | sourceId (7 bits) | isHash (1 bit) | zeros (216 bits)`
        // By bit masking we get `accountId` value:
        // `driverId (32 bits) | sourceId (7 bits) | isHash (1 bit) | nameEncoded (216 bits)`
        accountId = (accountId << 216) | nameEncoded;
    }

    /// @notice Calculates and emits the account ID.
    /// See `calcAccountId` documentation for the details on how the account ID is calculated.
    /// @param sourceId The source for the oracle to look up the account ownership.
    /// @param name The source-specific name identifying the account.
    /// @return accountId The account ID.
    function emitAccountId(uint8 sourceId, bytes calldata name)
        public
        returns (uint256 accountId)
    {
        accountId = calcAccountId(sourceId, name);
        emit AccountIdSeen(accountId, sourceId, name);
    }

    /// @notice Gets the account owner.
    /// @param accountId The ID of the account.
    /// @return owner The owner of the account.
    function ownerOf(uint256 accountId) public view returns (address owner) {
        return _accountOwner(accountId).owner;
    }

    /// @notice Updates the Lit oracle address. Can only be called by the current admin.
    /// @param litOracle_ The new Lit oracle address.
    function updateLitOracle(address litOracle_) public onlyAdminOrConstructor {
        _litOracle().value = litOracle_;
    }

    /// @notice Returns the Lit oracle address.
    /// @return litOracle_ The Lit oracle address.
    function litOracle() public view returns (address litOracle_) {
        return _litOracle().value;
    }

    /// @notice Updates the account owner.
    /// The payload of this function must be signed by the Lit oracle as returned by `litOracle`.
    /// The signature must be made for the parameters passed into this function
    /// and the name of the chain on which this contract is deployed as returned by `chain`.
    /// @param sourceId The source for the oracle to look up the account ownership.
    /// @param name The source-specific name identifying the account.
    /// @param owner The new owner of the account.
    /// @param timestamp The timestamp when the oracle looked up the account ownership.
    /// It must be newer than the timestamp used in the last ownership update of this account.
    /// @param r The `r` part of the payload compact signature as per EIP-2098.
    /// @param vs The `vs` part of the payload compact signature as per EIP-2098.
    /// @return accountId The account ID for which the owner was updated.
    function updateOwnerByLit(
        uint8 sourceId,
        bytes calldata name,
        address owner,
        uint32 timestamp,
        bytes32 r,
        bytes32 vs
    ) public whenNotPaused returns (uint256 accountId) {
        accountId = calcAccountId(sourceId, name);
        AccountOwner storage accountOwner = _accountOwner(accountId);

        uint32 lastTimestamp = accountOwner.timestamp;
        require(timestamp > lastTimestamp, "Payload obsolete");

        bytes32 sigHash = keccak256(
            "DripsOwnership(bytes32 chain,uint8 sourceId,bytes name,address owner,uint32 timestamp)"
        );
        bytes32 structHash =
            keccak256(abi.encode(sigHash, chain, sourceId, keccak256(name), owner, timestamp));
        address signer = ECDSA.recover(ECDSA.toTypedDataHash(_domainSeparator, structHash), r, vs);
        require(signer == litOracle(), "Invalid Lit oracle signature");

        accountOwner.owner = owner;
        accountOwner.timestamp = timestamp;
        if (lastTimestamp == 0) emit AccountIdSeen(accountId, sourceId, name);
        emit OwnerUpdated(accountId, owner);
    }

    /// This value is an immutable so it can be pre-calculated and cached in the constructor
    /// for the `updateOwnerByLit` function so it doesn't need to be calculated during runtime.
    bytes32 private immutable _domainSeparator = keccak256(
        abi.encode(
            keccak256("EIP712Domain(string name,string version)"),
            keccak256("DripsOwnership"),
            keccak256("1")
        )
    );

    /// @notice Collects the account's received already split funds
    /// and transfers them out of the Drips contract.
    /// @param accountId The ID of the collecting account.
    /// The caller must be the owner of the account.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param transferTo The address to send collected funds to
    /// @return amt The collected amount
    function collect(uint256 accountId, IERC20 erc20, address transferTo)
        public
        whenNotPaused
        onlyOwner(accountId)
        returns (uint128 amt)
    {
        amt = drips.collect(accountId, erc20);
        if (amt > 0) drips.withdraw(erc20, transferTo, amt);
    }

    /// @notice Gives funds from the account to the receiver.
    /// The receiver can split and collect them immediately.
    /// Transfers the funds to be given from the message sender's wallet to the Drips contract.
    /// @param accountId The ID of the giving account. The caller must be the owner of the account.
    /// @param receiver The receiver account ID.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param amt The given amount
    function give(uint256 accountId, uint256 receiver, IERC20 erc20, uint128 amt)
        public
        whenNotPaused
        onlyOwner(accountId)
    {
        _giveAndTransfer(accountId, receiver, erc20, amt);
    }

    /// @notice Sets the account's streams configuration.
    /// Transfers funds between the message sender's wallet and the Drips contract
    /// to fulfil the change of the streams balance.
    /// @param accountId The ID of the configured account.
    /// The caller must be the owner of the account.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param currReceivers The current streams receivers list.
    /// It must be exactly the same as the last list set for the account with `setStreams`.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The streams balance change to be applied.
    /// Positive to add funds to the streams balance, negative to remove them.
    /// @param newReceivers The list of the streams receivers of the sender to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @param maxEndHint1 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The first hint for finding the maximum end time when all streams stop due to funds
    /// running out after the balance is updated and the new receivers list is applied.
    /// Hints have no effect on the results of calling this function, except potentially saving gas.
    /// Hints are Unix timestamps used as the starting points for binary search for the time
    /// when funds run out in the range of timestamps from the current block's to `2^32`.
    /// Hints lower than the current timestamp are ignored.
    /// You can provide zero, one or two hints. The order of hints doesn't matter.
    /// Hints are the most effective when one of them is lower than or equal to
    /// the last timestamp when funds are still streamed, and the other one is strictly larger
    /// than that timestamp,the smaller the difference between such hints, the higher gas savings.
    /// The savings are the highest possible when one of the hints is equal to
    /// the last timestamp when funds are still streamed, and the other one is larger by 1.
    /// It's worth noting that the exact timestamp of the block in which this function is executed
    /// may affect correctness of the hints, especially if they're precise.
    /// Hints don't provide any benefits when balance is not enough to cover
    /// a single second of streaming or is enough to cover all streams until timestamp `2^32`.
    /// Even inaccurate hints can be useful, and providing a single hint
    /// or two hints that don't enclose the time when funds run out can still save some gas.
    /// Providing poor hints that don't reduce the number of binary search steps
    /// may cause slightly higher gas usage than not providing any hints.
    /// @param maxEndHint2 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The second hint for finding the maximum end time, see `maxEndHint1` docs for more details.
    /// @param transferTo The address to send funds to in case of decreasing balance
    /// @return realBalanceDelta The actually applied streams balance change.
    function setStreams(
        uint256 accountId,
        IERC20 erc20,
        StreamReceiver[] calldata currReceivers,
        int128 balanceDelta,
        StreamReceiver[] calldata newReceivers,
        uint32 maxEndHint1,
        uint32 maxEndHint2,
        address transferTo
    ) public whenNotPaused onlyOwner(accountId) returns (int128 realBalanceDelta) {
        return _setStreamsAndTransfer(
            accountId,
            erc20,
            currReceivers,
            balanceDelta,
            newReceivers,
            maxEndHint1,
            maxEndHint2,
            transferTo
        );
    }

    /// @notice Sets the account splits configuration.
    /// The configuration is common for all ERC-20 tokens.
    /// Nothing happens to the currently splittable funds, but when they are split
    /// after this function finishes, the new splits configuration will be used.
    /// Because anybody can call `split` on `Drips`, calling this function may be frontrun
    /// and all the currently splittable funds will be split using the old splits configuration.
    /// @param accountId The ID of the configured account.
    /// The caller must be the owner of the account.
    /// @param receivers The list of the account's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the account.
    /// If the sum of weights of all receivers is less than `_TOTAL_SPLITS_WEIGHT`,
    /// some funds won't be split, but they will be left for the account to collect.
    /// It's valid to include the account's own `accountId` in the list of receivers,
    /// but funds split to themselves return to their splittable balance and are not collectable.
    /// This is usually unwanted, because if splitting is repeated,
    /// funds split to themselves will be again split using the current configuration.
    /// Splitting 100% to self effectively blocks splitting unless the configuration is updated.
    function setSplits(uint256 accountId, SplitsReceiver[] calldata receivers)
        public
        whenNotPaused
        onlyOwner(accountId)
    {
        drips.setSplits(accountId, receivers);
    }

    /// @notice Emits the account's metadata.
    /// The keys and the values are not standardized by the protocol, it's up to the users
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param accountId The ID of the emitting account.
    /// The caller must be the owner of the account.
    /// @param accountMetadata The list of account metadata.
    function emitAccountMetadata(uint256 accountId, AccountMetadata[] calldata accountMetadata)
        public
        whenNotPaused
        onlyOwner(accountId)
    {
        if (accountMetadata.length == 0) return;
        drips.emitAccountMetadata(accountId, accountMetadata);
    }
}
