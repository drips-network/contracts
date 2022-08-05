// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.15;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice The reserve interface as seen by the users.
interface IReserve {
    /// @notice Deposits funds into the reserve.
    /// The reserve will `transferFrom` `amt` tokens from the `from` address.
    /// @param token The used token.
    /// @param from The address from which funds are deposited.
    /// @param amt The deposited amount.
    function deposit(
        IERC20 token,
        address from,
        uint256 amt
    ) external;

    /// @notice Withdraws funds from the reserve.
    /// The reserve will transfer `amt` tokens to the `to` address.
    /// Only funds previously deposited can be withdrawn.
    /// @param token The used token.
    /// @param to The address to which funds are withdrawn.
    /// @param amt The withdrawn amount.
    function withdraw(
        IERC20 token,
        address to,
        uint256 amt
    ) external;
}

/// @notice The reserve plugin interface required by the reserve.
interface IReservePlugin {
    /// @notice Called by the reserve when it starts using the plugin,
    /// immediately after transferring to the plugin all the deposited funds.
    /// This initial transfer won't trigger the regular call to `afterDeposition`.
    /// @param token The used token.
    /// @param amt The amount which has been transferred for deposition.
    function afterStart(IERC20 token, uint256 amt) external;

    /// @notice Called by the reserve immediately after
    /// transferring funds to the plugin for deposition.
    /// @param token The used token.
    /// @param amt The amount which has been transferred for deposition.
    function afterDeposition(IERC20 token, uint256 amt) external;

    /// @notice Called by the reserve right before transferring funds for withdrawal.
    /// The reserve will `transferFrom` the tokens from the plugin address.
    /// The reserve can always withdraw everything that has been ever deposited, but never more.
    /// @param token The used token.
    /// @param amt The amount which will be transferred.
    function beforeWithdrawal(IERC20 token, uint256 amt) external;

    /// @notice Called by the reserve when it stops using the plugin,
    /// right before transferring from the plugin all the deposited funds.
    /// The reserve will `transferFrom` the tokens from the plugin address.
    /// This final transfer won't trigger the regular call to `beforeWithdrawal`.
    /// @param token The used token.
    /// @param amt The amount which will be transferred.
    function beforeEnd(IERC20 token, uint256 amt) external;
}

/// @notice The ERC-20 tokens reserve contract.
/// The registered users can deposit and withdraw funds.
/// The reserve by default doesn't do anything with the tokens,
/// but for each ERC-20 address a plugin can be registered for tokens storage.
contract Reserve is IReserve, Ownable {
    using SafeERC20 for IERC20;
    /// @notice The dummy plugin address meaning that no plugin is being used.
    IReservePlugin public constant NO_PLUGIN = IReservePlugin(address(0));

    /// @notice A set of addresses considered users.
    /// The value is `true` if an address is a user, `false` otherwise.
    mapping(address => bool) public isUser;
    /// @notice How many tokens are deposited for each token address.
    mapping(IERC20 => uint256) public deposited;
    /// @notice The reserved plugins for each token address.
    mapping(IERC20 => IReservePlugin) public plugins;

    /// @notice Emitted when a plugin is set.
    /// @param owner The address which called the function.
    /// @param token The token for which plugin has been set.
    /// @param oldPlugin The old plugin address. `NO_PLUGIN` if no plugin was being used.
    /// @param newPlugin The new plugin address. `NO_PLUGIN` if no plugin will be used.
    /// @param amt The amount which has been withdrawn
    /// from the old plugin and deposited into the new one.
    event PluginSet(
        address owner,
        IERC20 indexed token,
        IReservePlugin indexed oldPlugin,
        IReservePlugin indexed newPlugin,
        uint256 amt
    );

    /// @notice Emitted when funds are deposited.
    /// @param user The address which called the function.
    /// @param token The used token.
    /// @param from The address from which tokens have been transferred.
    /// @param amt The amount which has been deposited.
    event Deposited(address user, IERC20 indexed token, address indexed from, uint256 amt);

    /// @notice Emitted when funds are withdrawn.
    /// @param user The address which called the function.
    /// @param token The used token.
    /// @param to The address to which tokens have been transferred.
    /// @param amt The amount which has been withdrawn.
    event Withdrawn(address user, IERC20 indexed token, address indexed to, uint256 amt);

    /// @notice Emitted when funds are force withdrawn.
    /// @param owner The address which called the function.
    /// @param token The used token.
    /// @param plugin The address of the plugin from which funds have been withdrawn or
    /// `NO_PLUGIN` if from the reserve itself.
    /// @param to The address to which tokens have been transferred.
    /// @param amt The amount which has been withdrawn.
    event ForceWithdrawn(
        address owner,
        IERC20 indexed token,
        IReservePlugin indexed plugin,
        address indexed to,
        uint256 amt
    );

    /// @notice Emitted when an address is registered as a user.
    /// @param owner The address which called the function.
    /// @param user The registered user address.
    event UserAdded(address owner, address indexed user);

    /// @notice Emitted when an address is unregistered as a user.
    /// @param owner The address which called the function.
    /// @param user The unregistered user address.
    event UserRemoved(address owner, address indexed user);

    /// @param owner The initial owner address.
    constructor(address owner) {
        transferOwnership(owner);
    }

    modifier onlyUser() {
        require(isUser[msg.sender], "Reserve: caller is not the user");
        _;
    }

    /// @notice Sets a plugin for a given token.
    /// All future deposits and withdrawals of that token will be made using that plugin.
    /// All currently deposited tokens of that type will be withdrawn from the plugin previously
    /// set for that token and deposited into the new one.
    /// If no plugin has been set, funds are deposited from the reserve itself.
    /// If no plugin is being set, funds are deposited into the reserve itself.
    /// Callable only by the current owner.
    /// @param token The used token.
    /// @param newPlugin The new plugin address. `NO_PLUGIN` if no plugin should be used.
    function setPlugin(IERC20 token, IReservePlugin newPlugin) public onlyOwner {
        IReservePlugin oldPlugin = plugins[token];
        plugins[token] = newPlugin;
        uint256 amt = deposited[token];
        if (oldPlugin != NO_PLUGIN) oldPlugin.beforeEnd(token, amt);
        _transfer(token, _pluginAddr(oldPlugin), _pluginAddr(newPlugin), amt);
        if (newPlugin != NO_PLUGIN) newPlugin.afterStart(token, amt);
        emit PluginSet(msg.sender, token, oldPlugin, newPlugin, amt);
    }

    /// @notice Deposits funds into the reserve.
    /// The reserve will `transferFrom` `amt` tokens from the `from` address.
    /// Callable only by a current user.
    /// @param token The used token.
    /// @param from The address from which funds are deposited.
    /// @param amt The deposited amount.
    function deposit(
        IERC20 token,
        address from,
        uint256 amt
    ) public override onlyUser {
        IReservePlugin plugin = plugins[token];
        require(from != address(plugin) && from != address(this), "Reserve: deposition from self");
        deposited[token] += amt;
        _transfer(token, from, _pluginAddr(plugin), amt);
        if (plugin != NO_PLUGIN) plugin.afterDeposition(token, amt);
        emit Deposited(msg.sender, token, from, amt);
    }

    /// @notice Withdraws funds from the reserve.
    /// The reserve will transfer `amt` tokens to the `to` address.
    /// Only funds previously deposited can be withdrawn.
    /// Callable only by a current user.
    /// @param token The used token.
    /// @param to The address to which funds are withdrawn.
    /// @param amt The withdrawn amount.
    function withdraw(
        IERC20 token,
        address to,
        uint256 amt
    ) public override onlyUser {
        uint256 balance = deposited[token];
        require(balance >= amt, "Reserve: withdrawal over balance");
        deposited[token] = balance - amt;
        IReservePlugin plugin = plugins[token];
        if (plugin != NO_PLUGIN) plugin.beforeWithdrawal(token, amt);
        _transfer(token, _pluginAddr(plugin), to, amt);
        emit Withdrawn(msg.sender, token, to, amt);
    }

    /// @notice Withdraws funds from the reserve or a plugin.
    /// The reserve will transfer `amt` tokens to the `to` address.
    /// The function doesn't update the deposited amount counter.
    /// If used recklessly, it may cause a mismatch between the counter and the actual balance
    /// making valid future calls to `withdraw` or `setPlugin` fail due to lack of funds.
    /// Callable only by the current owner.
    /// @param token The used token.
    /// @param plugin The plugin to withdraw from.
    /// It doesn't need to be registered as a plugin for `token`.
    /// Pass `NO_PLUGIN` to withdraw directly from the reserve balance.
    /// @param to The address to which funds are withdrawn.
    /// @param amt The withdrawn amount.
    function forceWithdraw(
        IERC20 token,
        IReservePlugin plugin,
        address to,
        uint256 amt
    ) public onlyOwner {
        if (plugin != NO_PLUGIN) plugin.beforeWithdrawal(token, amt);
        _transfer(token, _pluginAddr(plugin), to, amt);
        emit ForceWithdrawn(msg.sender, token, plugin, to, amt);
    }

    /// @notice Sets the deposited amount counter for a token without transferring any funds.
    /// If used recklessly, it may cause a mismatch between the counter and the actual balance
    /// making valid future calls to `withdraw` or `setPlugin` fail due to lack of funds.
    /// It may also make the counter lower than what users expect it to be again making
    /// valid future calls to `withdraw` fail.
    /// Callable only by the current owner.
    /// @param token The used token.
    /// @param amt The new deposited amount counter value.
    function setDeposited(IERC20 token, uint256 amt) public onlyOwner {
        deposited[token] = amt;
    }

    /// @notice Adds a new user.
    /// @param user The new user address.
    function addUser(address user) public onlyOwner {
        isUser[user] = true;
        emit UserAdded(msg.sender, user);
    }

    /// @notice Removes an existing user.
    /// @param user The removed user address.
    function removeUser(address user) public onlyOwner {
        isUser[user] = false;
        emit UserRemoved(msg.sender, user);
    }

    function _pluginAddr(IReservePlugin plugin) internal view returns (address) {
        return plugin == NO_PLUGIN ? address(this) : address(plugin);
    }

    function _transfer(
        IERC20 token,
        address from,
        address to,
        uint256 amt
    ) internal {
        if (from == address(this)) token.safeTransfer(to, amt);
        else token.safeTransferFrom(from, to, amt);
    }
}
