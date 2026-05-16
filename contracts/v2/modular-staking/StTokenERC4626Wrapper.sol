// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IStToken is IERC20 {
    function totalPooledEther() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
}

/**
 * @title StTokenERC4626Wrapper
 * @notice ERC-4626 compliant vault that wraps the rebasing stToken (stETH-like shares)
 *         into a non-rebasing vault token. Enables DeFi composability (Aave, Compound,
 *         Pendle, etc.) without rebasing accounting complications.
 *
 * asset  = stToken (the underlying rebasing shares token)
 * share  = wstToken-equivalent vault token (this contract's ERC-20)
 *
 * Exchange rate: 1 vault share = `convertToAssets(1e18)` stToken shares.
 * As the protocol accumulates staking rewards, each vault share appreciates in stToken terms.
 *
 * Withdrawal note: `withdraw()` and `redeem()` return stToken shares synchronously.
 * To convert stToken shares back to ETH, use the WithdrawalQueueV2 protocol flow.
 * This is documented in previewWithdraw() and totalAssets() NatSpec below.
 */
contract StTokenERC4626Wrapper is ERC4626 {
    using Math for uint256;

    IStToken private immutable ST_TOKEN;

    constructor(address stToken)
        ERC20("SharedStake Wrapped StToken", "wstToken-4626")
        ERC4626(IERC20(stToken))
    {
        ST_TOKEN = IStToken(stToken);
    }

    // ─── ERC-4626 overrides ──────────────────────────────────────────────────

    /**
     * @notice Total ETH-equivalent value of assets held in this vault.
     *
     * NOTE: This is the ETH value of the stToken shares held by this contract,
     * not a claimable ETH amount. Actual ETH redemption goes through the
     * WithdrawalQueueV2 two-step flow after calling withdraw()/redeem().
     */
    function totalAssets() public view override returns (uint256) {
        uint256 sharesHeld = ST_TOKEN.balanceOf(address(this));
        if (sharesHeld == 0) return 0;
        return ST_TOKEN.getPooledEthByShares(sharesHeld);
    }

    /**
     * @notice Convert vault shares to stToken asset amount using the live exchange rate.
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) return shares;
        uint256 stTokenHeld = ST_TOKEN.balanceOf(address(this));
        return shares.mulDiv(stTokenHeld, supply, Math.Rounding.Down);
    }

    /**
     * @notice Convert stToken asset amount to vault shares using the live exchange rate.
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 stTokenHeld = ST_TOKEN.balanceOf(address(this));
        if (supply == 0 || stTokenHeld == 0) return assets;
        return assets.mulDiv(supply, stTokenHeld, Math.Rounding.Down);
    }

    /**
     * @notice Preview how many vault shares `assets` stToken will yield.
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @notice Preview how many stToken `shares` vault shares will cost to mint.
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 stTokenHeld = ST_TOKEN.balanceOf(address(this));
        if (supply == 0 || stTokenHeld == 0) return shares;
        return shares.mulDiv(stTokenHeld, supply, Math.Rounding.Up);
    }

    /**
     * @notice Preview how many vault shares are needed to withdraw `assets` stToken.
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        uint256 stTokenHeld = ST_TOKEN.balanceOf(address(this));
        if (supply == 0 || stTokenHeld == 0) return assets;
        return assets.mulDiv(supply, stTokenHeld, Math.Rounding.Up);
    }

    /**
     * @notice Preview how many stToken `shares` vault shares will return on redeem.
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    // ─── Internal mint/burn wiring (required by OZ ERC4626) ─────────────────

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
