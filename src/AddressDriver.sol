// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {
    DripsHistory,
    DripsHub,
    DripsReceiver,
    IERC20,
    SplitsReceiver,
    UserMetadata
} from "./DripsHub.sol";
import {Managed} from "./Managed.sol";
import {ERC2771Context} from "openzeppelin-contracts/metatx/ERC2771Context.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice A DripsHub driver implementing address-based user identification.
/// Each address can use `AddressDriver` to control a single user ID derived from that address.
/// No registration is required, an `AddressDriver`-based user ID for each address is know upfront.
contract AddressDriver is Managed, ERC2771Context {
    using SafeERC20 for IERC20;

    /// @notice The DripsHub address used by this driver.
    DripsHub public immutable dripsHub;
    /// @notice The driver ID which this driver uses when calling DripsHub.
    uint32 public immutable driverId;

    /// @param _dripsHub The drips hub to use.
    /// @param forwarder The ERC-2771 forwarder to trust. May be the zero address.
    /// @param _driverId The driver ID to use when calling DripsHub.
    constructor(DripsHub _dripsHub, address forwarder, uint32 _driverId)
        ERC2771Context(forwarder)
    {
        dripsHub = _dripsHub;
        driverId = _driverId;
    }

    /// @notice Calculates the user ID for an address
    /// @param userAddr The user address
    /// @return userId The user ID
    function calcUserId(address userAddr) public view returns (uint256 userId) {
        return (uint256(driverId) << 224) | uint160(userAddr);
    }

    /// @notice Calculates the user ID for the message sender
    /// @return userId The user ID
    function callerUserId() internal view returns (uint256 userId) {
        return calcUserId(_msgSender());
    }

    /// @notice Collects the user's received already split funds
    /// and transfers them out of the drips hub contract.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferrable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param transferTo The address to send collected funds to
    /// @return amt The collected amount
    function collect(IERC20 erc20, address transferTo) public whenNotPaused returns (uint128 amt) {
        amt = dripsHub.collect(callerUserId(), erc20);
        erc20.safeTransfer(transferTo, amt);
    }

    /// @notice Gives funds from the message sender to the receiver.
    /// The receiver can collect them immediately.
    /// Transfers the funds to be given from the message sender's wallet to the drips hub contract.
    /// @param receiver The receiver
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferrable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param amt The given amount
    function give(uint256 receiver, IERC20 erc20, uint128 amt) public whenNotPaused {
        _transferFromCaller(erc20, amt);
        dripsHub.give(callerUserId(), receiver, erc20, amt);
    }

    /// @notice Sets the message sender's drips configuration.
    /// Transfers funds between the message sender's wallet and the drips hub contract
    /// to fulfill the change of the drips balance.
    /// @param erc20 The used ERC-20 token.
    /// It must preserve amounts, so if some amount of tokens is transferred to
    /// an address, then later the same amount must be transferrable from that address.
    /// Tokens which rebase the holders' balances, collect taxes on transfers,
    /// or impose any restrictions on holding or transferring tokens are not supported.
    /// If you use such tokens in the protocol, they can get stuck or lost.
    /// @param currReceivers The list of the drips receivers set in the last drips update
    /// of the sender.
    /// If this is the first update, pass an empty array.
    /// @param balanceDelta The drips balance change to be applied.
    /// Positive to add funds to the drips balance, negative to remove them.
    /// @param newReceivers The list of the drips receivers of the sender to be set.
    /// Must be sorted by the receivers' addresses, deduplicated and without 0 amtPerSecs.
    /// @param maxEndTip1 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The first tip for finding the maximum end time when all drips stop due to funds
    /// running out after the balance is updated and the new receivers list is applied.
    /// Tips have no effect on the results of calling this function, except potentially saving gas.
    /// Tips are Unix timestamps used as the starting points for binary search for the time
    /// when funds run out in the range of timestamps from the current block's to `2^32`.
    /// Tips lower than the current timestamp are ignored.
    /// You can provide zero, one or two tips. The order of tips doesn't matter.
    /// Tips are the most effective when one of them is lower than or equal to
    /// the time when funds run out, and the other one is strictly larger than that time,
    /// the smaller the difference between such tips, the higher gas savings.
    /// The savings are the highest possible when one of the tips
    /// is equal to the time when funds run out and the other one is larger by 1.
    /// It's worth noting that the exact timestamp of the block in which this function is executed
    /// may affect correctness of the tips, especially if they're precise.
    /// Tips don't provide any benefits when balance is not enough to cover
    /// a single second of dripping or is enough to cover all drips until timestamp `2^32`.
    /// Even inaccurate tips can be useful, and providing a single tip
    /// or two tips that don't enclose the time when funds run out can still save some gas.
    /// Providing poor tips that don't reduce the number of binary search steps
    /// may cause slightly higher gas usage than not providing any tips.
    /// @param maxEndTip2 An optional parameter allowing gas optimization, pass `0` to ignore it.
    /// The second tip for finding the maximum end time, see `maxEndTip1` docs for more details.
    /// @param transferTo The address to send funds to in case of decreasing balance
    /// @return realBalanceDelta The actually applied drips balance change.
    function setDrips(
        IERC20 erc20,
        DripsReceiver[] calldata currReceivers,
        int128 balanceDelta,
        DripsReceiver[] calldata newReceivers,
        uint32 maxEndTip1,
        uint32 maxEndTip2,
        address transferTo
    ) public whenNotPaused returns (int128 realBalanceDelta) {
        if (balanceDelta > 0) {
            _transferFromCaller(erc20, uint128(balanceDelta));
        }
        realBalanceDelta = dripsHub.setDrips(
            callerUserId(), erc20, currReceivers, balanceDelta, newReceivers, maxEndTip1, maxEndTip2
        );
        if (realBalanceDelta < 0) {
            erc20.safeTransfer(transferTo, uint128(-realBalanceDelta));
        }
    }

    /// @notice Sets the message sender's splits configuration.
    /// @param receivers The list of the user's splits receivers to be set.
    /// Must be sorted by the splits receivers' addresses, deduplicated and without 0 weights.
    /// Each splits receiver will be getting `weight / TOTAL_SPLITS_WEIGHT`
    /// share of the funds collected by the user.
    function setSplits(SplitsReceiver[] calldata receivers) public whenNotPaused {
        dripsHub.setSplits(callerUserId(), receivers);
    }

    /// @notice Emits the user metadata for the message sender.
    /// The keys and the values are not standardized by the protocol, it's up to the user
    /// to establish and follow conventions to ensure compatibility with the consumers.
    /// @param userMetadata The list of user metadata.
    function emitUserMetadata(UserMetadata[] calldata userMetadata) public whenNotPaused {
        dripsHub.emitUserMetadata(callerUserId(), userMetadata);
    }

    function _transferFromCaller(IERC20 erc20, uint128 amt) internal {
        erc20.safeTransferFrom(_msgSender(), address(this), amt);
        // Approval is done only on the first usage of the ERC-20 token in DripsHub by the driver
        if (erc20.allowance(address(this), address(dripsHub)) == 0) {
            erc20.safeApprove(address(dripsHub), type(uint256).max);
        }
    }
}
