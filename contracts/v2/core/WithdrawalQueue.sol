// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {SharedDepositMinterV2} from "./SharedDepositMinterV2.sol";

contract WithdrawalQueue is AccessControl, Pausable, ReentrancyGuard {
    struct Request {
        address requester;
        uint256 shares;
    }
    SharedDepositMinterV2 public immutable MINTER;
    address public immutable WSGETH;

    uint256 public constant REDEEM_THRESOLD = 32 ether;

    uint256 internal requestBack;
    uint256 internal totalPendingRequest;
    uint256 internal requestFront;
    mapping(uint256 => Request) internal requests;
    mapping(address => uint256) public claimableRedeemRequest;

    // This code snippet is incomplete pseudocode used for example only and is no way intended to be used in production or guaranteed to be secure
    // mapping(address => uint256) public pendingRedeemRequest;

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

    error InvalidAmount();
    error PermissionDenied();
    error InsufficientBalance();

    modifier onlyOwnerOrOperator(address owner) {
        if (owner != msg.sender && !isOperator[owner][msg.sender]) {
            revert PermissionDenied();
        }
        _;
    }

    constructor(address _minter, address _wsgEth) {
        MINTER = SharedDepositMinterV2(_minter);
        WSGETH = _wsgEth;

        uint256 maxUint256 = 2 ** 256 - 1;

        IERC20(WSGETH).approve(_minter, maxUint256);
    }

    function requestRedeem(
        uint256 shares,
        address requester,
        address owner
    ) external onlyOwnerOrOperator(owner) nonReentrant whenNotPaused returns (uint256 requestId) {
        if (shares == 0) {
            revert InvalidAmount();
        }

        requestId = requestBack++;

        IERC20(WSGETH).transferFrom(owner, address(this), shares); // asset here is the Vault underlying asset

        totalPendingRequest += shares;
        requests[requestId] = Request({requester: requester, shares: shares});

        uint256 assets = IERC4626(WSGETH).previewRedeem(totalPendingRequest);
        if (assets >= REDEEM_THRESOLD) {
            uint256 i = requestFront;
            requestFront = requestBack;
            for (; i < requestFront; ) {
                claimableRedeemRequest[requests[i].requester] += requests[i].shares;

                unchecked {
                    ++i;
                }
            }
            totalPendingRequest = 0;
        }

        emit RedeemRequest(requester, owner, requestId, msg.sender, shares);
        return requestId;
    }

    /**
     * Include some arbitrary transition logic here from Pending to Claimable
     */

    function redeem(
        uint256 shares,
        address receiver,
        address requester
    ) external onlyOwnerOrOperator(requester) nonReentrant returns (uint256 assets) {
        if (shares == 0) {
            revert InvalidAmount();
        }

        claimableRedeemRequest[requester] -= shares; // underflow would revert if not enough claimable shares

        assets = IERC4626(WSGETH).previewRedeem(shares);

        uint256 queueBalance = address(this).balance;
        uint256 minterBalance = address(MINTER).balance;

        if (queueBalance + minterBalance < assets) {
            revert InsufficientBalance();
        }

        if (assets <= queueBalance) {
            payable(receiver).transfer(assets);
        } else {
            payable(receiver).transfer(queueBalance);
            uint256 remainingShares = IERC4626(WSGETH).convertToShares(assets - queueBalance);
            MINTER.unstakeAndWithdraw(remainingShares, receiver);
        }

        emit Redeem(requester, receiver, shares, assets);
    }

    function setOperator(address operator, bool approved) public returns (bool) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function pendingRedeemRequest(address requester) public view returns (uint256 shares) {
        for (uint256 i = requestFront; i < requestBack; ) {
            if (requests[i].requester == requester) {
                shares += requests[i].shares;
            }
            unchecked {
                ++i;
            }
        }
    }

    receive() external payable {} // solhint-disable-line
    fallback() external payable {} // solhint-disable-line
}
