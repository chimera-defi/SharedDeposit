// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title xERC4626
/// @notice ERC4626 that separates stored assets from rewards that unlock
///         linearly over the next reward cycle.
contract xERC4626 is ERC4626 {
    /// @notice Assets currently stored in the pool.
    uint256 public storedTotalAssets;

    /// @notice Rewards that will be distributed linearly on the next reward cycle.
    uint256 public unlockedRewards;

    /// @notice Pool bookkeeping.
    struct PoolState {
        uint256 lastUpdated;
    }

    PoolState public poolState;

    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        return storedTotalAssets + unlockedRewards;
    }

    /// @inheritdoc ERC4626
    function redeem(uint256 redeemAmount, address receiver, address owner) external override returns (uint256) {
        uint256 totalAssets = storedTotalAssets + unlockedRewards;

        require(totalAssets >= redeemAmount, "insufficient assets");

        // A redemption larger than storedTotalAssets is settled against the rewards
        // that unlock linearly on the next reward cycle, avoiding an underflow.
        uint256 amount = redeemAmount;
        if (amount <= storedTotalAssets) {
            storedTotalAssets -= amount;
        } else {
            amount -= storedTotalAssets;
            storedTotalAssets = 0;
            unlockedRewards -= amount;
        }

        poolState.lastUpdated = block.timestamp;

        return super.redeem(redeemAmount, receiver, owner);
    }
}
