// SPDX-License-Identifier: MIT
pragma solidity ^0.7.5;

/// Token vesting contract.
/// Adapted from Melonport AG <team@melonport.com>

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract VestingToken {
    using SafeMath for uint256;

    ERC20 public token; // Radicle ERC20 contract
    address public owner; // deployer; can interrupt vesting

    bool public interrupted; // whether vesting is still possible
    bool public isVestingStarted; // whether vesting period has begun
    uint256 public totalVestingAmount; // quantity of vested token in total
    uint256 public vestingStartTime; // timestamp when vesting is set
    uint256 public vestingPeriod; // total vesting period in seconds
    address public beneficiary; // address of the beneficiary
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

    modifier vestingStarted() {
        require(isVestingStarted, "Vesting must be started");
        _;
    }

    /// @param _token Address of token being vested
    constructor(address _token, address _owner) {
        token = ERC20(_token);
        owner = _owner;
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

    /// @notice Grant vesting tokens to the beneficiary.
    ///
    /// @param ofBeneficiary Address of beneficiary
    /// @param ofTokenAmount Amount of tokens
    /// @param ofVestingPeriod Vesting period in seconds from vestingStartTime
    function grantTokens(
        address ofBeneficiary,
        uint256 ofTokenAmount,
        uint256 ofVestingPeriod
    ) external onlyOwner notInterrupted {
        require(!isVestingStarted, "VestingToken::grantTokens: vesting already started");
        require(ofTokenAmount > 0, "VestingToken::grantTokens: amount must be positive");
        require(
            token.transferFrom(msg.sender, address(this), ofTokenAmount),
            "VestingToken::grantTokens: token deposit failed"
        );

        isVestingStarted = true;
        vestingStartTime = block.timestamp;
        totalVestingAmount = ofTokenAmount;
        vestingPeriod = ofVestingPeriod;
        beneficiary = ofBeneficiary;
    }

    /// @notice Withdraw vested tokens
    function withdrawVested() external onlyBeneficiary vestingStarted notInterrupted {
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
    function terminateVesting() external onlyOwner vestingStarted notInterrupted {
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
