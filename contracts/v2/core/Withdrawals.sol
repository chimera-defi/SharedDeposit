// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {RedemptionsBase} from "../lib/RedemptionsBase.sol";

/// @title Withdrawals - ERC20 token to ETH redemption contract
/// @author @ChimeraDefi - sharedstake.org
/// @notice Withdrawals accepts an underlying ERC20 and redeems it for ETH
/** @dev Deployer chooses static virtual price at launch in 1e18 and the underlying ERC20 token
    Users call deposit(amt) to stake their ERC20 and signal intent to exit
    When the contract has enough ETH to service the users debt
    Users call redeem() to redem for ETH = deposited shares * virtualPrice
    The user can further call withdraw() if they change their mind about redeeming for ETH
**/
contract Withdrawals is RedemptionsBase {
    event Redemption(address indexed _from, uint256 val);

    constructor(address _underlying, uint256 _virtualPrice) payable RedemptionsBase(_underlying, _virtualPrice) {} // solhint-disable-line

    function _redeem(uint256 amountToReturn) internal override {
        if (amountToReturn > address(this).balance) {
            revert ContractBalanceTooLow();
        }
        emit Redemption(msg.sender, amountToReturn);

        payable(msg.sender).transfer(amountToReturn);
    }
}
