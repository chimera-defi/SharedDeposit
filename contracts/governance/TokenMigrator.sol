// ref code from gnt
pragma solidity 0.8.7;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../interfaces/IBlocklist.sol";

// Allows user to migrate from old token to new token by burning the old token

contract TokenMigrator is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    ERC20Burnable public target;
    IERC20 public oldToken;
    IBlocklist private _blocklist;

    mapping(address => uint256) public migratedForHolder;

    event TargetChanged(ERC20Burnable previousTarget, ERC20Burnable changedTarget);
    event BlocklistChanged(IBlocklist previousTarget, IBlocklist changedTarget);
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
    }

    function migrateFrom(address _from, uint256 _value) external {
        require(address(target) != address(0), "FD:0AD");

        oldToken.transferFrom(msg.sender, address(0), _value);
        if (address(_blocklist) != address(0) && _blocklist.inBlockList(msg.sender)) {
            target.burn(_value);
            emit Migrated(_from, address(0), target, _value);
        } else {
            target.transfer(msg.sender, _value);
            emit Migrated(_from, msg.sender, target, _value);
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
}
