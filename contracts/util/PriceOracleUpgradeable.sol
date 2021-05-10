
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

contract PriceOraceUpgradeable is Initializable {
    function __PriceOraceUpgradeable_init() internal initializer {
        __PriceOraceUpgradeable_init_unchained();
    }

    function __PriceOraceUpgradeable_init_unchained() internal initializer {}

    uint256 public costPerShare; // cost per share in 1e18

    function setCostPerShare(uint256 amount) internal {
        require(amount > 0,
            "Cost per share cannot be 0");
        costPerShare = amount;
    }

    uint256[50] private ______gap;
}
