// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/// @title ILSTPriceOracle - price oracle for an LST (e.g. stETH, rETH)
/// @notice Returns the ETH equivalent of an LST balance. Used by `LSTWrapModule` to
///         compute the stToken share entitlement for an LST deposit and the LST owed
///         on unwrap. Implementations must be view-only and deterministic.
///
///         Reference implementation `LidoPriceOracle.sol` reads stETH's per-share
///         pooled ETH directly from the Lido contract.
interface ILSTPriceOracle {
    /// @notice ETH value (wei) of `lstAmount` LST tokens at current price.
    function getEthValue(uint256 lstAmount) external view returns (uint256);

    /// @notice Inverse: how many LST tokens correspond to `ethAmount` wei.
    function getLstValue(uint256 ethAmount) external view returns (uint256);
}
