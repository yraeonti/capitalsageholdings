// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {InstitutionalVault} from "../src/InstitutionalVault.sol";
import {InstitutionalVaultV2} from "./mocks/InstitutionalVaultV2.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {VaultDeployer} from "./utils/VaultDeployer.sol";

contract UpgradeTest is VaultDeployer {
    MockERC20 internal usdc;
    InstitutionalVault internal vault;
    address internal alice = makeAddr("alice");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = _deployVault(usdc, 100, type(uint256).max);
        usdc.mint(alice, 10_000e6);
        vm.startPrank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e6, alice);
        vm.stopPrank();
    }

    function test_upgrade_preservesStateAndBalances() public {
        uint256 shares = vault.balanceOf(alice);
        uint256 assets = vault.totalAssets();
        address impl = address(new InstitutionalVaultV2());

        vm.prank(upgrader);
        vault.upgradeToAndCall(impl, "");

        assertEq(InstitutionalVaultV2(address(vault)).version(), 2);
        assertEq(address(uint160(uint256(vm.load(address(vault), ERC1967Utils.IMPLEMENTATION_SLOT)))), impl);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), assets);
        assertEq(vault.depositFeeBps(), 100);
        assertEq(vault.feeRecipient(), treasury);
        assertTrue(vault.hasRole(vault.PAUSER_ROLE(), pauser));
    }

    function test_upgrade_onlyUpgrader() public {
        address impl = address(new InstitutionalVaultV2());
        bytes32 role = vault.UPGRADER_ROLE();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, role));
        vault.upgradeToAndCall(impl, "");
    }

    function test_upgrade_worksWhilePaused() public {
        vm.prank(pauser);
        vault.pause();
        address impl = address(new InstitutionalVaultV2());

        vm.prank(upgrader);
        vault.upgradeToAndCall(impl, "");

        assertTrue(vault.paused());
    }

    function test_upgrade_rejectsNonUUPSImplementation() public {
        vm.prank(upgrader);
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(usdc)));
        vault.upgradeToAndCall(address(usdc), "");
    }

    function test_upgrade_implementationRejectsDirectCall() public {
        address impl = address(uint160(uint256(vm.load(address(vault), ERC1967Utils.IMPLEMENTATION_SLOT))));
        address next = address(new InstitutionalVaultV2());

        vm.prank(upgrader);
        vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
        InstitutionalVault(impl).upgradeToAndCall(next, "");
    }
}
