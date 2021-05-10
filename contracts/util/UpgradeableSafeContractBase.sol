// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract UpgradeableSafeContractBase is Initializable, ContextUpgradeable, AccessControlEnumerableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using AddressUpgradeable for address;

    function __UpgradeableSafeContractBase_init() internal initializer {
        __UpgradeableSafeContractBase_init_unchained();
    }

    function __UpgradeableSafeContractBase_init_unchained() internal initializer {
        __Context_init_unchained();
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();
    }

    // Inspired by alchemix smart contract gaurd at https://github.com/alchemix-finance/alchemix-protocol/blob/master/contracts/Alchemist.sol#L680
    /// @dev Checks that caller is a EOA.
    ///
    /// This is used to prevent contracts from interacting.
    modifier noContractAllowed() {
        require(!address(_msgSender()).isContract() && _msgSender() == tx.origin, "Sorry we do not accept contracts!");
        _;
    }

    uint256[50] private ______gap;
}