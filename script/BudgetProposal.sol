// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {
    Call,
    Calls,
    GovernorProposal,
    GovernorProposalImpl,
    RADWORKS_GOVERNOR,
    RADWORKS_TIMELOCK
} from "script/utils/Governor.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {console, Script} from "forge-std/Script.sol";
import {
    IERC20,
    IERC20Metadata
} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

IERC20Metadata constant RAD = IERC20Metadata(0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3);
IERC20Metadata constant USDC = IERC20Metadata(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
address constant DRIPS_ORG = 0xcC7d34C76A9d08aa0109F7Bae35f29C1CE35355A;
address constant GARDEN_ORG = 0x98aE6262A779e61846dF9D548a03282b246E4C68;

function createProposal() view returns (GovernorProposal memory proposal) {
    return GovernorProposalImpl.create(RADWORKS_GOVERNOR, "RGP-28").pushCall(
        address(RAD),
        abi.encodeCall(IERC20.transfer, (DRIPS_ORG, 7_500_000 * (10 ** RAD.decimals())))
    ).pushCall(
        address(USDC),
        abi.encodeCall(IERC20.transfer, (DRIPS_ORG, 894_000 * (10 ** USDC.decimals())))
    ).pushCall(
        address(USDC),
        abi.encodeCall(IERC20.transfer, (GARDEN_ORG, 2_100_000 * (10 ** USDC.decimals())))
    );
}

contract TestProposal is Script, StdAssertions {
    function run() public {
        uint256 radworksRad = RAD.balanceOf(RADWORKS_TIMELOCK);
        uint256 radworksUsdc = USDC.balanceOf(RADWORKS_TIMELOCK);
        uint256 dripsOrgRad = RAD.balanceOf(DRIPS_ORG);
        uint256 dripsOrgUsdc = USDC.balanceOf(DRIPS_ORG);
        uint256 gardenOrgUsdc = USDC.balanceOf(GARDEN_ORG);

        createProposal().testExecute();

        assertEq(RAD.balanceOf(RADWORKS_TIMELOCK), radworksRad - 7_500_000 * (10 ** RAD.decimals()));
        assertEq(
            USDC.balanceOf(RADWORKS_TIMELOCK),
            radworksUsdc - (894_000 + 2_100_000) * (10 ** USDC.decimals())
        );
        assertEq(RAD.balanceOf(DRIPS_ORG), dripsOrgRad + 7_500_000 * (10 ** RAD.decimals()));
        assertEq(USDC.balanceOf(DRIPS_ORG), dripsOrgUsdc + 894_000 * (10 ** USDC.decimals()));
        assertEq(USDC.balanceOf(GARDEN_ORG), gardenOrgUsdc + 2_100_000 * (10 ** USDC.decimals()));
    }
}

contract Propose is Script {
    function run() public {
        vm.startBroadcast();
        uint256 proposalId = createProposal().propose();
        console.log("Proposed proposal", proposalId);
    }
}

contract Queue is Script {
    function run() public {
        vm.startBroadcast();
        uint256 proposalId = createProposal().queue();
        console.log("Queued proposal", proposalId);
    }
}

contract Execute is Script {
    function run() public {
        vm.startBroadcast();
        uint256 proposalId = createProposal().execute();
        console.log("Executed proposal", proposalId);
    }
}
