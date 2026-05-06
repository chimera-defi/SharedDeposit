// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title MockILidoStETH
/// @notice Minimal mock of Lido's stETH interface for testing LidoPriceOracle.
///         Identity mapping: 1 share = 1 wei, so round-trip is exact.
contract MockILidoStETH {
    function getPooledEthByShares(uint256 sharesAmount) external pure returns (uint256) {
        return sharesAmount;
    }

    function getSharesByPooledEth(uint256 ethAmount) external pure returns (uint256) {
        return ethAmount;
    }
}
