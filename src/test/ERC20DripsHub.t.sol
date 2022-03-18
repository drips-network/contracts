// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {DripsHubUser, ERC20DripsHubUser} from "./DripsHubUser.t.sol";
import {ManagedDripsHubUser} from "./ManagedDripsHubUser.t.sol";
import {ManagedDripsHubTest} from "./ManagedDripsHub.t.sol";
import {ERC20Reserve, IERC20Reserve} from "../ERC20Reserve.sol";
import {ERC20DripsHub} from "../ERC20DripsHub.sol";
import {ManagedDripsHubProxy} from "../ManagedDripsHub.sol";
import {IERC20, ERC20PresetFixedSupply} from "openzeppelin-contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract ERC20DripsHubTest is ManagedDripsHubTest {
    ERC20DripsHub private dripsHub;
    uint256 private otherAsset;
    DripsHubUser private user;
    DripsHubUser private receiver1;
    DripsHubUser private receiver2;

    function setUp() public {
        defaultAsset = uint160(
            address(new ERC20PresetFixedSupply("test", "test", 10**6 * 1 ether, address(this)))
        );
        otherAsset = uint160(
            address(new ERC20PresetFixedSupply("other", "other", 10**6 * 1 ether, address(this)))
        );
        ERC20Reserve reserve = new ERC20Reserve(address(this));
        ERC20DripsHub hubLogic = new ERC20DripsHub(10, reserve);
        dripsHub = ERC20DripsHub(address(wrapInProxy(hubLogic)));
        reserve.addUser(address(dripsHub));
        user = createUser();
        receiver1 = createUser();
        receiver2 = createUser();
        ManagedDripsHubTest.setUp(dripsHub);
    }

    function createUser() internal override returns (DripsHubUser newUser) {
        newUser = new ERC20DripsHubUser(dripsHub);
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
        uint32 totalWeight = dripsHub.TOTAL_SPLITS_WEIGHT();
        setSplits(user, splitsReceivers(receiver1, totalWeight / 10));
        give(defaultAsset, receiver2, user, 30);
        give(otherAsset, receiver2, user, 100);
        collectAll(defaultAsset, user, 27, 3);
        collectAll(otherAsset, user, 90, 10);
        collectAll(defaultAsset, receiver1, 3);
        collectAll(otherAsset, receiver1, 10);
    }
}
