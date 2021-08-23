//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../util/SingleTokenVestingNonRevocable.sol";

/**
    Fork of badger vesting contracts at https://github.com/chimera-defi/badger-system/blob/adf58e75de994564b55ceb0529a666149d708c8c/contracts/badger-timelock/SmartVesting.sol
    With all executor capabilities removed
 */

/* 
  A token vesting contract that is capable of interacting with other smart contracts.
  This allows the beneficiary to participate in on-chain goverance processes, despite having locked tokens.
  The beneficiary can withdraw the appropriate vested amount at any time.

  Features safety functions to allow beneficiary to claim ETH & ERC20-compliant tokens sent to the timelock contract, accidentially or otherwise.

  An optional 'governor' address has the ability to allow the vesting to send it's tokens to approved destinations. 
  This is intended to allow the token holder to stake their tokens in approved mechanisms.
*/

contract SimpleVesting is SingleTokenVestingNonRevocable, ReentrancyGuardUpgradeable {
    address internal _governor;
    mapping(address => bool) internal _transferAllowed;

    // address beneficiary, uint256 start, uint256 cliffDuration, uint256 duration, bool revocable

    function initialize(
        IERC20Upgradeable token,
        address beneficiary,
        address governor,
        uint256 start,
        uint256 cliffDuration,
        uint256 duration
    ) public initializer {
        __SingleTokenVestingNonRevocable_init(token, beneficiary, start, cliffDuration, duration);
        __ReentrancyGuard_init_unchained();
        _governor = governor;
    }

    event Call(address to, uint256 value, bytes data, bool transfersAllowed);
    event ApproveTransfer(address to);
    event RevokeTransfer(address to);
    event ClaimToken(IERC20Upgradeable token, uint256 amount);
    event ClaimEther(uint256 amount);

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary(), "smart-timelock/only-beneficiary");
        _;
    }

    modifier onlyGovernor() {
        require(msg.sender == _governor, "smart-timelock/only-governor");
        _;
    }

    /**
     * @notice Claim ERC20-compliant tokens other than locked token.
     * @param tokenToClaim Token to claim balance of.
     */
    function claimToken(IERC20Upgradeable tokenToClaim) external onlyBeneficiary nonReentrant {
        require(address(tokenToClaim) != address(token()), "smart-timelock/no-locked-token-claim");
        uint256 preAmount = token().balanceOf(address(this));

        uint256 claimableTokenAmount = tokenToClaim.balanceOf(address(this));
        require(claimableTokenAmount > 0, "smart-timelock/no-token-balance-to-claim");

        tokenToClaim.transfer(beneficiary(), claimableTokenAmount);

        uint256 postAmount = token().balanceOf(address(this));
        require(postAmount >= preAmount, "smart-timelock/locked-balance-check");

        emit ClaimToken(tokenToClaim, claimableTokenAmount);
    }

    /**
     * @notice Claim Ether in contract.
     */
    function claimEther() external onlyBeneficiary nonReentrant {
        uint256 preAmount = token().balanceOf(address(this));

        uint256 etherToTransfer = address(this).balance;
        require(etherToTransfer > 0, "smart-timelock/no-ether-balance-to-claim");

        payable(beneficiary()).transfer(etherToTransfer);

        uint256 postAmount = token().balanceOf(address(this));
        require(postAmount >= preAmount, "smart-timelock/locked-balance-check");

        emit ClaimEther(etherToTransfer);
    }

    /**
     * @notice Governor address
     */
    function governor() external view returns (address) {
        return _governor;
    }

    /**
     * @notice Allow timelock to receive Ether
     */
    receive() external payable {}
}
