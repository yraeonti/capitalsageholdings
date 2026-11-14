// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {InstitutionalVault} from "../../src/InstitutionalVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {VaultDeployer} from "../utils/VaultDeployer.sol";
import {VaultHandler} from "./VaultHandler.sol";

contract VaultInvariantsTest is VaultDeployer {
    MockERC20 internal usdc;
    InstitutionalVault internal vault;
    VaultHandler internal handler;
    uint256 internal deadShares;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = _deployVault(usdc, 100, type(uint256).max);
        handler = new VaultHandler(vault, usdc, feeManager);
        deadShares = vault.balanceOf(address(0xdead));
        targetContract(address(handler));
    }

    function invariant_solvent() public view {
        assertLe(vault.previewRedeem(vault.totalSupply()), usdc.balanceOf(address(vault)));
    }

    function invariant_sharePriceNeverDecreases() public view {
        assertFalse(handler.priceDecreased());
    }

    function invariant_feesMatchIndependentFormula() public view {
        assertEq(usdc.balanceOf(treasury), handler.expectedFees());
        assertLe(vault.depositFeeBps(), vault.MAX_FEE_BPS());
    }

    function invariant_supplyIsSumOfHoldersAndDeadSharesAreLocked() public view {
        uint256 sum = vault.balanceOf(address(0xdead));
        for (uint256 i; i < handler.actorCount(); ++i) {
            sum += vault.balanceOf(handler.actors(i));
        }
        assertEq(sum, vault.totalSupply());
        assertEq(vault.balanceOf(address(0xdead)), deadShares);
    }
}
