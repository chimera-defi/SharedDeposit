
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {PriceOraceUpgradeable} from "./PriceOracleUpgradeable.sol";

contract VaultWithSharesAndCapUpgradeable is Initializable, PriceOraceUpgradeable {
    using SafeMathUpgradeable for uint256;
    uint256 public curShares; //initialized to 0
    uint256 public maxShares;
    // Its hard to exactly hit the max deposit amount with small shares. this allows a small bit of overflow room
    // Tokens in the buffer cannot be withdrawn by an admin, only by burning the underlying token via a user withdraw
    uint256 public buffer;

    function __VaultWithSharesAndCapUpgradeable_init() internal initializer {
        __VaultWithSharesAndCapUpgradeable_init_unchained();
    }

    function __VaultWithSharesAndCapUpgradeable_init_unchained() internal initializer {
        __PriceOraceUpgradeable_init_unchained();
    }

    function getSharesGivenAmount(uint256 amount) public view returns (uint256) {
        return amount.div(costPerShare).mul(1e18);
    }

    function getAmountGivenShares(uint256 shares) public view returns (uint256) {
        return shares.mul(costPerShare).div(1e18);
    }

    function setCap(uint256 amount) internal {
        require(amount > 0,
        "Cap cannot be 0");
        maxShares = amount;
    }

    function setBuffer(uint256 amount) internal {
        require(amount > 0,
        "Buffer cannot be 0");
        buffer = amount;
    }

    function incrementShares(uint256 amount) underCap(amount) internal {
        setCurrentShares(curShares.add(amount));
    }

    function decrementShares(uint256 amount) aboveZero(amount) internal {
        setCurrentShares(curShares.sub(amount));
    }

    function setCurrentShares(uint256 amount) internal {
        curShares = amount;
    }

    modifier underCap(uint256 amount) {
        require(curShares.add(amount) <= buffer.add(maxShares), 
        "VaultWithSharesAndCapUpgradeable:: Amount too large; Exceeds Cap");
        _;
    }

    modifier aboveZero(uint256 amount) {
        require(curShares.sub(amount) > 0,
        "VaultWithSharesAndCapUpgradeable:: newShareTotal cannot be negative");
        _;
    }

    function depositAndAccountShares(uint256 amount) internal returns (uint256) {
        uint256 newShares = getSharesGivenAmount(amount);
        incrementShares(newShares);
        return newShares;
    }

    function withdrawAndAccountShares(uint256 amount) internal returns (uint256) {
        uint256 newShares = getAmountGivenShares(amount);
        decrementShares(newShares);
        return newShares;
    }

    uint256[50] private ______gap;
}
