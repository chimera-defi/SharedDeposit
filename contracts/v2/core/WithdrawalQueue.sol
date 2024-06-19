// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {FIFOQueue} from "../../lib/FIFOQueue.sol";
import {Errors} from "../../lib/Errors.sol";
import {SharedDepositMinterV2} from "./SharedDepositMinterV2.sol";

// ERC-7540 inspired withdrawal contract
// This contract is designed to be used with SharedDepositMinterV2 contract
// As a module extension that adds 7540 methods requestRedeem and redeem
// Example flow ->
contract WithdrawalQueue is AccessControl, Pausable, ReentrancyGuard, FIFOQueue {
    struct Request {
        address requester;
        uint256 shares;
    }
    SharedDepositMinterV2 public immutable MINTER;
    address public immutable WSGETH;

    uint256 internal totalPendingRequest;
    uint256 internal requestsPending;
    uint256 internal requestsFulfilled;
    uint256 public totalOut;

    bytes32 public constant GOV = keccak256("GOV"); // Governance for settings - normally timelock controlled by multisig

    mapping(uint256 => Request) internal requests;
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

    modifier onlyOwnerOrOperator(address owner) {
        if (owner != msg.sender && !isOperator[owner][msg.sender]) {
            revert Errors.PermissionDenied();
        }
        _;
    }

    modifier checkWithdraw(address owner, uint256 amt) {
        uint256 totalBalance = address(this).balance + address(MINTER).balance;
        if (_checkWithdraw(msg.sender, totalBalance, amt)) {
            _;
        }
    }

    constructor(address _minter, address _wsgEth, uint256 _epochLength) FIFOQueue(_epochLength) {
        MINTER = SharedDepositMinterV2(_minter);
        WSGETH = _wsgEth;

        uint256 maxUint256 = 2 ** 256 - 1;

        IERC20(WSGETH).approve(_minter, maxUint256);

        _grantRole(GOV, msg.sender);
    }

    function requestRedeem(
        uint256 shares,
        address requester,
        address owner
    ) external onlyOwnerOrOperator(owner) nonReentrant whenNotPaused returns (uint256 requestId) {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }

        requestId = requestsPending++;
        requests[requestId] = Request({requester: requester, shares: shares});

        IERC20(WSGETH).transferFrom(owner, address(this), shares); // asset here is the Vault underlying asset
        _stakeForWithdrawal(owner, shares);
        totalPendingRequest += shares;
        if (requester != owner) {
            isOperator[owner][requester] = true;
        }
        claimableRedeemRequest[requester] += shares; // underflow would revert if not enough claimable shares

        emit RedeemRequest(requester, owner, requestId, msg.sender, shares);
        return requestId;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address requester
    )
        external
        onlyOwnerOrOperator(requester)
        checkWithdraw(receiver, shares)
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        if (shares == 0) {
            revert Errors.InvalidAmount();
        }

        claimableRedeemRequest[requester] -= shares; // underflow would revert if not enough claimable shares
        totalPendingRequest -= shares;
        assets = IERC4626(WSGETH).previewRedeem(shares);

        uint256 queueBalance = address(this).balance;
        uint256 minterBalance = address(MINTER).balance;

        if (queueBalance + minterBalance < assets) {
            revert Errors.InsufficientBalance();
        }

        // Track total returned
        totalOut += assets;
        requestsFulfilled++;
        // This feels suboptimal, but is the easiest way to always burn the token on redemptions
        if (assets > minterBalance) {
            uint256 diff = assets - minterBalance;
            payable(address(MINTER)).transfer(diff);
        }
        // Always burn redeemed tokens
        MINTER.unstakeAndWithdraw(shares, receiver);

        emit Redeem(requester, receiver, shares, assets);
    }

    function setOperator(address operator, bool approved) external returns (bool) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function togglePause() external onlyRole(GOV) {
        bool paused = paused();
        if (paused) {
            _unpause();
        } else {
            _pause();
        }
    }

    function pendingRedeemRequest(uint256 requestId, address owner) public view returns (uint256 shares) {
        if (requests[requestId].requester == owner) {
            return requests[requestId].shares;
        }
        return 0;
    }

    receive() external payable {} // solhint-disable-line

    fallback() external payable {} // solhint-disable-line
}
