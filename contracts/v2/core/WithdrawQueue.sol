// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {SharedDepositMinterV2} from "./SharedDepositMinterV2.sol";

contract WithdrawQueue is AccessControl, Pausable, ReentrancyGuard {
    SharedDepositMinterV2 public immutable MINTER;
    address public immutable SGETH;
    address public immutable WSGETH;

    // This code snippet is incomplete pseudocode used for example only and is no way intended to be used in production or guaranteed to be secure
    mapping(address => uint256) public pendingRedeemRequest;

    mapping(address => uint256) public claimableRedeemRequest;

    mapping(address requester => mapping(address operator => bool)) public isOperator;

    event RedeemRequest(
        address indexed requester,
        address indexed owner,
        uint256 indexed requestId,
        address operator,
        uint256 assets
    );
    event Redeem(address indexed requester, address indexed receiver, uint256 shares, uint256 assets);
    event OperatorSet(address indexed owner, address indexed operator, bool value);

    constructor(address _minter, address _sgEth, address _wsgEth) {
        MINTER = SharedDepositMinterV2(_minter);
        SGETH = _sgEth;
        WSGETH = _wsgEth;

        uint256 maxUint256 = 2 ** 256 - 1;

        IERC20(WSGETH).approve(_minter, maxUint256);
        IERC20(SGETH).approve(_minter, maxUint256);
    }

    function requestRedeem(uint256 shares, address requester, address owner) external returns (uint256 requestId) {
        require(shares != 0);
        require(owner == msg.sender || isOperator[owner][msg.sender]);

        requestId = 0; // no requestId associated with this request

        IERC20(WSGETH).transferFrom(owner, address(this), shares); // asset here is the Vault underlying asset

        pendingRedeemRequest[requester] += shares;

        emit RedeemRequest(requester, owner, requestId, msg.sender, shares);
        return requestId;
    }

    /**
     * Include some arbitrary transition logic here from Pending to Claimable
     */

    function redeem(uint256 shares, address receiver, address requester) external returns (uint256 assets) {
        require(shares != 0);
        require(requester == msg.sender || isOperator[requester][msg.sender]);

        claimableRedeemRequest[requester] -= shares; // underflow would revert if not enough claimable shares

        assets = IERC4626(WSGETH).previewRedeem(shares);

        MINTER.unstakeAndWithdraw(shares, receiver);

        emit Redeem(requester, receiver, shares, assets);
    }

    function setOperator(address operator, bool approved) public returns (bool) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }
}
