// SPDX-License-Identifier: UNLICENSED

// based on ref code from gnt
pragma solidity 0.8.7;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../interfaces/IBlocklist.sol";

// Allows user to migrate from old token to new token by burning the old token

struct SwapRecord {
    uint256 amount;
    uint256 unlock_timestamp;
}

contract TokenMigrator is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    ERC20Burnable public target;
    IERC20 public oldToken;
    IBlocklist private _blocklist;
    uint256 public startTime;
    // address public constant burn = 0x000000000000000000000000000000000000dEaD;

    mapping(address => SwapRecord) public lockedSwaps;

    event TargetChanged(ERC20Burnable previousTarget, ERC20Burnable changedTarget);
    event BlocklistChanged(IBlocklist previousTarget, IBlocklist changedTarget);
    event SwapLocked(address from, uint256 value, uint256 unlock_timestamp);
    event Migrated(address from, address to, ERC20Burnable target, uint256 value);

    constructor(
        IERC20 _oldToken,
        ERC20Burnable _target,
        IBlocklist bl
    ) public {
        require(address(_oldToken) != address(0), "FD:0AD");
        oldToken = _oldToken;
        _blocklist = bl;
        target = _target;
        startTime = block.timestamp;
    }

    function migrate(uint256 _value) external {
        oldToken.transferFrom(msg.sender, 0x000000000000000000000000000000000000dEaD, _value);

        SwapRecord memory existingSwap = lockedSwaps[msg.sender];
        existingSwap.amount += _value;
        existingSwap.unlock_timestamp = block.timestamp + 5 days;
        lockedSwaps[msg.sender] = existingSwap;
        emit SwapLocked(msg.sender, _value, existingSwap.unlock_timestamp);
    }

    function releaseTokens() external {
        require(address(target) != address(0), "FD:0AD");

        SwapRecord memory existingSwap = lockedSwaps[msg.sender];
        if (existingSwap.amount > 0 && block.timestamp >= existingSwap.unlock_timestamp) {

            delete lockedSwaps[msg.sender];

            if (address(_blocklist) != address(0) && _blocklist.inBlockList(msg.sender)) {
                target.transfer(owner(), existingSwap.amount);
                emit Migrated(msg.sender, owner(), target, existingSwap.amount);
            } else {
                target.transfer(msg.sender, existingSwap.amount);
                emit Migrated(msg.sender, msg.sender, target, existingSwap.amount);
            }
        }
    }

    function setTarget(ERC20Burnable _target) external onlyOwner {
        emit TargetChanged(target, _target);
        target = _target;
    }

    function setBlocklist(IBlocklist bl) external onlyOwner {
        emit BlocklistChanged(_blocklist, bl);
        _blocklist = bl;
    }

    // Based on community advice. once a preset epoch of 1-2 mos expired,
    // all tokens in the contract
    // should be burnt. this will reduce circulating supply and
    // reassure the community of limited dilution
    function burnAll() external onlyOwner {
        require((startTime + 60 days) < block.timestamp, "TM:Too early");
        target.burn(target.balanceOf(address(this)));
    }
}
