pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Withdrawals - ERC20 token to ETH redemption contract
/// @author @ChimeraDefi - sharedstake.org
/// @notice Deployer chooses static virtual price at launch in 1e18 and the underlying ERC20 token
/// @notice Users call deposit(amt) to stake their ERC20 and signal intent to exit
/// @notice When the contract has enough ETH to service the users debt
/// @notice Users call redeem() to redem for ETH = deposited shares * virtualPrice
/// @notice The user can further call withdraw() if they change their mind about redeeming for ETH
/// @dev TODO Docs
/// @dev TODO Test goerli
contract Withdrawals {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    error ContractBalanceTooLow();
    error UserStakeTooLow();
    struct UserEntry {
        uint256 amount;
    }

    mapping(address => UserEntry) internal _userEntries;
    IERC20 public vEth2Token;
    uint256 public virtualPrice;
    uint256 public totalOut;

    constructor(address _underlying, uint256 _virtualPrice) payable {
        vEth2Token = IERC20(_underlying);
        virtualPrice = _virtualPrice;
    }

    function deposit(uint256 amount) external {
        // vEth2 transfer from returns true otherwise reverts
        if (vEth2Token.transferFrom(msg.sender, address(this), amount)) {
            _stakeForWithdrawal(msg.sender, amount);
        }
    }

    function withdraw() external {
        uint256 amt = _userEntries[msg.sender].amount;
        delete _userEntries[msg.sender];

        vEth2Token.transferFrom(address(this), msg.sender, amt);
    }

    function redeem() external {
        uint256 amountToReturn = _getAmountGivenShares(_userEntries[msg.sender].amount, virtualPrice);
        _check(msg.sender, _userEntries[msg.sender].amount, amountToReturn);
        delete _userEntries[msg.sender];
        totalOut += amountToReturn;

        payable(msg.sender).transfer(amountToReturn);
    }

    function _getAmountGivenShares(uint256 shares, uint256 _vp) internal pure returns (uint256) {
        return shares.mul(_vp).div(1e18);
    }

    function _stakeForWithdrawal(address sender, uint256 amount) internal {
        UserEntry memory ue = _userEntries[sender];
        ue.amount = ue.amount.add(amount);
        _userEntries[sender] = ue;
    }

    function _check(
        address sender,
        uint256 amountToWithdraw,
        uint256 amountToReturn
    ) internal view {
        if (amountToWithdraw >= _userEntries[sender].amount) {
            revert UserStakeTooLow();
        } else if (amountToReturn >= address(this).balance) {
            revert ContractBalanceTooLow();
        }
    }

    receive() external payable {} // solhint-disable-line

    fallback() external payable {} // solhint-disable-line
}
