// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Drips, IERC20, SplitsReceiver} from "src/Drips.sol";
import {RepoDeadlineDriver, RepoDriver} from "src/RepoDeadlineDriver.sol";
import {ManagedProxy} from "src/Managed.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20PresetFixedSupply} from
    "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract FakeRepoDriver {
    Drips public immutable drips;

    constructor(Drips drips_) {
        drips = drips_;
    }

    mapping(uint256 accountId => address owner) public ownerOf;

    function setOwnerOf(uint256 accountId, address owner) public {
        ownerOf[accountId] = owner;
    }
}

contract RepoDeadlineDriverTest is Test {
    Drips internal drips;
    FakeRepoDriver internal repoDriver;
    RepoDeadlineDriver internal driver;
    IERC20 internal erc20;

    uint256 internal deadlineAccountId;
    uint256 internal immutable repoAccountId = uint256(bytes32("repo"));
    uint256 internal immutable recipientAccountId = uint256(bytes32("recipient"));
    uint256 internal immutable refundAccountId = uint256(bytes32("refund"));
    uint32 internal immutable deadline = 100;
    uint128 internal immutable amount = 10;

    function setUp() public {
        Drips dripsLogic = new Drips(10);
        drips = Drips(address(new ManagedProxy(dripsLogic, address(this), "")));

        // Register self as driver `0` and having control of account ID `0`.
        drips.registerDriver(address(this));

        repoDriver = new FakeRepoDriver(drips);
        drips.registerDriver(address(repoDriver));

        RepoDeadlineDriver driverLogic =
            new RepoDeadlineDriver(RepoDriver(payable(address(repoDriver))), drips.nextDriverId());
        driver = RepoDeadlineDriver(
            address(new ManagedProxy(driverLogic, address(bytes20("admin")), ""))
        );
        drips.registerDriver(address(driver));

        deadlineAccountId =
            driver.calcAccountId(repoAccountId, recipientAccountId, refundAccountId, deadline);
        erc20 = new ERC20PresetFixedSupply("test", "test", amount, address(drips));
        drips.give(0, deadlineAccountId, erc20, amount);
        drips.split(deadlineAccountId, erc20, new SplitsReceiver[](0));
    }

    function collectAndGive(uint128 leftAmt, uint128 receiveAmt, uint128 refundAmt) internal {
        uint128 givenAmt = driver.collectAndGive(
            repoAccountId, recipientAccountId, refundAccountId, deadline, erc20
        );
        assertEq(givenAmt, amount - leftAmt, "Invalid given amount");
        assertEq(drips.collectable(deadlineAccountId, erc20), leftAmt, "Invalid left amount");
        assertEq(drips.splittable(recipientAccountId, erc20), receiveAmt, "Invalid received amount");
        assertEq(drips.splittable(refundAccountId, erc20), refundAmt, "Invalid refunded amount");
    }

    function testCollectAndGiveDoesNothingBeforeClaiming() public {
        collectAndGive({leftAmt: amount, receiveAmt: 0, refundAmt: 0});
    }

    function testCollectAndGiveRefundsAfterDeadline() public {
        vm.warp(deadline);
        collectAndGive({leftAmt: 0, receiveAmt: 0, refundAmt: amount});
    }

    function testCollectAndGiveGivesAfterClaiming() public {
        repoDriver.setOwnerOf(repoAccountId, address(1));
        collectAndGive({leftAmt: 0, receiveAmt: amount, refundAmt: 0});
    }

    function testCollectAndGiveGivesAfterClaimingAndDeadline() public {
        vm.warp(deadline);
        repoDriver.setOwnerOf(repoAccountId, address(1));
        collectAndGive({leftAmt: 0, receiveAmt: amount, refundAmt: 0});
    }

    function testCollectAndGiveCanBePaused() public {
        vm.prank(driver.admin());
        driver.pause();
        vm.expectRevert("Contract paused");
        driver.collectAndGive(0, 0, 0, 0, erc20);
    }
}
