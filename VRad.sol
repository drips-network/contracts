// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./Governance/RadicleToken.sol";

/// A token allocation of vRad.
///
/// @param vestingStart Vesting start time in seconds since Epoch.
/// @param vestingCliffDuration Vesting cliff duration.
/// @param vestingDuration Vesting total (including cliff) duration in seconds.
struct Allocation {
    uint256 vestingStart;
    uint256 vestingCliffDuration;
    uint256 vestingDuration;
}

/// The vRad token.
///
/// This contract implements a simple vesting token (vRad) that can be redeemed
/// for an equal amount of Radicle when the vesting period is over.
///
/// The general idea is the following:
///
/// 1. The contract is initialized with a "grantor" who has the right
///    to grant vRad to an address. The contract starts out with a zero
///    balance.
/// 2. The contract supply is expanded via `expandTokenSupply`. With this
///    method, the sender can transfer Radicle to mint an equal amount of vRad
///    into the contract's supply. The contract now holds an equal amount of
///    Radicle and vRad.
/// 3. When the grantor wants to grant tokens to an address, they call
///    `allocateTokens`. This simply transfers vRad from the contract
///    to the "grantee", and records the vesting rules for that allocation.
/// 4. The grantee can then call `getVestedAmount` at all times to check their
///    amount of vested tokens.
/// 5. When this amount is non-zero, the grantee can redeem vRad for Radicle, by
///    calling `redeemTokens` with an amount. As long as this amount isn't
///    greater than the vested amount, the contract supply is shrunk via
///    `shrinkTokenSupply`: the specified amount of vRad is burned, and an
///    equal amount of Radicle is transfered from the contract to the redeemer.
///
contract VRad is ERC20 {
    /// @dev The Radicle token.
    RadicleToken private immutable rad;

    /// Token allocations.
    mapping(address => Allocation) public allocations;

    /// The grantor of token allocations.
    address public grantor;

    /// Construct a new VRad token.
    ///
    /// @param _rad The address of the Radicle ERC20 contract.
    /// @param _grantor The initial account to grant all the tokens to.
    constructor(address _rad, address _grantor) ERC20("vRad", "vRAD") {
        rad = RadicleToken(_rad);
        grantor = _grantor;
    }

    /// Expand the supply of Radicle and vRad held by this contract equally,
    /// by transfering Radicle from the sender to the contract.
    function depositRadFrom(address sender, uint256 amount) public {
        // Transfer the Radicle.
        require(rad.transferFrom(sender, address(this), amount), "The transfer in should succeed");
        // Mint an equal amount of vRad.
        _mint(address(this), amount);
    }

    /// Transfer Radicle out of the contract, burning an equal amount of VRad.
    function withdrawRadTo(address payable receiver, uint256 amount) internal {
        // Transfer out an equal amount of Radicle from the contract to the receiver.
        require(rad.transfer(receiver, amount), "The transfer out should succeed");
        // Burn an amount of vRad from the sender.
        _burn(msg.sender, amount);
    }

    /// Grant vesting tokens to an address.
    function grantTokens(
        address grantee,
        uint256 amount,
        uint32 vestingStart,
        uint32 vestingCliffDuration,
        uint32 vestingDuration
    ) public {
        require(balanceOf(grantee) == 0, "Grantee must not already have an allocation");
        require(
            vestingDuration >= vestingCliffDuration,
            "Cliff must not be longer than total duration"
        );

        // Nb. It's okay for the vesting/cliff duration to be zero.

        _allocate(grantee, amount);

        allocations[grantee].vestingStart = vestingStart;
        allocations[grantee].vestingCliffDuration = vestingCliffDuration;
        allocations[grantee].vestingDuration = vestingDuration;
    }

    /// Increase the vesting token allocation of an address.
    function grantAdditionalTokens(address grantee, uint256 amount) public {
        require(balanceOf(grantee) > 0, "Grantee must already have an allocation");

        _allocate(grantee, amount);
    }

    /// Get the amount of vesting tokens for an address.
    function vestingBalanceOf(address grantee) public view returns (uint256) {
        return balanceOf(grantee);
    }

    /// Get the amount of currently vested tokens for an address.
    function vestedBalanceOf(address grantee) public view returns (uint256) {
        uint256 vestingAmount = balanceOf(grantee);

        if (vestingAmount == 0) {
            return 0;
        }

        Allocation memory alloc = allocations[grantee];
        uint256 elapsed = getTime() - alloc.vestingStart;

        if (elapsed < alloc.vestingCliffDuration) {
            return 0;
        }

        if (alloc.vestingDuration == 0) {
            return vestingAmount;
        }

        uint256 vestedAmount = (elapsed * vestingAmount) / alloc.vestingDuration;

        if (vestedAmount > vestingAmount) {
            vestedAmount = vestingAmount;
        }

        return vestedAmount;
    }

    /// Get the current time.
    function getTime() public view returns (uint256) {
        return block.timestamp;
    }

    /// Redeem vRad tokens for Radicle tokens.
    function redeemVestedTokens(address payable receiver, uint256 amount) public {
        require(amount > 0, "Redeem amount must be positive");
        require(vestedBalanceOf(msg.sender) >= amount, "Redeem amount should be vested");

        withdrawRadTo(receiver, amount);

        if (balanceOf(msg.sender) == 0) {
            delete allocations[msg.sender];
        }
    }

    /// Transfer the given amount of tokens from the contract to the grantee.
    function _allocate(address grantee, uint256 amount) internal {
        require(msg.sender == grantor, "Only the grantor can allocate tokens");
        require(grantee != address(0), "Grantee cannot be the zero address");
        require(amount <= balanceOf(address(this)), "Cannot allocate more than the allowance");

        // Make the actual transfer.
        _transfer(address(this), grantee, amount);
    }

    /// Transfer of vRad is only allowed by the grantor.
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        require(msg.sender == grantor, "Only the grantor can transfer vRad");

        _transfer(msg.sender, recipient, amount);

        return true;
    }
}
