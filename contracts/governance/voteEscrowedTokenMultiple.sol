// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VoteEscrowedToken is ERC20Votes, Ownable {
    using SafeERC20 for IERC20;

    struct LockedBalance {
        mapping(address => uint256) amounts;
        uint256 end;
    }

    // flags
    uint256 private _unlocked;

    uint256 public constant MINDAYS = 7;
    uint256 public constant MAXDAYS = 3 * 365;

    uint256 public constant MAXTIME = MAXDAYS * 1 days; // 3 years
    uint256 public constant MAX_WITHDRAWAL_PENALTY = 50000; // 50%
    uint256 public constant PRECISION = 100000; // 5 decimals
    uint256 public constant MAX_BOOST = 10; // boost of 10 equals a 1:1 conversion in max time

    address public penaltyCollector;
    uint256 public minLockedAmount;
    uint256 public earlyWithdrawPenaltyRate;

    // User => Token => lockedBal
    mapping(address => LockedBalance) public locked;
    mapping(address => uint256) public mintedForLock;

    mapping(address => uint256) public underlyingTokensToBoost;
    address[] public underlyingTokens;
    uint256 public boostedTokens;

    /* ========== MODIFIERS ========== */

    modifier lock() {
        require(_unlocked == 1, "LOCKED");
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _minLockedAmount
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        minLockedAmount = _minLockedAmount;
        earlyWithdrawPenaltyRate = 30000; // 30%
        _unlocked = 1;

        address _dummyToken = address(0x0000000000000000000000000000000000000000);
        underlyingTokensToBoost[_dummyToken] = 0;
        underlyingTokens[boostedTokens] = _dummyToken;
        boostedTokens = boostedTokens + 1;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function locked__of(address _addr, address _token) external view returns (uint256) {
        return locked[_addr].amounts[_token];
    }

    function locked__end(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    function voting_power_unlock_time(
        uint256 _value,
        uint256 _unlockTime,
        address _token
    ) public view returns (uint256) {
        uint256 _now = block.timestamp;
        if (_unlockTime <= _now) return 0;
        uint256 _lockedSeconds = _unlockTime - _now;
        uint256 _boost = underlyingTokensToBoost[_token];
        if (_lockedSeconds >= MAXTIME) {
            return (_value * _boost) / MAX_BOOST;
        }
        return (_value * _lockedSeconds * _boost) / (MAXTIME * MAX_BOOST);
    }

    function voting_power_locked_days(
        uint256 _value,
        uint256 _days,
        address _token
    ) public view returns (uint256) {
        if (_days >= MAXDAYS) {
            return _value;
        }
        return (_value * _days * underlyingTokensToBoost[_token]) / (MAXDAYS * MAX_BOOST);
    }

    function deposit_for(
        address _addr,
        uint256 _value,
        address _token
    ) external {
        require(_value >= minLockedAmount, "less than min amount");
        _deposit_for(_addr, _value, 0, _token);
    }

    function create_lock(
        uint256 _value,
        uint256 _days,
        address _token
    ) external {
        require(_value >= minLockedAmount, "less than min amount");
        require(locked[_msgSender()].amounts[_token] == 0, "Withdraw old tokens first");
        require(_days >= MINDAYS, "Voting lock can be 7 days min");
        require(_days <= MAXDAYS, "Voting lock can be 4 years max");
        _deposit_for(_msgSender(), _value, _days, _token);
    }

    function increase_amount(uint256 _value, address _token) external {
        require(_value >= minLockedAmount, "less than min amount");
        _deposit_for(_msgSender(), _value, 0, _token);
    }

    function increase_unlock_time(uint256 _days) external {
        require(_days >= MINDAYS, "Voting lock can be 7 days min");
        require(_days <= MAXDAYS, "Voting lock can be 4 years max");
        _deposit_for(_msgSender(), 0, _days, 0x0000000000000000000000000000000000000000);
    }

    function withdraw() external lock {
        _transfer_all();
        // LockedBalance storage _locked = locked[_msgSender()];
        // uint256 _now = block.timestamp;
        // require(_locked.amount > 0, "Nothing to withdraw");
        // require(_now >= _locked.end, "The lock didn't expire");
        // uint256 _amount = _locked.amount;
        // _locked.end = 0;
        // _locked.amount = 0;
        // _burn(_msgSender(), mintedForLock[_msgSender()]);
        // mintedForLock[_msgSender()] = 0;
        // IERC20(lockedToken).safeTransfer(_msgSender(), _amount);

        // emit Withdraw(_msgSender(), _amount, _now);
    }

    // This will charge PENALTY if lock is not expired yet
    function emergencyWithdraw() external lock {
        _transfer_all();
        // LockedBalance storage _locked = locked[_msgSender()];
        // uint256 _now = block.timestamp;
        // require(_locked.amount > 0, "Nothing to withdraw");
        // uint256 _amount = _locked.amount;
        // if (_now < _locked.end) {
        //     uint256 _fee = _amount * earlyWithdrawPenaltyRate / PRECISION;
        //     _penalize(_fee);
        //     _amount = _amount - _fee;
        // }
        // _locked.end = 0;
        // _locked.amount = 0;
        // _burn(_msgSender(), mintedForLock[_msgSender()]);
        // mintedForLock[_msgSender()] = 0;

        // IERC20(lockedToken).safeTransfer(_msgSender(), _amount);

        // emit Withdraw(_msgSender(), _amount, _now);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _transfer_all() internal {
        LockedBalance storage _locked = locked[_msgSender()];
        uint256 _now = block.timestamp;

        uint256 _mintedForLock = mintedForLock[_msgSender()];
        _burn(_msgSender(), _mintedForLock);
        mintedForLock[_msgSender()] = 0;

        address _token;
        uint256 _amount;
        for (uint256 i = 0; i < boostedTokens; i++) {
            _token = underlyingTokens[i];
            _amount = _locked.amounts[_token];
            if (_now < _locked.end) {
                uint256 _fee = (_amount * earlyWithdrawPenaltyRate) / PRECISION;
                _penalize(_fee, _token);
                _amount = _amount - _fee;
            }
            _locked.amounts[_token] = 0;
            IERC20(_token).safeTransfer(_msgSender(), _amount);
        }

        _locked.end = 0;
        emit Withdraw(_msgSender(), _mintedForLock, _now);
    }

    // function _check_all()

    function _deposit_for(
        address _addr,
        uint256 _value,
        uint256 _days,
        address _token
    ) internal lock {
        LockedBalance storage _locked = locked[_addr];
        uint256 _now = block.timestamp;
        uint256 _amount = _locked.amounts[_token];
        uint256 _end = _locked.end;
        uint256 _vp;
        if (_amount == 0) {
            _vp = voting_power_locked_days(_value, _days, _token);
            _locked.amounts[_token] = _value;
            _locked.end = _now + _days * 1 days;
        } else if (_days == 0) {
            _vp = voting_power_unlock_time(_value, _end, _token);
            _locked.amounts[_token] = _amount + _value;
        } else {
            require(_value == 0, "Cannot increase amount and extend lock in the same time");
            _vp = voting_power_locked_days(_amount, _days, _token);
            _locked.end = _end + _days * 1 days;
            require(_locked.end - _now <= MAXTIME, "Cannot extend lock to more than 4 years");
        }
        require(_vp > 0, "No benefit to lock");
        if (_value > 0) {
            IERC20(_token).safeTransferFrom(_msgSender(), address(this), _value);
        }
        _mint(_addr, _vp);
        mintedForLock[_addr] += _vp;

        emit Deposit(_addr, _locked.amounts[_token], _locked.end, _now);
    }

    function _penalize(uint256 _amount, address _token) internal {
        if (penaltyCollector != address(0)) {
            // send to collector if `penaltyCollector` set
            IERC20(_token).safeTransfer(penaltyCollector, _amount);
        } else {
            ERC20Burnable(_token).burn(_amount);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Allow users to vote escrow LP positions of various types
    function addUnderlying(address _token, uint256 _boost) external onlyOwner {
        require(_boost <= MAX_BOOST, "Boost too high");
        underlyingTokensToBoost[_token] = _boost;
        boostedTokens = boostedTokens + 1;
    }

    function setMinLockedAmount(uint256 _minLockedAmount) external onlyOwner {
        minLockedAmount = _minLockedAmount;
        emit MinLockedAmountSet(_minLockedAmount);
    }

    function setEarlyWithdrawPenaltyRate(uint256 _earlyWithdrawPenaltyRate) external onlyOwner {
        require(_earlyWithdrawPenaltyRate <= MAX_WITHDRAWAL_PENALTY, "withdrawal penalty is too high"); // <= 50%
        earlyWithdrawPenaltyRate = _earlyWithdrawPenaltyRate;
        emit EarlyWithdrawPenaltySet(_earlyWithdrawPenaltyRate);
    }

    function setPenaltyCollector(address _addr) external onlyOwner {
        penaltyCollector = _addr;
        emit PenaltyCollectorSet(_addr);
    }

    /* =============== EVENTS ==================== */
    event Deposit(address indexed provider, uint256 value, uint256 locktime, uint256 timestamp);
    event Withdraw(address indexed provider, uint256 value, uint256 timestamp);
    event PenaltyCollectorSet(address indexed addr);
    event EarlyWithdrawPenaltySet(uint256 indexed penalty);
    event MinLockedAmountSet(uint256 indexed amount);
}
