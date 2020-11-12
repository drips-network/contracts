// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.5;

import "./Rad.sol";
import "./PriceOracle.sol";
import "./Router.sol";

contract Exchange {
    Router public immutable router;
    PriceOracle public immutable oracle;
    address public immutable rad;

    constructor(
        address _rad,
        address _router,
        address _oracle
    ) {
        rad = _rad;
        oracle = PriceOracle(_oracle);
        router = Router(_router);
    }

    function swapEthForRad(address receiver) public payable returns (uint256) {
        require(msg.value > 0, "Swap amount should be positive");

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(rad);

        // The minimum amount of Rad we're willing to receive in exchange.
        // We keep this at zero to ensure registrations don't fail due to
        // market volatility.
        uint256 minimumRad = 0;

        uint256[] memory amounts =
            router.swapExactETHForTokens{value: msg.value}(
                minimumRad,
                path,
                receiver,
                block.timestamp
            );

        // Return RAD amount exchanged.
        return amounts[1];
    }
}
