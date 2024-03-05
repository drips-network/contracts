// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

import "./IRepoDriverAnyApi.sol";
import {DriverTransferUtils} from "./DriverTransferUtils.sol";
import {Managed} from "./Managed.sol";
import {BufferChainlink, CBORChainlink} from "chainlink/Chainlink.sol";
import {ShortString, ShortStrings} from "openzeppelin-contracts/utils/ShortStrings.sol";

/// @notice The implementation of `IRepoDriverAnyApi`, see its documentation for more details.
contract RepoDriver is IRepoDriverAnyApi, DriverTransferUtils, Managed {
    using CBORChainlink for BufferChainlink.buffer;

    /// @inheritdoc IRepoDriver
    IDrips public immutable drips;
    /// @inheritdoc IRepoDriver
    uint32 public immutable driverId;
    /// @inheritdoc IRepoDriverAnyApi
    LinkTokenInterface public immutable linkToken;
    /// @notice The JSON path inside `FUNDING.json` where the account ID owner is stored.
    ShortString internal immutable jsonPath;

    /// @notice The ERC-1967 storage slot holding a single `RepoDriverStorage` structure.
    bytes32 private immutable _repoDriverStorageSlot = _erc1967Slot("eip1967.repoDriver.storage");
    /// @notice The ERC-1967 storage slot holding a single `RepoDriverAnyApiStorage` structure.
    bytes32 private immutable _repoDriverAnyApiStorageSlot =
        _erc1967Slot("eip1967.repoDriver.anyApi.storage");

    struct RepoDriverStorage {
        /// @notice The owners of the accounts.
        mapping(uint256 accountId => address) accountOwners;
    }

    struct RepoDriverAnyApiStorage {
        /// @notice The requested account owner updates.
        mapping(bytes32 requestId => uint256 accountId) requestedUpdates;
        /// @notice The new address of the AnyApi operator.
        OperatorInterface operator;
        /// @notice The fee in Link for each account owner
        /// update request when the driver is covering the cost.
        /// The fee must be high enough for the operator to accept the requests,
        /// refer to their documentation to see what's the minimum value.
        uint96 defaultFee;
        /// @notice The AnyApi job ID used for requesting account owner updates.
        bytes32 jobId;
        /// @notice If false, the initial operator configuration is possible.
        bool isInitialized;
        /// @notice The AnyApi requests counter used as a nonce when calculating the request ID.
        uint248 nonce;
    }

    /// @param drips_ The Drips contract to use.
    /// @param forwarder The ERC-2771 forwarder to trust. May be the zero address.
    /// @param driverId_ The driver ID to use when calling Drips.
    constructor(IDrips drips_, address forwarder, uint32 driverId_)
        DriverTransferUtils(forwarder)
    {
        drips = drips_;
        driverId = driverId_;
        string memory chainName;
        address _linkToken;
        if (block.chainid == 1) {
            chainName = "ethereum";
            _linkToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        } else if (block.chainid == 5) {
            chainName = "goerli";
            _linkToken = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
        } else if (block.chainid == 11155111) {
            chainName = "sepolia";
            _linkToken = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
        } else {
            chainName = "other";
            _linkToken = address(bytes20("dummy link token"));
        }
        jsonPath = ShortStrings.toShortString(string.concat("drips,", chainName, ",ownedBy"));
        linkToken = LinkTokenInterface(_linkToken);
    }

    modifier onlyOwner(uint256 accountId) {
        require(_msgSender() == ownerOf(accountId), "Caller is not the account owner");
        _;
    }

    /// @inheritdoc IRepoDriver
    function calcAccountId(Forge forge, bytes memory name)
        public
        view
        onlyProxy
        returns (uint256 accountId)
    {
        uint8 forgeId;
        uint216 nameEncoded;
        if (forge == Forge.GitHub) {
            if (name.length <= 27) {
                forgeId = 0;
                nameEncoded = uint216(bytes27(name));
            } else {
                forgeId = 1;
                // `nameEncoded` is the lower 27 bytes of the hash
                nameEncoded = uint216(uint256(keccak256(name)));
            }
        } else {
            if (name.length <= 27) {
                forgeId = 2;
                nameEncoded = uint216(bytes27(name));
            } else {
                forgeId = 3;
                // `nameEncoded` is the lower 27 bytes of the hash
                nameEncoded = uint216(uint256(keccak256(name)));
            }
        }
        // By assignment we get `accountId` value:
        // `zeros (224 bits) | driverId (32 bits)`
        accountId = driverId;
        // By bit shifting we get `accountId` value:
        // `zeros (216 bits) | driverId (32 bits) | zeros (8 bits)`
        // By bit masking we get `accountId` value:
        // `zeros (216 bits) | driverId (32 bits) | forgeId (8 bits)`
        accountId = (accountId << 8) | forgeId;
        // By bit shifting we get `accountId` value:
        // `driverId (32 bits) | forgeId (8 bits) | zeros (216 bits)`
        // By bit masking we get `accountId` value:
        // `driverId (32 bits) | forgeId (8 bits) | nameEncoded (216 bits)`
        accountId = (accountId << 216) | nameEncoded;
    }

    /// @notice Initializes the AnyApi operator configuration.
    /// Callable only once, and only before any calls to `updateAnyApiOperator`.
    /// @param operator The initial address of the AnyApi operator.
    /// @param jobId The initial AnyApi job ID used for requesting account owner updates.
    /// @param defaultFee The initial fee in Link for each account owner
    /// update request when the driver is covering the cost.
    /// The fee must be high enough for the operator to accept the requests,
    /// refer to their documentation to see what's the minimum value.
    function initializeAnyApiOperator(OperatorInterface operator, bytes32 jobId, uint96 defaultFee)
        public
        onlyProxy
    {
        require(!_repoDriverAnyApiStorage().isInitialized, "Already initialized");
        _updateAnyApiOperator(operator, jobId, defaultFee);
    }

    /// @notice Updates the AnyApi operator configuration. Callable only by the admin.
    /// @param operator The new address of the AnyApi operator.
    /// @param jobId The new AnyApi job ID used for requesting account owner updates.
    /// @param defaultFee The new fee in Link for each account owner
    /// update request when the driver is covering the cost.
    /// The fee must be high enough for the operator to accept the requests,
    /// refer to their documentation to see what's the minimum value.
    function updateAnyApiOperator(OperatorInterface operator, bytes32 jobId, uint96 defaultFee)
        public
        onlyProxy
        onlyAdmin
    {
        _updateAnyApiOperator(operator, jobId, defaultFee);
    }

    /// @notice Updates the AnyApi operator configuration. Callable only by the admin.
    /// @param operator The new address of the AnyApi operator.
    /// @param jobId The new AnyApi job ID used for requesting account owner updates.
    /// @param defaultFee The new fee in Link for each account owner
    /// update request when the driver is covering the cost.
    /// The fee must be high enough for the operator to accept the requests,
    /// refer to their documentation to see what's the minimum value.
    function _updateAnyApiOperator(OperatorInterface operator, bytes32 jobId, uint96 defaultFee)
        internal
    {
        RepoDriverAnyApiStorage storage storageRef = _repoDriverAnyApiStorage();
        storageRef.isInitialized = true;
        storageRef.operator = operator;
        storageRef.jobId = jobId;
        storageRef.defaultFee = defaultFee;
        emit AnyApiOperatorUpdated(operator, jobId, defaultFee);
    }

    /// @inheritdoc IRepoDriverAnyApi
    function anyApiOperator()
        public
        view
        onlyProxy
        returns (OperatorInterface operator, bytes32 jobId, uint96 defaultFee)
    {
        RepoDriverAnyApiStorage storage storageRef = _repoDriverAnyApiStorage();
        operator = storageRef.operator;
        jobId = storageRef.jobId;
        defaultFee = storageRef.defaultFee;
    }

    /// @inheritdoc IRepoDriver
    function ownerOf(uint256 accountId) public view onlyProxy returns (address owner) {
        return _repoDriverStorage().accountOwners[accountId];
    }

    /// @inheritdoc IRepoDriverAnyApi
    function requestUpdateOwner(Forge forge, bytes memory name)
        public
        onlyProxy
        returns (uint256 accountId)
    {
        uint256 fee = _repoDriverAnyApiStorage().defaultFee;
        require(linkToken.balanceOf(address(this)) >= fee, "Link balance too low");
        return _requestUpdateOwner(forge, name, fee);
    }

    /// @inheritdoc IRepoDriverAnyApi
    function onTokenTransfer(address, /* sender */ uint256 amount, bytes calldata data)
        public
        onlyProxy
    {
        require(msg.sender == address(linkToken), "Callable only by the Link token");
        require(data.length >= 4, "Data not a valid calldata");
        require(bytes4(data[:4]) == this.requestUpdateOwner.selector, "Data not requestUpdateOwner");
        (Forge forge, bytes memory name) = abi.decode(data[4:], (Forge, bytes));
        _requestUpdateOwner(forge, name, amount);
    }

    /// @notice Requests an update of the ownership of the account representing the repository.
    /// See `requestUpdateOwner` for more details.
    /// @param forge The forge where the repository is stored.
    /// @param name The name of the repository.
    /// @param fee The fee in Link to pay for the request.
    /// @return accountId The ID of the account.
    function _requestUpdateOwner(Forge forge, bytes memory name, uint256 fee)
        internal
        returns (uint256 accountId)
    {
        RepoDriverAnyApiStorage storage storageRef = _repoDriverAnyApiStorage();
        address operator = address(storageRef.operator);
        require(operator != address(0), "Operator address not set");
        uint256 nonce = storageRef.nonce++;
        bytes32 requestId = keccak256(abi.encodePacked(this, nonce));
        accountId = calcAccountId(forge, name);
        storageRef.requestedUpdates[requestId] = accountId;
        bytes memory payload = _requestPayload(forge, name);
        bytes memory callData = abi.encodeCall(
            OperatorInterface.operatorRequest,
            (
                address(0), // ignored, will be replaced in the operator with this contract address
                0, // ignored, will be replaced in the operator with the fee
                storageRef.jobId,
                this.updateOwnerByAnyApi.selector,
                nonce,
                2, // data version
                payload
            )
        );
        require(linkToken.transferAndCall(operator, fee, callData), "Transfer and call failed");
        // slither-disable-next-line reentrancy-events
        emit OwnerUpdateRequested(accountId, forge, name);
    }

    /// @notice Builds the AnyApi generic `bytes` fetching request payload.
    /// It instructs the operator to fetch the current owner of the account.
    /// @param forge The forge where the repository is stored.
    /// @param name The name of the repository.
    /// @return payload The AnyApi request payload.
    function _requestPayload(Forge forge, bytes memory name)
        internal
        view
        returns (bytes memory payload)
    {
        // slither-disable-next-line uninitialized-local
        BufferChainlink.buffer memory buffer;
        buffer = BufferChainlink.init(buffer, 256);
        buffer.encodeString("get");
        buffer.encodeString(_requestUrl(forge, name));
        buffer.encodeString("path");
        buffer.encodeString(ShortStrings.toString(jsonPath));
        return buffer.buf;
    }

    /// @notice Builds the URL for fetch the `FUNDING.json` file for the given repository.
    /// @param forge The forge where the repository is stored.
    /// @param name The name of the repository.
    /// @return url The built URL.
    function _requestUrl(Forge forge, bytes memory name)
        internal
        pure
        returns (string memory url)
    {
        if (forge == Forge.GitHub) {
            return string.concat(
                "https://raw.githubusercontent.com/", string(name), "/HEAD/FUNDING.json"
            );
        } else if (forge == Forge.GitLab) {
            return string.concat("https://gitlab.com/", string(name), "/-/raw/HEAD/FUNDING.json");
        } else {
            revert("Unsupported forge");
        }
    }

    /// @notice Updates the account owner. Callable only by the AnyApi operator.
    /// @param requestId The ID of the AnyApi request.
    /// Must be the same as the request ID generated when requesting an owner update,
    /// this function will update the account ownership that was requested back then.
    /// @param ownerRaw The new owner of the account. Must be a 20 bytes long address.
    function updateOwnerByAnyApi(bytes32 requestId, bytes calldata ownerRaw) public onlyProxy {
        RepoDriverAnyApiStorage storage storageRef = _repoDriverAnyApiStorage();
        require(msg.sender == address(storageRef.operator), "Callable only by the operator");
        uint256 accountId = storageRef.requestedUpdates[requestId];
        require(accountId != 0, "Unknown request ID");
        delete storageRef.requestedUpdates[requestId];
        require(ownerRaw.length == 20, "Invalid owner length");
        address owner = address(bytes20(ownerRaw));
        _repoDriverStorage().accountOwners[accountId] = owner;
        emit OwnerUpdated(accountId, owner);
    }

    /// @inheritdoc IRepoDriver
    function collect(uint256 accountId, IERC20 erc20, address transferTo)
        public
        onlyProxy
        onlyOwner(accountId)
        returns (uint128 amt)
    {
        return _collectAndTransfer(drips, accountId, erc20, transferTo);
    }

    /// @inheritdoc IRepoDriver
    function give(uint256 accountId, uint256 receiver, IERC20 erc20, uint128 amt)
        public
        onlyProxy
        onlyOwner(accountId)
    {
        _giveAndTransfer(drips, accountId, receiver, erc20, amt);
    }

    /// @inheritdoc IRepoDriver
    function setStreams(
        uint256 accountId,
        IERC20 erc20,
        StreamReceiver[] calldata currReceivers,
        int128 balanceDelta,
        StreamReceiver[] calldata newReceivers,
        MaxEndHints maxEndHints,
        address transferTo
    ) public onlyProxy onlyOwner(accountId) returns (int128 realBalanceDelta) {
        return _setStreamsAndTransfer(
            drips,
            accountId,
            erc20,
            currReceivers,
            balanceDelta,
            newReceivers,
            maxEndHints,
            transferTo
        );
    }

    /// @inheritdoc IRepoDriver
    function setSplits(uint256 accountId, SplitsReceiver[] calldata receivers)
        public
        onlyProxy
        onlyOwner(accountId)
    {
        drips.setSplits(accountId, receivers);
    }

    /// @inheritdoc IRepoDriver
    function emitAccountMetadata(uint256 accountId, AccountMetadata[] calldata accountMetadata)
        public
        onlyProxy
        onlyOwner(accountId)
    {
        if (accountMetadata.length != 0) {
            drips.emitAccountMetadata(accountId, accountMetadata);
        }
    }

    /// @notice Returns the RepoDriver storage.
    /// @return storageRef The storage.
    function _repoDriverStorage() internal view returns (RepoDriverStorage storage storageRef) {
        bytes32 slot = _repoDriverStorageSlot;
        // slither-disable-next-line assembly
        assembly {
            storageRef.slot := slot
        }
    }

    /// @notice Returns the RepoDriver storage specific to AnyApi.
    /// @return storageRef The storage.
    function _repoDriverAnyApiStorage()
        internal
        view
        returns (RepoDriverAnyApiStorage storage storageRef)
    {
        bytes32 slot = _repoDriverAnyApiStorageSlot;
        // slither-disable-next-line assembly
        assembly {
            storageRef.slot := slot
        }
    }
}
