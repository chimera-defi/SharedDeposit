// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {ILSTPriceOracle} from "./interfaces/ILSTPriceOracle.sol";
import {Errors} from "../lib/Errors.sol";

/// @title LidoPriceOracle - reference ILSTPriceOracle for stETH
/// @notice Reads stETH's per-share pooled ETH directly from the Lido contract. Since
///         stETH balances ARE ETH-denominated (rebasing), the price function is the
///         identity 1:1 in normal conditions; we still route through the Lido contract
///         so this oracle can be swapped for a wstETH-style one without touching
///         consumers.
interface ILidoStETH {
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
}

contract LidoPriceOracle is ILSTPriceOracle {
    ILidoStETH public immutable LIDO;

    constructor(address lido) {
        if (lido == address(0)) revert Errors.ZeroAddress();
        LIDO = ILidoStETH(lido);
    }

    /// @inheritdoc ILSTPriceOracle
    /// @dev For stETH: 1 stETH ≈ 1 ETH (rebasing). The LST balance IS the ETH backing
    ///      net of slashings. Returning the LST amount as ETH equivalent is correct
    ///      for stETH-denominated holdings.
    function getEthValue(uint256 lstAmount) external view override returns (uint256) {
        // Round-trip via shares to reflect the precise current rebase rate.
        uint256 shares = LIDO.getSharesByPooledEth(lstAmount);
        return LIDO.getPooledEthByShares(shares);
    }

    /// @inheritdoc ILSTPriceOracle
    function getLstValue(uint256 ethAmount) external view override returns (uint256) {
        // Same round-trip in the inverse direction.
        uint256 shares = LIDO.getSharesByPooledEth(ethAmount);
        return LIDO.getPooledEthByShares(shares);
    }
}
