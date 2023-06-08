// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {AddressDriver} from "./AddressDriver.sol";
import {Caller} from "./Caller.sol";
import {Drips} from "./Drips.sol";
import {ImmutableSplitsDriver} from "./ImmutableSplitsDriver.sol";
import {Managed, ManagedProxy} from "./Managed.sol";
import {NFTDriver} from "./NFTDriver.sol";
import {OperatorInterface, RepoDriver} from "./RepoDriver.sol";
import {Ownable2Step} from "openzeppelin-contracts/access/Ownable2Step.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {Create2} from "openzeppelin-contracts/utils/Create2.sol";

struct Module {
    bytes32 salt;
    uint256 amount;
    bytes initCode;
}

contract DripsDeployer is Ownable2Step {
    // slither-disable-next-line naming-convention
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
            Create3.deploy(module.amount, module.salt, module.initCode);
        }
    }

    function moduleSalts() public view returns (bytes32[] memory) {
        return _moduleSalts;
    }

    function moduleAddress(bytes32 salt) public view returns (address addr) {
        return Create3.computeAddress(salt);
    }
}

abstract contract BaseModule {
    address public immutable dripsDeployer;
    bytes32 public immutable moduleSalt;

    constructor(address dripsDeployer_, bytes32 moduleSalt_) {
        require(
            address(this) == Create3.computeAddress(moduleSalt_, dripsDeployer_),
            "Invalid module deployment salt"
        );
        dripsDeployer = dripsDeployer_;
        moduleSalt = moduleSalt_;
    }

    function args() public view virtual returns (bytes memory);

    function _moduleAddress(bytes32 salt) internal view returns (address addr) {
        return Create3.computeAddress(salt, dripsDeployer);
    }

    modifier onlyModule(bytes32 salt) {
        require(msg.sender == _moduleAddress(bytes32(salt)));
        _;
    }
}

abstract contract ContractDeployerModule is BaseModule {
    bytes32 public immutable salt = "deployment";

    function deployment() public view returns (address) {
        return Create3.computeAddress(salt);
    }

    function deploymentArgs() public view virtual returns (bytes memory);

    function _deployContract(bytes memory creationCode) internal {
        Create3.deploy(0, salt, abi.encodePacked(creationCode, deploymentArgs()));
    }
}

abstract contract ProxyDeployerModule is BaseModule {
    bytes32 public immutable proxySalt = "proxy";
    address public proxyAdmin;
    address public logic;

    function proxy() public view returns (address) {
        return Create3.computeAddress(proxySalt);
    }

    function proxyArgs() public view returns (bytes memory) {
        return abi.encode(logic, proxyAdmin);
    }

    function logicArgs() public view virtual returns (bytes memory);

    // slither-disable-next-line reentrancy-benign
    function _deployProxy(address proxyAdmin_, bytes memory logicCreationCode) internal {
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
        // slither-disable-next-line too-many-digits
        bytes memory proxyInitCode = abi.encodePacked(type(ManagedProxy).creationCode, proxyArgs());
        Create3.deploy(0, proxySalt, proxyInitCode);
    }
}

abstract contract DripsDependentModule is BaseModule {
    // slither-disable-next-line naming-convention
    bytes32 internal immutable _dripsModuleSalt = "Drips";

    function _dripsModule() internal view returns (DripsModule) {
        address module = _moduleAddress(_dripsModuleSalt);
        require(Address.isContract(module), "Drips module not deployed");
        return DripsModule(module);
    }
}

contract DripsModule is DripsDependentModule, ProxyDeployerModule {
    uint32 public immutable dripsCycleSecs;
    uint32 public immutable claimableDriverIds = 100;

    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, dripsCycleSecs, proxyAdmin);
    }

    constructor(address dripsDeployer_, uint32 dripsCycleSecs_, address proxyAdmin_)
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

    function drips() public view returns (Drips) {
        return Drips(proxy());
    }

    function claimDriverId(bytes32 moduleSalt_, uint32 driverId, address driverAddr)
        public
        onlyModule(moduleSalt_)
    {
        drips().updateDriverAddress(driverId, driverAddr);
    }
}

abstract contract CallerDependentModule is BaseModule {
    // slither-disable-next-line naming-convention
    bytes32 internal immutable _callerModuleSalt = "Caller";

    function _callerModule() internal view returns (CallerModule) {
        address module = _moduleAddress(_callerModuleSalt);
        require(Address.isContract(module), "Caller module not deployed");
        return CallerModule(module);
    }
}

contract CallerModule is ContractDeployerModule, CallerDependentModule {
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer);
    }

    constructor(address dripsDeployer_) BaseModule(dripsDeployer_, _callerModuleSalt) {
        // slither-disable-next-line too-many-digits
        _deployContract(type(Caller).creationCode);
    }

    function deploymentArgs() public pure override returns (bytes memory) {
        return abi.encode();
    }

    function caller() public view returns (Caller) {
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

contract AddressDriverModule is CallerDependentModule, DriverModule(0) {
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin);
    }

    constructor(address dripsDeployer_, address proxyAdmin_)
        BaseModule(dripsDeployer_, "AddressDriver")
    {
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(AddressDriver).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_dripsModule().drips(), _callerModule().caller(), driverId);
    }

    function addressDriver() public view returns (AddressDriver) {
        return AddressDriver(proxy());
    }
}

contract NFTDriverModule is CallerDependentModule, DriverModule(1) {
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin);
    }

    constructor(address dripsDeployer_, address proxyAdmin_)
        BaseModule(dripsDeployer_, "NFTDriver")
    {
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(NFTDriver).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_dripsModule().drips(), _callerModule().caller(), driverId);
    }

    function nftDriver() public view returns (NFTDriver) {
        return NFTDriver(proxy());
    }
}

contract ImmutableSplitsDriverModule is DriverModule(2) {
    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin);
    }

    constructor(address dripsDeployer_, address proxyAdmin_)
        BaseModule(dripsDeployer_, "ImmutableSplitsDriver")
    {
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(ImmutableSplitsDriver).creationCode);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_dripsModule().drips(), driverId);
    }

    function immutableSplitsDriver() public view returns (ImmutableSplitsDriver) {
        return ImmutableSplitsDriver(proxy());
    }
}

contract RepoDriverModule is CallerDependentModule, DriverModule(3) {
    OperatorInterface public immutable operator;
    bytes32 public immutable jobId;
    uint96 public immutable defaultFee;

    function args() public view override returns (bytes memory) {
        return abi.encode(dripsDeployer, proxyAdmin, operator, jobId, defaultFee);
    }

    constructor(
        address dripsDeployer_,
        address proxyAdmin_,
        OperatorInterface operator_,
        bytes32 jobId_,
        uint96 defaultFee_
    ) BaseModule(dripsDeployer_, "RepoDriver") {
        operator = operator_;
        jobId = jobId_;
        defaultFee = defaultFee_;
        // slither-disable-next-line too-many-digits
        _deployProxy(proxyAdmin_, type(RepoDriver).creationCode);
        repoDriver().initializeAnyApiOperator(operator, jobId, defaultFee);
    }

    function logicArgs() public view override returns (bytes memory) {
        return abi.encode(_dripsModule().drips(), _callerModule().caller(), driverId);
    }

    function repoDriver() public view returns (RepoDriver) {
        return RepoDriver(proxy());
    }
}

/// @notice Creates a contract under a deterministic addresses
/// derived only from the deployer's address and the salt.
/// The deployment is a two-step process, first, a proxy is deployed using CREATE2 with
/// the given salt, and then it's called with the bytecode of the deployed contract,
/// the proxy uses it to deploy the contract using regular CREATE.
/// If the deployed contract's constructor reverts, the proxy also reverts.
/// If the proxy call has a non-zero value, it's passed to the deployed contract's constructor.
/// Based on the bytecode from https://github.com/0xsequence/create3.
library Create3 {
    using Address for address;

    //////////////////////////// PROXY CREATION CODE ///////////////////////////
    // Opcode     | Opcode name      | Stack values after executing
    // Store the proxy bytecode in memory
    // 0x67XX..XX | PUSH8 bytecode   | bytecode
    // 0x3d       | RETURNDATASIZE   | 0 bytecode
    // 0x52       | MSTORE           |
    // Return the proxy bytecode
    // 0x6008     | PUSH1 8          | 8
    // 0x6018     | PUSH1 24         | 24 8
    // 0xf3       | RETURN           |

    ////////////////////////////// PROXY BYTECODE //////////////////////////////
    // Opcode     | Opcode name      | Stack values after executing
    // Copy the calldata to memory
    // 0x36       | CALLDATASIZE     | size
    // 0x3d       | RETURNDATASIZE   | 0 size
    // 0x3d       | RETURNDATASIZE   | 0 0 size
    // 0x37       | CALLDATACOPY     |
    // Create the contract
    // 0x36       | CALLDATASIZE     | size
    // 0x3d       | RETURNDATASIZE   | 0 size
    // 0x34       | CALLVALUE        | value 0 size
    // 0xf0       | CREATE           | newContract

    bytes private constant PROXY_CREATION_CODE =
    // Proxy creation code up to `PUSH8`
        hex"67"
        // Proxy bytecode
        hex"363d3d37363d34f0"
        // Proxy creation code after `PUSH8`
        hex"3d5260086018f3";

    /// @notice Deploys a contract under a deterministic address.
    /// @param amount The amount to pass into the deployed contract's constructor.
    /// @param salt The salt to use. It must have never been used by this contract.
    /// @param initCode The init code of the deployed contract.
    function deploy(uint256 amount, bytes32 salt, bytes memory initCode) internal {
        (address proxy, address addr) = _computeAddress(salt, address(this));
        require(!proxy.isContract(), "Salt already used");
        require(amount <= address(this).balance, "Balance too low");
        // slither-disable-next-line unused-return
        Create2.deploy(0, salt, PROXY_CREATION_CODE);
        bool success;
        // slither-disable-next-line low-level-calls
        (success,) = proxy.call{value: amount}(initCode);
        require(addr.isContract(), "Deployment failed");
    }

    /// @notice Computes the deterministic address of a contract deployed by this contract.
    /// The deployed contract doesn't need to be deployed yet, it's a hypothetical address.
    /// @param salt The salt used for deployment.
    /// @return addr The deployed contract's address.
    function computeAddress(bytes32 salt) internal view returns (address addr) {
        return computeAddress(salt, address(this));
    }

    /// @notice Computes the deterministic address of a contract deployed by a deployer.
    /// The contract doesn't need to be deployed yet, it's a hypothetical address.
    /// @param salt The salt used for deployment.
    /// @param deployer The address of the deployer of the proxy and the contract.
    /// @return addr The deployed contract's address.
    function computeAddress(bytes32 salt, address deployer) internal pure returns (address addr) {
        (, addr) = _computeAddress(salt, deployer);
    }

    /// @notice Computes the deterministic address of a proxy and a contract deployed by a deployer.
    /// The proxy and the contract don't need to be deployed yet, these are hypothetical addresses.
    /// @param salt The salt used for deployment.
    /// @param deployer The address of the deployer of the proxy and the contract.
    /// @return proxy The proxy's address.
    /// @return addr The deployed contract's address.
    function _computeAddress(bytes32 salt, address deployer)
        private
        pure
        returns (address proxy, address addr)
    {
        proxy = Create2.computeAddress(salt, keccak256(PROXY_CREATION_CODE), deployer);
        addr = address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy, hex"01")))));
    }
}
