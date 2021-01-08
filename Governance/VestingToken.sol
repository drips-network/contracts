// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;

/// Token vesting contract.
/// Adapted from Melonport AG <team@melonport.com>

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VestingToken {
    using SafeMath for uint256;

    ERC20 public immutable token; // Radicle ERC20 contract

    address public immutable owner; // deployer; can interrupt vesting
    uint256 public immutable totalVestingAmount; // quantity of vested token in total
    uint256 public immutable vestingStartTime; // timestamp when vesting is set
    uint256 public immutable vestingPeriod; // total vesting period in seconds
    address public immutable beneficiary; // address of the beneficiary

    bool public interrupted; // whether vesting is still possible
    uint256 public withdrawn; // quantity of token withdrawn so far

    modifier notInterrupted() {
        require(!interrupted, "The contract has been interrupted");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can do this");
        _;
    }

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "Only beneficiary can do this");
        _;
    }

    /// @notice Create a vesting allocation of tokens.
    ///
    /// @param _token Address of token being vested
    /// @param _beneficiary Address of beneficiary
    /// @param _amount Amount of tokens
    /// @param _vestingPeriod Vesting period in seconds from vestingStartTime
    /// @param _vestingStartTime Vesting start time in seconds since Epoch
    constructor(
        address _token,
        address _owner,
        address _beneficiary,
        uint256 _amount,
        uint256 _vestingStartTime,
        uint256 _vestingPeriod
    ) {
        require(_vestingStartTime < block.timestamp, "Vesting start time must be in the past");
        require(_vestingPeriod > 0, "Vesting period must be positive");
        require(_amount > 0, "VestingToken::constructor: amount must be positive");
        ERC20 erc20 = ERC20(_token);
        require(
            erc20.transferFrom(msg.sender, address(this), _amount),
            "VestingToken::constructor: token deposit failed"
        );

        token = erc20;
        owner = _owner;
        totalVestingAmount = _amount;
        beneficiary = _beneficiary;
        vestingStartTime = _vestingStartTime;
        vestingPeriod = _vestingPeriod;
    }

    /// @notice Returns the token amount that is currently withdrawable
    /// @return withdrawable Quantity of withdrawable Radicle asset
    function withdrawableBalance() public view returns (uint256 withdrawable) {
        uint256 timePassed = block.timestamp.sub(vestingStartTime);

        if (timePassed < vestingPeriod) {
            uint256 vested = totalVestingAmount.mul(timePassed) / vestingPeriod;
            withdrawable = vested.sub(withdrawn);
        } else {
            withdrawable = totalVestingAmount.sub(withdrawn);
        }
    }

    /// @notice Withdraw vested tokens
    function withdrawVested() external onlyBeneficiary notInterrupted {
        uint256 withdrawable = withdrawableBalance();

        withdrawn = withdrawn.add(withdrawable);

        require(
            token.transfer(beneficiary, withdrawable),
            "VestingToken::withdrawVested: transfer to beneficiary failed"
        );
    }

    /// @notice Force withdrawal of vested tokens to beneficiary
    /// @notice Send remainder back to owner
    /// @notice Prevent further vesting
    function terminateVesting() external onlyOwner notInterrupted {
        interrupted = true;

        uint256 remainingVested = withdrawableBalance();
        uint256 totalToBeVested = withdrawn.add(remainingVested);
        uint256 remainingUnvested = totalVestingAmount.sub(totalToBeVested);

        withdrawn = totalVestingAmount;

        require(
            token.transfer(beneficiary, remainingVested),
            "VestingToken::terminateVesting: transfer to beneficiary failed"
        );
        require(
            token.transfer(owner, remainingUnvested),
            "VestingToken::terminateVesting: transfer to owner failed"
        );
    }
}
