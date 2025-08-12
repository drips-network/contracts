// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

// This is the old deployment system used only on Ethereum and Sepolia.

import {AddressDriver} from "src/AddressDriver.sol";
import {Caller} from "src/Caller.sol";
import {Drips} from "src/Drips.sol";
import {GiversRegistry} from "src/Giver.sol";
import {ImmutableSplitsDriver} from "src/ImmutableSplitsDriver.sol";
import {IWrappedNativeToken} from "src/IWrappedNativeToken.sol";
import {Managed, ManagedProxy} from "src/Managed.sol";
import {NativeTokenUnwrapper} from "src/NativeTokenUnwrapper.sol";
import {NFTDriver} from "src/NFTDriver.sol";
import {RepoDeadlineDriver} from "src/RepoDeadlineDriver.sol";
import {IAutomate, RepoDriver} from "src/RepoDriver.sol";
import {RepoSubAccountDriver} from "src/RepoSubAccountDriver.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

struct Module {
    bytes32 salt;
    uint256 amount;
    bytes initCode;
}

function requireDripsDeployer(uint256 chainId, address deployerAddr)
    view
    returns (DripsDeployer deployer)
{
    require(
        block.chainid == chainId,
        string.concat("The script must be run on the chain with ID ", Strings.toString(chainId))
    );
    deployer = DripsDeployer(deployerAddr);
    require(msg.sender == deployer.owner(), "Must be run with the deployer wallet");
}

contract DripsDeployer is Ownable2Step {
    bytes32[] internal _moduleSalts;
    address public immutable initialOwner;

    function args() public view returns (bytes memory) {
        return abi.encode(initialOwner);
    }

    constructor(address initialOwner_) {
        // slither-disable-next-line missing-zero-check
        initialOwner = initialOwner_;
        _transferOwnership(initialOwner);
    }

    function deployModules(
        Module[] calldata modules1,
        Module[] calldata modules2,
        Module[] calldata modules3,
        Module[] calldata modules4
    ) public onlyOwner {
        _deployModules(modules1);
        _deployModules(modules2);
        _deployModules(modules3);
        _deployModules(modules4);
    }

    function _deployModules(Module[] calldata modules) internal {
        for (uint256 i = 0; i < modules.length; i++) {
            Module calldata module = modules[i];
            _moduleSalts.push(module.salt);
            // slither-disable-next-line reentrancy-eth,reentrancy-no-eth
            Create3Factory.deploy(module.amount, module.salt, module.initCode);
        }
    }

    function moduleSalts() public view returns (bytes32[] memory) {
        return _moduleSalts;
    }

    function moduleAddress(bytes32 salt) public view returns (address addr) {
        return Create3Factory.getDeployed(salt);
    }
}

abstract contract BaseModule {
    DripsDeployer public immutable dripsDeployer;
    bytes32 public immutable moduleSalt;

    constructor(DripsDeployer dripsDeployer_, bytes32 moduleSalt_) {
        dripsDeployer = dripsDeployer_;
        moduleSalt = moduleSalt_;
        require(address(this) == _moduleAddress(moduleSalt_), "Invalid module deployment salt");
    }

    function args() public view virtual returns (bytes memory);

    function _moduleAddress(bytes32 salt) internal view returns (address addr) {
        return dripsDeployer.moduleAddress(salt);
    }

    modifier onlyModule(bytes32 salt) {
        require(msg.sender == _moduleAddress(bytes32(salt)));
        _;
    }
}

abstract contract ContractDeployerModule is BaseModule {
    bytes32 public immutable salt = "deployment";

    function deployment() public view returns (address) {
        return Create3Factory.getDeployed(salt);
    }

    function deploymentArgs() public view virtual returns (bytes memory);

    function _deployContract(bytes memory creationCode) internal {
        Create3Factory.deploy(0, salt, abi.encodePacked(creationCode, deploymentArgs()));
    }
}

abstract contract ProxyDeployerModule is BaseModule {
    bytes32 public immutable proxySalt = "proxy";
    address public proxyAdmin;
    address public logic;
    bytes public proxyDelegateCalldata;

    function proxy() public view returns (address) {
        return Create3Factory.getDeployed(proxySalt);
    }

    function proxyArgs() public view returns (bytes memory) {
        return abi.encode(logic, proxyAdmin, proxyDelegateCalldata);
    }

    function logicArgs() public view virtual returns (bytes memory);

    function _deployProxy(address proxyAdmin_, bytes memory logicCreationCode) internal {
        _deployProxy(proxyAdmin_, logicCreationCode, "");
    }

    // slither-disable-next-line reentrancy-benign
    function _deployProxy(
        address proxyAdmin_,
        bytes memory logicCreationCode,
        bytes memory proxyDelegateCalldata_
    ) internal {
        // Deploy logic
        address logic_;
        bytes memory logicInitCode = abi.encodePacked(logicCreationCode, logicArgs());
        // slither-disable-next-line assembly
        assembly ("memory-safe") {
            logic_ := create(0, add(logicInitCode, 32), mload(logicInitCode))
        }
        require(logic_ != address(0), "Logic deployment failed");
        logic = logic_;
        // Deploy proxy
        proxyAdmin = proxyAdmin_;
        proxyDelegateCalldata = proxyDelegateCalldata_;
        // slither-disable-next-line too-many-digits
        bytes memory proxyInitCode = abi.encodePacked(type(ManagedProxy).creationCode, proxyArgs());
        Create3Factory.deploy(0, proxySalt, proxyInitCode);
    }
}

abstract contract DripsDependentModule is BaseModule {
    bytes32 internal immutable _dripsModuleSalt = "Drips";

    function _dripsModule() internal view returns (IDripsModule) {
        address module = _moduleAddress(_dripsModuleSalt);
        require(Address.isContract(module), "Drips module not deployed");
        return IDripsModule(module);
    }
}

interface IDripsModule {
    function drips() external view returns (Drips);
    function claimDriverId(bytes32 moduleSalt_, uint32 driverId, address driverAddr) external;
}

contract DripsModule is IDripsModule, DripsDependentModule, ProxyDeployerModule {
    uint32 public immutable dripsCycleSecs;
    uint32 public immutable claimableDriverIds = 100;

    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, dripsCycleSecs, proxyAdmin);
    }

    constructor(DripsDeployer dripsDeployer_, uint32 dripsCycleSecs_, address proxyAdmin_)
        BaseModule(dripsDeployer_, _dripsModuleSalt)
    {
        dripsCycleSecs = dripsCycleSecs_;
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(Drips).creationCode);
        Drips drips_ = drips();
        for (uint256 i = 0; i < claimableDriverIds; i++) {
            // slither-disable-next-line calls-loop,unused-return
            drips_.registerDriver(address(this));
        }
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(dripsCycleSecs);
    }

    function drips() public view override returns (Drips) {
        return Drips(proxy());
    }

    function claimDriverId(bytes32 moduleSalt_, uint32 driverId, address driverAddr)
        public
        override
        onlyModule(moduleSalt_)
    {
        drips().updateDriverAddress(driverId, driverAddr);
    }
}

abstract contract CallerDependentModule is BaseModule {
    bytes32 internal immutable _callerModuleSalt = "Caller";

    function _callerModule() internal view returns (ICallerModule) {
        address module = _moduleAddress(_callerModuleSalt);
        require(Address.isContract(module), "Caller module not deployed");
        return ICallerModule(module);
    }
}

interface ICallerModule {
    function caller() external view returns (Caller);
}

contract CallerModule is ICallerModule, ContractDeployerModule, CallerDependentModule {
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer);
    }

    constructor(DripsDeployer dripsDeployer_) BaseModule(dripsDeployer_, _callerModuleSalt) {
        // slither-disable-next-line too-many-digits
        _deployContract(type(Caller).creationCode);
    }

    function deploymentArgs() public pure override returns (bytes memory) {
        return abi.encode();
    }

    function caller() public view override returns (Caller) {
        return Caller(deployment());
    }
}

abstract contract DriverModule is DripsDependentModule, ProxyDeployerModule {
    uint32 public immutable driverId;

    constructor(uint32 driverId_) {
        driverId = driverId_;
        _dripsModule().claimDriverId(moduleSalt, driverId, proxy());
    }
}

abstract contract AddressDriverDependentModule is BaseModule {
    bytes32 internal immutable _addressDriverModuleSalt = "AddressDriver";

    // slither-disable-next-line dead-code
    function _addressDriverModule() internal view returns (IAddressDriverModule) {
        address module = _moduleAddress(_addressDriverModuleSalt);
        require(Address.isContract(module), "AddressDriver module not deployed");
        return IAddressDriverModule(module);
    }
}

interface IAddressDriverModule {
    function addressDriver() external view returns (AddressDriver);
}

contract AddressDriverModule is
    IAddressDriverModule,
    AddressDriverDependentModule,
    CallerDependentModule,
    DriverModule(0)
{
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin);
    }

    constructor(DripsDeployer dripsDeployer_, address proxyAdmin_)
        BaseModule(dripsDeployer_, _addressDriverModuleSalt)
    {
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(AddressDriver).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_dripsModule().drips(), _callerModule().caller(), driverId);
    }

    function addressDriver() public view override returns (AddressDriver) {
        return AddressDriver(proxy());
    }
}

abstract contract NFTDriverDependentModule is BaseModule {
    bytes32 internal immutable _nftDriverModuleSalt = "NFTDriver";

    // slither-disable-next-line dead-code
    function _nftDriverModule() internal view returns (INFTDriverModule) {
        address module = _moduleAddress(_nftDriverModuleSalt);
        require(Address.isContract(module), "NFTDriver module not deployed");
        return INFTDriverModule(module);
    }
}

interface INFTDriverModule {
    function nftDriver() external view returns (NFTDriver);
}

contract NFTDriverModule is
    INFTDriverModule,
    NFTDriverDependentModule,
    CallerDependentModule,
    DriverModule(1)
{
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin);
    }

    constructor(DripsDeployer dripsDeployer_, address proxyAdmin_)
        BaseModule(dripsDeployer_, _nftDriverModuleSalt)
    {
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(NFTDriver).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_dripsModule().drips(), _callerModule().caller(), driverId);
    }

    function nftDriver() public view override returns (NFTDriver) {
        return NFTDriver(proxy());
    }
}

abstract contract ImmutableSplitsDriverDependentModule is BaseModule {
    bytes32 internal immutable _immutableSplitsDriverModuleSalt = "ImmutableSplitsDriver";

    // slither-disable-next-line dead-code
    function _immutableSplitsDriverModule() internal view returns (IImmutableSplitsDriverModule) {
        address module = _moduleAddress(_immutableSplitsDriverModuleSalt);
        require(Address.isContract(module), "ImmutableSplitsDriver module not deployed");
        return IImmutableSplitsDriverModule(module);
    }
}

interface IImmutableSplitsDriverModule {
    function immutableSplitsDriver() external view returns (ImmutableSplitsDriver);
}

contract ImmutableSplitsDriverModule is
    IImmutableSplitsDriverModule,
    ImmutableSplitsDriverDependentModule,
    DriverModule(2)
{
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin);
    }

    constructor(DripsDeployer dripsDeployer_, address proxyAdmin_)
        BaseModule(dripsDeployer_, _immutableSplitsDriverModuleSalt)
    {
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(ImmutableSplitsDriver).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_dripsModule().drips(), driverId);
    }

    function immutableSplitsDriver() public view override returns (ImmutableSplitsDriver) {
        return ImmutableSplitsDriver(proxy());
    }
}

abstract contract RepoDriverDependentModule is BaseModule {
    bytes32 internal immutable _repoDriverModuleSalt = "RepoDriver";

    // slither-disable-next-line dead-code
    function _repoDriverModule() internal view returns (IRepoDriverModule) {
        address module = _moduleAddress(_repoDriverModuleSalt);
        require(Address.isContract(module), "RepoDriver module not deployed");
        return IRepoDriverModule(module);
    }
}

interface IRepoDriverModule {
    function repoDriver() external view returns (RepoDriver);
}

contract RepoDriverModule is
    IRepoDriverModule,
    RepoDriverDependentModule,
    CallerDependentModule,
    DriverModule(3)
{
    IAutomate public immutable gelatoAutomate;
    string public ipfsCid;
    uint32 public immutable maxRequestsPerBlock;
    uint32 public immutable maxRequestsPer31Days;

    function args() public view override returns (bytes memory) {
        return abi.encode(
            dripsDeployer,
            proxyAdmin,
            gelatoAutomate,
            ipfsCid,
            maxRequestsPerBlock,
            maxRequestsPer31Days
        );
    }

    constructor(
        DripsDeployer dripsDeployer_,
        address proxyAdmin_,
        IAutomate gelatoAutomate_,
        string memory ipfsCid_,
        uint32 maxRequestsPerBlock_,
        uint32 maxRequestsPer31Days_
    ) BaseModule(dripsDeployer_, _repoDriverModuleSalt) {
        gelatoAutomate = gelatoAutomate_;
        ipfsCid = ipfsCid_;
        maxRequestsPerBlock = maxRequestsPerBlock_;
        maxRequestsPer31Days = maxRequestsPer31Days_;
        bytes memory data = abi.encodeCall(
            RepoDriver.updateGelatoTask, (ipfsCid_, maxRequestsPerBlock, maxRequestsPer31Days)
        );
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(RepoDriver).creationCode, data);
    }

    function logicArgs() public view override returns (bytes memory) {
        return
            abi.encode(_dripsModule().drips(), _callerModule().caller(), driverId, gelatoAutomate);
    }

    function repoDriver() public view override returns (RepoDriver) {
        return RepoDriver(payable(proxy()));
    }
}

bytes32 constant REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT = "RepoSubAccountDriver";

function repoSubAccountDriverModule(DripsDeployer dripsDeployer, address proxyAdmin)
    pure
    returns (Module memory)
{
    bytes memory args = abi.encode(dripsDeployer, proxyAdmin);
    return Module({
        salt: REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT,
        amount: 0,
        initCode: abi.encodePacked(type(RepoSubAccountDriverModule).creationCode, args)
    });
}

abstract contract RepoSubAccountDriverDependentModule is BaseModule {
    // slither-disable-next-line dead-code
    function _repoSubAccountDriverModule() internal view returns (IRepoSubAccountDriverModule) {
        address module = _moduleAddress(REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT);
        require(Address.isContract(module), "RepoSubAccountDriver module not deployed");
        return IRepoSubAccountDriverModule(module);
    }
}

interface IRepoSubAccountDriverModule {
    function repoSubAccountDriver() external view returns (RepoSubAccountDriver);
}

contract RepoSubAccountDriverModule is
    IRepoSubAccountDriverModule,
    RepoSubAccountDriverDependentModule,
    CallerDependentModule,
    RepoDriverDependentModule,
    DriverModule(4)
{
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin);
    }

    constructor(DripsDeployer dripsDeployer_, address proxyAdmin_)
        BaseModule(dripsDeployer_, REPO_SUB_ACCOUNT_DRIVER_MODULE_SALT)
    {
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(RepoSubAccountDriver).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_repoDriverModule().repoDriver(), _callerModule().caller(), driverId);
    }

    function repoSubAccountDriver() public view override returns (RepoSubAccountDriver) {
        return RepoSubAccountDriver(proxy());
    }
}

bytes32 constant REPO_DEADLINE_DRIVER_MODULE_SALT = "RepoDeadlineDriver";

function repoDeadlineDriverModule(DripsDeployer dripsDeployer, address proxyAdmin)
    pure
    returns (Module memory)
{
    bytes memory args = abi.encode(dripsDeployer, proxyAdmin);
    return Module({
        salt: REPO_DEADLINE_DRIVER_MODULE_SALT,
        amount: 0,
        initCode: abi.encodePacked(type(RepoDeadlineDriverModule).creationCode, args)
    });
}

abstract contract RepoDeadlineDriverDependentModule is BaseModule {
    // slither-disable-next-line dead-code
    function _repoDeadlineDriverModule() internal view returns (IRepoDeadlineDriverModule) {
        address module = _moduleAddress(REPO_DEADLINE_DRIVER_MODULE_SALT);
        require(Address.isContract(module), "RepoDeadlineDriver module not deployed");
        return IRepoDeadlineDriverModule(module);
    }
}

interface IRepoDeadlineDriverModule {
    function repoDeadlineDriver() external view returns (RepoDeadlineDriver);
}

contract RepoDeadlineDriverModule is
    IRepoDeadlineDriverModule,
    RepoDeadlineDriverDependentModule,
    RepoDriverDependentModule,
    DriverModule(5)
{
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin);
    }

    constructor(DripsDeployer dripsDeployer_, address proxyAdmin_)
        BaseModule(dripsDeployer_, REPO_DEADLINE_DRIVER_MODULE_SALT)
    {
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(RepoDeadlineDriver).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_repoDriverModule().repoDriver(), driverId);
    }

    function repoDeadlineDriver() public view override returns (RepoDeadlineDriver) {
        return RepoDeadlineDriver(proxy());
    }
}

bytes32 constant GIVERS_REGISTRY_MODULE_SALT = "GiversRegistry";

function giversRegistryModule(
    DripsDeployer dripsDeployer,
    address proxyAdmin,
    IWrappedNativeToken wrappedNativeToken
) pure returns (Module memory) {
    bytes memory args = abi.encode(dripsDeployer, proxyAdmin, wrappedNativeToken);
    return Module({
        salt: GIVERS_REGISTRY_MODULE_SALT,
        amount: 0,
        initCode: abi.encodePacked(type(GiversRegistryModule).creationCode, args)
    });
}

abstract contract GiversRegistryDependentModule is BaseModule {
    // slither-disable-next-line dead-code
    function _giversRegistryModule() internal view returns (IGiversRegistryModule) {
        address module = _moduleAddress(GIVERS_REGISTRY_MODULE_SALT);
        require(Address.isContract(module), "GiversRegistry module not deployed");
        return IGiversRegistryModule(module);
    }
}

interface IGiversRegistryModule {
    function giversRegistry() external view returns (GiversRegistry);
}

contract GiversRegistryModule is
    IGiversRegistryModule,
    GiversRegistryDependentModule,
    AddressDriverDependentModule,
    ProxyDeployerModule
{
    IWrappedNativeToken public immutable wrappedNativeToken;

    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin, wrappedNativeToken);
    }

    constructor(
        DripsDeployer dripsDeployer_,
        address proxyAdmin_,
        IWrappedNativeToken wrappedNativeToken_
    ) BaseModule(dripsDeployer_, GIVERS_REGISTRY_MODULE_SALT) {
        wrappedNativeToken = wrappedNativeToken_;
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(GiversRegistry).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_addressDriverModule().addressDriver(), wrappedNativeToken);
    }

    function giversRegistry() public view override returns (GiversRegistry) {
        return GiversRegistry(proxy());
    }
}

bytes32 constant NATIVE_TOKEN_UNWRAPPER_MODULE_SALT = "NativeTokenUnwrapper";

function nativeTokenUnwrapperModule(
    DripsDeployer dripsDeployer,
    IWrappedNativeToken wrappedNativeToken
) pure returns (Module memory) {
    bytes memory args = abi.encode(dripsDeployer, wrappedNativeToken);
    return Module({
        salt: NATIVE_TOKEN_UNWRAPPER_MODULE_SALT,
        amount: 0,
        initCode: abi.encodePacked(type(NativeTokenUnwrapperModule).creationCode, args)
    });
}

abstract contract NativeTokenUnwrapperDependentModule is BaseModule {
    function _nativeTokenUnwrapperModule() internal view returns (INativeTokenUnwrapperModule) {
        address module = _moduleAddress(NATIVE_TOKEN_UNWRAPPER_MODULE_SALT);
        require(Address.isContract(module), "NativeTokenUnwrapper module not deployed");
        return INativeTokenUnwrapperModule(module);
    }
}

interface INativeTokenUnwrapperModule {
    function nativeTokenUnrapper() external view returns (NativeTokenUnwrapper);
}

contract NativeTokenUnwrapperModule is
    INativeTokenUnwrapperModule,
    ContractDeployerModule,
    NativeTokenUnwrapperDependentModule
{
    IWrappedNativeToken public immutable wrappedNativeToken;

    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, wrappedNativeToken);
    }

    constructor(DripsDeployer dripsDeployer_, IWrappedNativeToken wrappedNativeToken_)
        BaseModule(dripsDeployer_, NATIVE_TOKEN_UNWRAPPER_MODULE_SALT)
    {
        wrappedNativeToken = wrappedNativeToken_;
        // slither-disable-next-line too-many-digits
        _deployContract(type(NativeTokenUnwrapper).creationCode);
    }

    function deploymentArgs() public view override returns (bytes memory) {
        return abi.encode(wrappedNativeToken);
    }

    function nativeTokenUnrapper() public view override returns (NativeTokenUnwrapper) {
        return NativeTokenUnwrapper(payable(deployment()));
    }
}

/// @notice Deploys contracts using CREATE3.
/// Each deployer has its own namespace for deployed addresses.
library Create3Factory {
    /// @notice The CREATE3 factory address.
    /// It's always the same, see `deploy_create3_factory` in the deployment script.
    ICreate3Factory private constant _CREATE3_FACTORY =
        ICreate3Factory(0x6aA3D87e99286946161dCA02B97C5806fC5eD46F);

    /// @notice Deploys a contract using CREATE3.
    /// @param amount The amount to pass into the deployed contract's constructor.
    /// @param salt The deployer-specific salt for determining the deployed contract's address.
    /// @param creationCode The creation code of the contract to deploy.
    function deploy(uint256 amount, bytes32 salt, bytes memory creationCode) internal {
        // slither-disable-next-line unused-return
        _CREATE3_FACTORY.deploy{value: amount}(salt, creationCode);
    }

    /// @notice Predicts the address of a contract deployed by this contract.
    /// @param salt The deployer-specific salt for determining the deployed contract's address.
    /// @return deployed The address of the contract that will be deployed.
    function getDeployed(bytes32 salt) internal view returns (address deployed) {
        return _CREATE3_FACTORY.getDeployed(address(this), salt);
    }
}

/// @title Factory for deploying contracts to deterministic addresses via CREATE3.
/// @author zefram.eth, taken from https://github.com/ZeframLou/create3-factory.
/// @notice Enables deploying contracts using CREATE3.
/// Each deployer (`msg.sender`) has its own namespace for deployed addresses.
interface ICreate3Factory {
    /// @notice Deploys a contract using CREATE3.
    /// @dev The provided salt is hashed together with msg.sender to generate the final salt.
    /// @param salt The deployer-specific salt for determining the deployed contract's address.
    /// @param creationCode The creation code of the contract to deploy.
    /// @return deployed The address of the deployed contract.
    function deploy(bytes32 salt, bytes memory creationCode)
        external
        payable
        returns (address deployed);

    /// @notice Predicts the address of a deployed contract.
    /// @dev The provided salt is hashed together
    /// with the deployer address to generate the final salt.
    /// @param deployer The deployer account that will call `deploy()`.
    /// @param salt The deployer-specific salt for determining the deployed contract's address.
    /// @return deployed The address of the contract that will be deployed.
    function getDeployed(address deployer, bytes32 salt) external view returns (address deployed);
}
