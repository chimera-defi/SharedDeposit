// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {ValidatorModule} from "./ValidatorModule.sol";

/// @title DVTModule - Distributed Validator Technology variant of ValidatorModule
/// @notice Distributed Validator Technology (DVT — e.g. Obol, SSV) is a different
///         operator topology, not a different accounting model. The economic flow
///         (buffer ETH, push to beacon, oracle reports balance, router rebases)
///         is identical to a solo-validator setup. We override `moduleType()` so
///         off-chain tooling can distinguish DVT validators from solo, and reserve
///         this contract as the integration point for cluster-coordinator hooks
///         (operator whitelist, threshold-signature pre-flight, etc.) in Phase 2.
contract DVTModule is ValidatorModule {
    constructor(address router, bytes32 moduleId, address gov, address beaconDepositContract)
        ValidatorModule(router, moduleId, gov, beaconDepositContract)
    {}

    function moduleType() external pure override returns (bytes32) {
        return keccak256("DVT_VALIDATOR");
    }
}
