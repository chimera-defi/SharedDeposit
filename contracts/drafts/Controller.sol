pragma solidity 0.8.20;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Controller is Ownable {
  struct Settings {
    address _addr;
    uint256 _val;
  }
  mapping(string => Settings) public settingsMap;
  // Settings public settings;
  Settings[] public settingsArr;

  constructor(
    address[] memory addresses,
    uint256[] memory vals,
    string[] memory names
  ) Ownable() {
    uint256 i = vals.length;
    while (i > 0) {
      unchecked {
        --i;
        _setSetting(names[i], addresses[i], vals[i]);
      }
    }
  }

  function get(string calldata name) public returns (address _a, uint256 _v) {
    Settings memory _s = settingsMap[name];
    _a = _s._addr;
    _v = _s._val;
  }

  function _setSetting(
    string memory name,
    address addr,
    uint256 val
  ) internal {
    Settings memory _s = Settings({_addr: addr, _val: val});

    settingsMap[name] = _s;
  }
}
