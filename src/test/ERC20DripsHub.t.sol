// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {AddressIdUser} from "./AddressIdUser.t.sol";
import {AddressIdUser} from "./AddressIdUser.t.sol";
import {ManagedDripsHubTest} from "./ManagedDripsHub.t.sol";
import {AddressId} from "../AddressId.sol";
import {ERC20Reserve, IERC20Reserve} from "../ERC20Reserve.sol";
import {ERC20DripsHub} from "../ERC20DripsHub.sol";
import {Proxy} from "../Managed.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20DripsHubTest is ManagedDripsHubTest {
    ERC20DripsHub private dripsHub;
    AddressId private addressId;
    uint256 private otherAsset;
    AddressIdUser private user;
    AddressIdUser private receiver1;
    AddressIdUser private receiver2;

    function setUp() public {
        defaultAsset = uint160(
            address(new ERC20PresetFixedSupply("test", "test", 10**6 * 1 ether, address(this)))
        );
        otherAsset = uint160(
            address(new ERC20PresetFixedSupply("other", "other", 10**6 * 1 ether, address(this)))
        );
        ERC20Reserve reserve = new ERC20Reserve(address(this));
        ERC20DripsHub hubLogic = new ERC20DripsHub(10, reserve);
        dripsHub = wrapInProxy(hubLogic);
        reserve.addUser(address(dripsHub));
        addressId = new AddressId(dripsHub);
        user = createUser();
        receiver1 = createUser();
        receiver2 = createUser();
        ManagedDripsHubTest.setUp(dripsHub);
    }

    function createUser() internal override returns (AddressIdUser newUser) {
        newUser = new AddressIdUser(addressId);
        IERC20(address(uint160(defaultAsset))).transfer(address(newUser), 100 ether);
        IERC20(address(uint160(otherAsset))).transfer(address(newUser), 100 ether);
    }

    function testDripsInDifferentTokensAreIndependent() public {
        uint64 cycleLength = dripsHub.cycleSecs();
        // Covers 1.5 cycles of dripping
        setDrips(
            defaultAsset,
            user,
            0,
            9 * cycleLength,
            dripsReceivers(receiver1, 4, receiver2, 2)
        );

        warpToCycleEnd();
        // Covers 2 cycles of dripping
        setDrips(otherAsset, user, 0, 6 * cycleLength, dripsReceivers(receiver1, 3));

        warpToCycleEnd();
        // receiver1 had 1.5 cycles of 4 per second
        collectAll(defaultAsset, receiver1, 6 * cycleLength);
        // receiver1 had 1.5 cycles of 2 per second
        collectAll(defaultAsset, receiver2, 3 * cycleLength);
        // receiver1 had 1 cycle of 3 per second
        collectAll(otherAsset, receiver1, 3 * cycleLength);
        // receiver2 received nothing
        collectAll(otherAsset, receiver2, 0);

        warpToCycleEnd();
        // receiver1 received nothing
        collectAll(defaultAsset, receiver1, 0);
        // receiver2 received nothing
        collectAll(defaultAsset, receiver2, 0);
        // receiver1 had 1 cycle of 3 per second
        collectAll(otherAsset, receiver1, 3 * cycleLength);
        // receiver2 received nothing
        collectAll(otherAsset, receiver2, 0);
    }

    function testSplitsConfigurationIsCommonBetweenTokens() public {
        uint32 totalWeight = dripsHub.totalSplitsWeight();
        setSplits(user, splitsReceivers(receiver1, totalWeight / 10));
        give(defaultAsset, receiver2, user, 30);
        give(otherAsset, receiver2, user, 100);
        collectAll(defaultAsset, user, 27, 3);
        collectAll(otherAsset, user, 90, 10);
        collectAll(defaultAsset, receiver1, 3);
        collectAll(otherAsset, receiver1, 10);
    }

    function testSetDripsRevertsWhenNotAccountOwner() public {
        try
            dripsHub.setDrips(
                calcUserId(dripsHub.nextAccountId(), 0),
                defaultAsset,
                0,
                0,
                dripsReceivers(),
                0,
                dripsReceivers()
            )
        {
            assertTrue(false, "SetDrips hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid setDrips revert reason");
        }
    }

    function testGiveRevertsWhenNotAccountOwner() public {
        try dripsHub.give(calcUserId(dripsHub.nextAccountId(), 0), 0, defaultAsset, 1) {
            assertTrue(false, "Give hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid give revert reason");
        }
    }

    function testSetSplitsRevertsWhenNotAccountOwner() public {
        try dripsHub.setSplits(calcUserId(dripsHub.nextAccountId(), 0), splitsReceivers()) {
            assertTrue(false, "SetSplits hasn't reverted");
        } catch Error(string memory reason) {
            assertEq(reason, ERROR_NOT_OWNER, "Invalid setSplits revert reason");
        }
    }

    function testAnyoneCanCollectForAnyoneUsingAddressId() public {
        give(user, receiver1, 5);
        split(receiver1, 5, 0);
        assertCollectable(receiver1, 5);
        uint256 balanceBefore = receiver1.balance(defaultAsset);
        IERC20 erc20 = IERC20(address(uint160(defaultAsset)));

        uint128 collected = addressId.collect(address(receiver1), erc20);

        assertEq(collected, 5, "Invalid collected amount");
        assertCollectable(receiver1, 0);
        assertBalance(receiver1, balanceBefore + 5);
    }

    function testAnyoneCanCollectAllForAnyoneUsingAddressId() public {
        give(user, receiver1, 5);
        assertCollectableAll(receiver1, 5);
        uint256 balanceBefore = receiver1.balance(defaultAsset);
        IERC20 erc20 = IERC20(address(uint160(defaultAsset)));

        (uint128 collected, uint128 split) = addressId.collectAll(
            address(receiver1),
            erc20,
            splitsReceivers()
        );

        assertEq(collected, 5, "Invalid collected amount");
        assertEq(split, 0, "Invalid split amount");
        assertCollectableAll(receiver1, 0);
        assertBalance(receiver1, balanceBefore + 5);
    }
}
