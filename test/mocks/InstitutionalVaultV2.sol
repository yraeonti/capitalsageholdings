// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {InstitutionalVault} from "../../src/InstitutionalVault.sol";

contract InstitutionalVaultV2 is InstitutionalVault {
    function version() external pure returns (uint256) {
        return 2;
    }
}
