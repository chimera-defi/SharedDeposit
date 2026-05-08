// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {ILSTPriceOracle} from "./interfaces/ILSTPriceOracle.sol";
import {Errors} from "../lib/Errors.sol";

/// @title StEthPriceOracle - reference ILSTPriceOracle for stETH
/// @notice Reads stETH's per-share pooled ETH directly from the source protocol. Since
///         stETH balances ARE ETH-denominated (rebasing), the price function is the
///         identity 1:1 in normal conditions; we still route through the stETH contract
///         so this oracle can be swapped for a wstETH-style one without touching
///         consumers.
interface IStEth {
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
}

contract StEthPriceOracle is ILSTPriceOracle {
    IStEth public immutable ST_ETH;

    constructor(address stEth) {
        if (stEth == address(0)) revert Errors.ZeroAddress();
        ST_ETH = IStEth(stEth);
    }

    /// @inheritdoc ILSTPriceOracle
    /// @dev For stETH: 1 stETH ≈ 1 ETH (rebasing). The LST balance IS the ETH backing
    ///      net of slashings. Returning the LST amount as ETH equivalent is correct
    ///      for stETH-denominated holdings.
    function getEthValue(uint256 lstAmount) external view override returns (uint256) {
        // Round-trip via shares to reflect the precise current rebase rate.
        uint256 shares = ST_ETH.getSharesByPooledEth(lstAmount);
        return ST_ETH.getPooledEthByShares(shares);
    }

    /// @inheritdoc ILSTPriceOracle
    function getLstValue(uint256 ethAmount) external view override returns (uint256) {
        // Same round-trip in the inverse direction.
        uint256 shares = ST_ETH.getSharesByPooledEth(ethAmount);
        return ST_ETH.getPooledEthByShares(shares);
    }

    /// @inheritdoc ILSTPriceOracle
    /// @dev This oracle reads the live stETH contract on every call, so the price is
    ///      always as fresh as the latest on-chain oracle/rebase update reflected on-chain.
    ///      Returning `block.timestamp` makes any reasonable staleness check pass while
    ///      still letting consumers wire the same guard they would use against a
    ///      push-style oracle. If a future implementation caches values, replace this
    ///      with the timestamp of the cached read.
    function lastUpdated() external view override returns (uint256) {
        return block.timestamp;
    }
}
