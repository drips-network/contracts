pragma solidity ^0.7.5;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "./../Pool.sol";
import "openzeppelin-contracts/math/SafeMath.sol";

interface Hevm {
    function warp(uint256) external;
}

contract User {
    DaiPool public pool;
    Dai public dai;
    constructor(DaiPool pool_, Dai dai_) {
        pool = pool_;
        dai = dai_;
    }

    function withdraw(uint withdrawAmount) public {
        pool.updateSender(0, uint128(withdrawAmount), 0,  new ReceiverWeight[](0), new ReceiverWeight[](0));
    }

    function collect() public {
        pool.collect();
    }

    function send(address to, uint daiPerSecond, uint lockAmount) public {
        ReceiverWeight[] memory receivers = new ReceiverWeight[](1);
        receivers[0] = ReceiverWeight({receiver:to, weight:pool.SENDER_WEIGHTS_SUM_MAX()});

        dai.approve(address(pool), uint(-1));
        pool.updateSender(uint128(lockAmount), 0, uint128(daiPerSecond), receivers, new ReceiverWeight[](0));
    }
}

contract PoolTest is DSTest {
    using SafeMath for uint;

    Hevm public hevm;
    DaiPool pool;
    Dai dai;

    // test user
    User public alice;
    address public alice_;

    User public bob;
    address public bob_;

    uint constant SECONDS_PER_YEAR = 31536000;
    uint64 constant CYCLE_SECS = 30 days;
    uint constant TOLERANCE = 10 ** 10;

    function fundingInSeconds(uint fundingPerCycle) public pure returns(uint) {
        return fundingPerCycle/CYCLE_SECS;
    }

    // assert equal two variables with a wei tolerance
    function assertEqTol(uint actual, uint expected, bytes32 msg_) public {
        uint diff;
        if (actual > expected) {
            diff = actual.sub(expected);
        } else {
            diff = expected.sub(actual);
        }
        if (diff > TOLERANCE) {
            emit log_named_bytes32(string(abi.encodePacked(msg_)), "Assert Equal Failed");
            emit log_named_uint("Expected", expected);
            emit log_named_uint("Actual  ", actual);
            emit log_named_uint("Diff    ", diff);

        }
        assertTrue(diff <= TOLERANCE);
    }

    function setUp() public {
        hevm = Hevm(HEVM_ADDRESS);
        emit log_named_uint("block.timestamp start", block.timestamp);

        dai = new Dai();
        pool = new DaiPool(CYCLE_SECS, dai);

        alice = new User(pool, dai);
        alice_ = address(alice);

        bob = new User(pool, dai);
        bob_ = address(bob);
    }

    function testBasic() public {
        uint lockAmount = 5_000 ether;
        // 1000 DAI per month
        uint daiPerCycle = 10 ether;
        uint daiPerSecond = fundingInSeconds(daiPerCycle);

        emit log_named_uint("dai per seconds", daiPerSecond);

        dai.transfer(bob_, lockAmount);

        bob.send(alice_, daiPerSecond, lockAmount);

        // two cycles
        uint t = 60 days;
        hevm.warp(block.timestamp + t);

        alice.collect();
        assertEqTol(dai.balanceOf(alice_), t * daiPerSecond, "incorrect received amount");
    }

    function testSendFuzzTime(uint48 t) public {
        // random time between 0 and a month in the future
        if (t > SECONDS_PER_YEAR) {
            return;
        }

        dai.transfer(bob_, SECONDS_PER_YEAR * 1 ether);

        // send 0.001 DAI per second
        uint daiPerSecond = 1 ether * 0.001;

        uint lockAmount = 1_000_000 ether;
        bob.send(alice_, daiPerSecond, lockAmount);

        hevm.warp(block.timestamp + t);

        uint passedCycles = t/CYCLE_SECS;
        uint daiPerCycle = daiPerSecond * CYCLE_SECS;

        uint receivedAmount = daiPerCycle * passedCycles;

        assertEq(dai.balanceOf(alice_), 0);
        alice.collect();
        assertEqTol(dai.balanceOf(alice_), receivedAmount, "incorrect received amount");
        emit log_named_uint("block.timestamp end", block.timestamp);
    }
}
