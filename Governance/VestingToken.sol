pragma solidity >=0.4.23;

/// @title Math operations with safety checks
/// @author Melonport AG <team@melonport.com>
/// @notice From https://github.com/status-im/status-network-token/blob/master/contracts/safeMath.sol

library safeMath {
  function mul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint a, uint b) internal returns (uint) {
    uint c = a / b;
    return c;
  }

  function sub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function add(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c >= a);
    return c;
  }

  function max64(uint64 a, uint64 b) internal constant returns (uint64) {
    return a >= b ? a : b;
  }

  function min64(uint64 a, uint64 b) internal constant returns (uint64) {
    return a < b ? a : b;
  }

  function max256(uint256 a, uint256 b) internal constant returns (uint256) {
    return a >= b ? a : b;
  }

  function min256(uint256 a, uint256 b) internal constant returns (uint256) {
    return a < b ? a : b;
  }
}

/// @title ERC20 Token Interface
/// @author Melonport AG <team@melonport.com>
/// @notice See https://github.com/ethereum/EIPs/issues/20
contract ERC20Interface {

    // EVENTS

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    // CONSTANT METHODS

    function totalSupply() constant returns (uint256 totalSupply) {}
    function balanceOf(address _owner) constant returns (uint256 balance) {}
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

    // NON-CONSTANT METHODS

    function transfer(address _to, uint256 _value) returns (bool success) {}
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}
    function approve(address _spender, uint256 _value) returns (bool success) {}
}

/// @title ERC20 Token
/// @author Melonport AG <team@melonport.com>
/// @notice Original taken from https://github.com/ethereum/EIPs/issues/20
/// @notice Checked against integer overflow
contract ERC20 is ERC20Interface {

    function transfer(address _to, uint256 _value) returns (bool success) {
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else { throw; }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { throw; }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        // See: https://github.com/ethereum/EIPs/issues/20#issuecomment-263555598
        if (_value > 0) {
            require(allowed[msg.sender][_spender] == 0);
        }
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    mapping (address => uint256) balances;

    mapping (address => mapping (address => uint256)) allowed;

    uint256 public totalSupply;

}


contract CouncilVesting {
    using safeMath for uint;

    // FIELDS

    // Constructor fields
    ERC20 public MELON_CONTRACT;   // MLN as ERC20 contract
    address public owner;          // deployer; can interrupt vesting
    // Methods fields
    bool public interrupted;       // whether vesting is still possible
    bool public isVestingStarted;  // whether vesting period has begun
    uint public totalVestingAmount; // quantity of vested Melon in total
    uint public vestingStartTime;  // timestamp when vesting is set
    uint public vestingPeriod;     // total vesting period in seconds
    address public beneficiary;    // address of the beneficiary
    uint public withdrawn;         // quantity of Melon withdrawn so far

    // MODIFIERS

    modifier not_interrupted() {
        require(
            !interrupted,
            "The contract has been interrupted"
        );
        _;
    }

    modifier only_owner() {
        require(
            msg.sender == owner,
            "Only owner can do this"
        );
        _;
    }

    modifier only_beneficiary() {
        require(
            msg.sender == beneficiary,
            "Only beneficiary can do this"
        );
        _;
    }

    modifier vesting_not_started() {
        require(
            !isVestingStarted,
            "Vesting cannot be started"
        );
        _;
    }

    modifier vesting_started() {
        require(
            isVestingStarted,
            "Vesting must be started"
        );
        _;
    }

    /// @notice Calculates the quantity of Melon asset that's currently withdrawable
    /// @return withdrawable Quantity of withdrawable Melon asset
    function calculateWithdrawable() public view returns (uint withdrawable) {
        uint timePassed = block.timestamp.sub(vestingStartTime);

        if (timePassed < vestingPeriod) {
            uint vested = totalVestingAmount.mul(timePassed).div(vestingPeriod);
            withdrawable = vested.sub(withdrawn);
        } else {
            withdrawable = totalVestingAmount.sub(withdrawn);
        }
    }

    // NON-CONSTANT METHODS

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
        uint ofMelonQuantity,
        uint ofVestingPeriod
    )
        external
        only_owner
        not_interrupted
        vesting_not_started
    {
        require(ofMelonQuantity > 0, "Must vest some MLN");
        require(
            MELON_CONTRACT.transferFrom(msg.sender, this, ofMelonQuantity),
            "MLN deposit failed"
        );
        isVestingStarted = true;
        vestingStartTime = block.timestamp;
        totalVestingAmount = ofMelonQuantity;
        vestingPeriod = ofVestingPeriod;
        beneficiary = ofBeneficiary;
    }

    /// @notice Withdraw
    function withdraw()
        external
        only_beneficiary
        vesting_started
        not_interrupted
    {
        uint withdrawable = calculateWithdrawable();
        withdrawn = withdrawn.add(withdrawable);
        require(
            MELON_CONTRACT.transfer(beneficiary, withdrawable),
            "Transfer to beneficiary failed"
        );
    }

    /// @notice Withdraw vested tokens to beneficiary
    /// @notice Send remainder back to owner
    /// @notice Prevent further vesting
    function forceWithdrawalAndInterrupt()
        external
        only_owner
        vesting_started
        not_interrupted
    {
        interrupted = true;
        uint remainingVested = calculateWithdrawable();
        uint totalToBeVested = withdrawn.add(remainingVested);
        uint remainingUnvested = totalVestingAmount.sub(totalToBeVested);
        withdrawn = totalVestingAmount;
        require(
            MELON_CONTRACT.transfer(beneficiary, remainingVested),
            "Transfer to beneficiary failed"
        );
        require(
            MELON_CONTRACT.transfer(owner, remainingUnvested),
            "Transfer to owner failed"
        );
    }
}
