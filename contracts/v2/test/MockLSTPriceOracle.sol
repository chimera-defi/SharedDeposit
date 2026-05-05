// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ILSTPriceOracle} from "../lido-parity/interfaces/ILSTPriceOracle.sol";

/// @title MockLSTPriceOracle
/// @notice Test-only oracle that lets a test set the ETH-per-LST exchange rate.
///         Used to model peg deviations and price-oracle manipulation scenarios.
contract MockLSTPriceOracle is ILSTPriceOracle {
    /// @notice Wei of ETH represented by 1e18 of the LST token.
    uint256 public ethPerLst;

    constructor(uint256 _ethPerLst) {
        ethPerLst = _ethPerLst;
    }

    function setEthPerLst(uint256 _ethPerLst) external {
        ethPerLst = _ethPerLst;
    }

    /// @inheritdoc ILSTPriceOracle
    function getEthValue(uint256 lstAmount) external view override returns (uint256) {
        return (lstAmount * ethPerLst) / 1e18;
    }

    /// @inheritdoc ILSTPriceOracle
    function getLstValue(uint256 ethAmount) external view override returns (uint256) {
        if (ethPerLst == 0) return 0;
        return (ethAmount * 1e18) / ethPerLst;
    }
}
