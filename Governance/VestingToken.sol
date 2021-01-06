pragma solidity ^0.7.5;

/// @title Math operations with safety checks
/// @author Melonport AG <team@melonport.com>
/// @notice From https://github.com/status-im/status-network-token/blob/master/contracts/safeMath.sol

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Vesting {
    using SafeMath for uint256;

    // FIELDS

    // Constructor fields
    ERC20 public MELON_CONTRACT; // MLN as ERC20 contract
    address public owner; // deployer; can interrupt vesting
    // Methods fields
    bool public interrupted; // whether vesting is still possible
    bool public isVestingStarted; // whether vesting period has begun
    uint256 public totalVestingAmount; // quantity of vested Melon in total
    uint256 public vestingStartTime; // timestamp when vesting is set
    uint256 public vestingPeriod; // total vesting period in seconds
    address public beneficiary; // address of the beneficiary
    uint256 public withdrawn; // quantity of Melon withdrawn so far

    // MODIFIERS

    modifier not_interrupted() {
        require(!interrupted, "The contract has been interrupted");
        _;
    }

    modifier only_owner() {
        require(msg.sender == owner, "Only owner can do this");
        _;
    }

    modifier only_beneficiary() {
        require(msg.sender == beneficiary, "Only beneficiary can do this");
        _;
    }

    modifier vesting_not_started() {
        require(!isVestingStarted, "Vesting cannot be started");
        _;
    }

    modifier vesting_started() {
        require(isVestingStarted, "Vesting must be started");
        _;
    }

    /// @notice Calculates the quantity of Melon asset that's currently withdrawable
    /// @return withdrawable Quantity of withdrawable Melon asset
    function calculateWithdrawable() public view returns (uint256 withdrawable) {
        uint256 timePassed = block.timestamp.sub(vestingStartTime);

        if (timePassed < vestingPeriod) {
            uint256 vested = totalVestingAmount.mul(timePassed) / vestingPeriod;
            withdrawable = vested.sub(withdrawn);
        } else {
            withdrawable = totalVestingAmount.sub(withdrawn);
        }
    }

    /// @param ofMelonAsset Address of Melon asset
    constructor(address ofMelonAsset, address ofOwner) {
        MELON_CONTRACT = ERC20(ofMelonAsset);
        owner = ofOwner;
    }

    /// @param ofBeneficiary Address of beneficiary
    /// @param ofMelonQuantity Address of MLN asset
    /// @param ofVestingPeriod Vesting period in seconds from vestingStartTime
    function setVesting(
        address ofBeneficiary,
        uint256 ofMelonQuantity,
        uint256 ofVestingPeriod
    ) external only_owner not_interrupted vesting_not_started {
        require(ofMelonQuantity > 0, "Must vest some MLN");
        require(
            MELON_CONTRACT.transferFrom(msg.sender, address(this), ofMelonQuantity),
            "MLN deposit failed"
        );
        isVestingStarted = true;
        vestingStartTime = block.timestamp;
        totalVestingAmount = ofMelonQuantity;
        vestingPeriod = ofVestingPeriod;
        beneficiary = ofBeneficiary;
    }

    /// @notice Withdraw
    function withdraw() external only_beneficiary vesting_started not_interrupted {
        uint256 withdrawable = calculateWithdrawable();
        withdrawn = withdrawn.add(withdrawable);
        require(
            MELON_CONTRACT.transfer(beneficiary, withdrawable),
            "Transfer to beneficiary failed"
        );
    }

    /// @notice Withdraw vested tokens to beneficiary
    /// @notice Send remainder back to owner
    /// @notice Prevent further vesting
    function forceWithdrawalAndInterrupt() external only_owner vesting_started not_interrupted {
        interrupted = true;
        uint256 remainingVested = calculateWithdrawable();
        uint256 totalToBeVested = withdrawn.add(remainingVested);
        uint256 remainingUnvested = totalVestingAmount.sub(totalToBeVested);
        withdrawn = totalVestingAmount;
        require(
            MELON_CONTRACT.transfer(beneficiary, remainingVested),
            "Transfer to beneficiary failed"
        );
        require(MELON_CONTRACT.transfer(owner, remainingUnvested), "Transfer to owner failed");
    }
}
