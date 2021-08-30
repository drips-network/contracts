pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import "./BaseTest.t.sol";

contract PoolTest is BaseTest {
    Hevm public hevm;
    NFTPool pool;
    Dai dai;

    // test user
    User public alice;
    address public alice_;

    User public bob;
    address public bob_;

    function setUp() public {
        hevm = Hevm(HEVM_ADDRESS);
        emit log_named_uint("block.timestamp start", block.timestamp);

        dai = new Dai();
        pool = new NFTPool(CYCLE_SECS, dai);

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

        bob.streamWithAddress(alice_, daiPerSecond, lockAmount);

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
        bob.streamWithAddress(alice_, daiPerSecond, lockAmount);

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
