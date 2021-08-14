// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;
pragma experimental ABIEncoderV2;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {PriceOracleUpgradeable} from "./PriceOracleUpgradeable.sol";

contract VaultWithSharesAndCapUpgradeable is Initializable, PriceOracleUpgradeable {
    using SafeMathUpgradeable for uint256;
    uint256 public curShares; //initialized to 0
    uint256 public maxShares;
    // Its hard to exactly hit the max deposit amount with small shares. this allows a small bit of overflow room
    // Tokens in the buffer cannot be withdrawn by an admin, only by burning the underlying token via a user withdraw
    uint256 public buffer;

    function __VaultWithSharesAndCapUpgradeable_init(uint256 _sharePrice) internal initializer {
        __VaultWithSharesAndCapUpgradeable_init_unchained(_sharePrice);
    }

    function __VaultWithSharesAndCapUpgradeable_init_unchained(uint256 _sharePrice) internal initializer {
        __PriceOracleUpgradeable_init_unchained(_sharePrice);
    }

    function getSharesGivenAmount(uint256 amount) public view returns (uint256) {
        return amount.div(costPerShare).mul(1e18);
    }

    function getAmountGivenShares(uint256 shares) public view returns (uint256) {
        return shares.mul(costPerShare).div(1e18);
    }

    function _setCap(uint256 amount) internal {
        require(amount > 0, "Cap cannot be 0");
        maxShares = amount;
    }

    function _setBuffer(uint256 amount) internal {
        require(amount > 0, "Buffer cannot be 0");
        buffer = amount;
    }

    function _setCurrentShares(uint256 amount) internal {
        curShares = amount;
    }

    function _incrementShares(uint256 amount) internal underCap(amount) {
        _setCurrentShares(curShares.add(amount));
    }

    function _decrementShares(uint256 amount) internal aboveOrEqualToZero(amount) {
        _setCurrentShares(curShares.sub(amount));
    }

    modifier underCap(uint256 amount) {
        if (maxShares > 0) {
            require(
                curShares.add(amount) <= buffer.add(maxShares),
                "VaultWithSharesAndCapUpgradeable:: Amount too large; Exceeds Cap"
            );
        }
        _;
    }

    modifier aboveOrEqualToZero(uint256 amount) {
        require(curShares.sub(amount) >= 0, "VaultWithSharesAndCapUpgradeable:: newShareTotal cant be -ve");
        _;
    }

    function _depositAndAccountShares(uint256 amount) internal returns (uint256) {
        uint256 newShares = getSharesGivenAmount(amount);
        _incrementShares(newShares);
        return newShares;
    }

    function _withdrawAndAccountShares(uint256 amount) internal returns (uint256) {
        uint256 newShares = getAmountGivenShares(amount);
        _decrementShares(amount);
        return newShares;
    }

    uint256[50] private ______gap;
}
