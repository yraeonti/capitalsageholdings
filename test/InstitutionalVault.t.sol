// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlDefaultAdminRules} from
    "@openzeppelin/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {InstitutionalVault} from "../src/InstitutionalVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {VaultDeployer} from "./utils/VaultDeployer.sol";

contract InstitutionalVaultTest is VaultDeployer {
    MockERC20 internal usdc;
    InstitutionalVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint16 internal constant FEE_BPS = 100;
    uint256 internal constant CAP = 1_000_000e6;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = _deployVault(usdc, FEE_BPS, CAP);
        _fund(alice, 100_000e6);
        _fund(bob, 100_000e6);
    }

    function _fund(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _deposit(address user, uint256 assets) internal returns (uint256) {
        vm.prank(user);
        return vault.deposit(assets, user);
    }

    function test_initialize_seedsDeadShares() public view {
        assertEq(vault.totalAssets(), SEED);
        assertEq(vault.balanceOf(address(0xdead)), vault.totalSupply());
        assertEq(vault.decimals(), 6 + 6);
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_revertsOnProxyReinit() public {
        InstitutionalVault.InitParams memory p;
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(p);
    }

    function test_initialize_implementationIsLocked() public {
        InstitutionalVault impl = new InstitutionalVault();
        InstitutionalVault.InitParams memory p;
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(p);
    }

    function test_initialize_revertsOnZeroSeed() public {
        InstitutionalVault impl = new InstitutionalVault();
        InstitutionalVault.InitParams memory p = _params(0);
        vm.expectRevert(InstitutionalVault.ZeroAmount.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, (p)));
    }

    function test_initialize_revertsOnZeroAdmin() public {
        InstitutionalVault impl = new InstitutionalVault();
        InstitutionalVault.InitParams memory p = _params(SEED);
        p.admin = address(0);
        vm.expectRevert(InstitutionalVault.InvalidAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, (p)));
    }

    function _params(uint256 seed) internal view returns (InstitutionalVault.InitParams memory) {
        return InstitutionalVault.InitParams({
            asset: IERC20(address(usdc)),
            name: "V",
            symbol: "V",
            admin: admin,
            adminTransferDelay: ADMIN_DELAY,
            feeRecipient: treasury,
            depositFeeBps: FEE_BPS,
            depositCap: CAP,
            seedAssets: seed
        });
    }

    function test_deposit_chargesFeeOnNetAndMintsPreviewedShares() public {
        uint256 gross = 10_100e6;
        uint256 expectedShares = vault.previewDeposit(gross);

        uint256 shares = _deposit(alice, gross);

        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(usdc.balanceOf(treasury), 100e6);
        assertEq(vault.totalAssets(), SEED + 10_000e6);
        assertApproxEqAbs(vault.convertToAssets(shares), 10_000e6, 1);
        assertLe(vault.convertToAssets(shares), 10_000e6);
    }

    function test_mint_chargesFeeOnTopOfNetAssets() public {
        uint256 shares = vault.convertToShares(10_000e6);
        uint256 expectedAssets = vault.previewMint(shares);
        uint256 before = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.mint(shares, alice);

        assertEq(assets, expectedAssets);
        assertEq(before - usdc.balanceOf(alice), assets);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(usdc.balanceOf(treasury), assets - (vault.totalAssets() - SEED));
        assertEq(usdc.balanceOf(treasury), 100e6);
    }

    function test_withdraw_burnsPreviewedSharesWithoutFee() public {
        _deposit(alice, 10_100e6);
        uint256 expectedShares = vault.previewWithdraw(5_000e6);
        uint256 sharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 burned = vault.withdraw(5_000e6, alice, alice);

        assertEq(burned, expectedShares);
        assertEq(sharesBefore - vault.balanceOf(alice), burned);
        assertEq(usdc.balanceOf(alice), 100_000e6 - 10_100e6 + 5_000e6);
        assertEq(usdc.balanceOf(treasury), 100e6);
    }

    function test_redeem_paysPreviewedAssetsWithoutFee() public {
        uint256 shares = _deposit(alice, 10_100e6);
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), 0);
        assertApproxEqAbs(assets, 10_000e6, 1);
        assertLe(assets, 10_000e6);
    }

    function test_redeem_byApprovedOperatorSpendsAllowance() public {
        uint256 shares = _deposit(alice, 10_100e6);
        vm.prank(alice);
        vault.approve(bob, shares);

        vm.prank(bob);
        vault.redeem(shares, bob, alice);

        assertEq(vault.allowance(alice, bob), 0);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_yield_raisesShareValueForHolders() public {
        uint256 shares = _deposit(alice, 10_100e6);
        usdc.mint(address(vault), 1_000e6);

        assertGt(vault.previewRedeem(shares), 10_000e6);
    }

    function test_fee_zeroBpsTakesNothing() public {
        vm.prank(feeManager);
        vault.setDepositFee(0);
        _deposit(alice, 10_000e6);
        assertEq(usdc.balanceOf(treasury), 0);
        assertEq(vault.totalAssets(), SEED + 10_000e6);
    }

    function test_fee_maxBpsIsFivePercentOfNet() public {
        vm.prank(feeManager);
        vault.setDepositFee(500);
        _deposit(alice, 10_500e6);
        assertEq(usdc.balanceOf(treasury), 500e6);
        assertEq(vault.totalAssets(), SEED + 10_000e6);
    }

    function test_fee_maxBpsRoundsUpOnUnevenAmount() public {
        vm.prank(feeManager);
        vault.setDepositFee(500);
        _deposit(alice, 1_000e6);
        // 1000e6 * 500 / 10500 = 47_619_047.6 -> ceil
        assertEq(usdc.balanceOf(treasury), 47_619_048);
    }

    function test_fee_depositFullyConsumedByFeeReverts() public {
        vm.prank(alice);
        vm.expectRevert(InstitutionalVault.ZeroAmount.selector);
        vault.deposit(1, alice);
    }

    function testFuzz_fee_depositNeverUndercharges(uint256 gross, uint16 bps) public {
        gross = bound(gross, 2, 100_000e6);
        bps = uint16(bound(bps, 0, 500));
        vm.prank(feeManager);
        vault.setDepositFee(bps);

        _deposit(alice, gross);

        uint256 fee = usdc.balanceOf(treasury);
        uint256 net = gross - fee;
        assertGe(fee * 10_000, net * bps);
        assertLe(fee, gross * bps / (10_000 + bps) + 1);
    }

    function testFuzz_fee_mintPathFeeEqualsFeeOnRaw(uint256 shares, uint16 bps) public {
        shares = bound(shares, 1e6, vault.convertToShares(90_000e6));
        bps = uint16(bound(bps, 0, 500));
        vm.prank(feeManager);
        vault.setDepositFee(bps);

        uint256 net = _netForMint(shares);
        uint256 expectedFee = (net * bps + 9_999) / 10_000;

        vm.prank(alice);
        vault.mint(shares, alice);

        assertEq(usdc.balanceOf(treasury), expectedFee);
    }

    function _netForMint(uint256 shares) internal view returns (uint256) {
        uint256 supply = vault.totalSupply() + 1e6;
        uint256 assets = vault.totalAssets() + 1;
        return (shares * assets + supply - 1) / supply;
    }

    function testFuzz_rounding_depositRedeemNeverProfits(uint256 assets) public {
        assets = bound(assets, 1, 100_000e6);
        vm.prank(feeManager);
        vault.setDepositFee(0);

        uint256 shares = _deposit(alice, assets);
        vm.prank(alice);
        uint256 out = vault.redeem(shares, alice, alice);

        assertLe(out, assets);
    }

    function testFuzz_rounding_mintWithdrawNeverProfits(uint256 shares) public {
        shares = bound(shares, 1e6, vault.convertToShares(90_000e6));
        vm.prank(feeManager);
        vault.setDepositFee(0);

        uint256 start = usdc.balanceOf(alice);
        vm.startPrank(alice);
        uint256 paid = vault.mint(shares, alice);
        uint256 out = vault.maxWithdraw(alice);
        vault.withdraw(out, alice, alice);
        vm.stopPrank();

        assertLe(out, paid);
        assertLe(usdc.balanceOf(alice), start);
    }

    function test_rounding_previewsFavorVault() public {
        usdc.mint(address(vault), 333_333);
        uint256 a = 1_234_567;
        uint256 s = vault.convertToShares(a);
        vm.prank(feeManager);
        vault.setDepositFee(0);

        assertLe(vault.previewDeposit(a), s);
        assertGe(vault.previewMint(s), vault.convertToAssets(s));
        assertGe(vault.previewWithdraw(a), s);
        assertLe(vault.previewRedeem(s), vault.convertToAssets(s));
    }

    function test_zero_depositReverts() public {
        vm.prank(alice);
        vm.expectRevert(InstitutionalVault.ZeroAmount.selector);
        vault.deposit(0, alice);
    }

    function test_zero_mintReverts() public {
        vm.prank(alice);
        vm.expectRevert(InstitutionalVault.ZeroAmount.selector);
        vault.mint(0, alice);
    }

    function test_zero_withdrawReverts() public {
        vm.prank(alice);
        vm.expectRevert(InstitutionalVault.ZeroAmount.selector);
        vault.withdraw(0, alice, alice);
    }

    function test_zero_redeemReverts() public {
        vm.prank(alice);
        vm.expectRevert(InstitutionalVault.ZeroAmount.selector);
        vault.redeem(0, alice, alice);
    }

    function test_zero_redeemOfDustThatPaysNothingReverts() public {
        _deposit(alice, 10_100e6);
        assertEq(vault.previewRedeem(1), 0);

        vm.prank(alice);
        vm.expectRevert(InstitutionalVault.ZeroAmount.selector);
        vault.redeem(1, alice, alice);
    }

    function test_pause_blocksAllFlowsAndZeroesMax() public {
        uint256 shares = _deposit(alice, 10_100e6);
        vm.prank(pauser);
        vault.pause();

        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxMint(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);

        vm.startPrank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.deposit(1e6, alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.mint(1e6, alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.withdraw(1e6, alice, alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vault.redeem(shares, alice, alice);
        vm.stopPrank();
    }

    function test_pause_onlyAdminCanUnpause() public {
        vm.prank(pauser);
        vault.pause();

        bytes32 role = vault.DEFAULT_ADMIN_ROLE();
        vm.prank(pauser);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, pauser, role));
        vault.unpause();

        vm.prank(admin);
        vault.unpause();
        _deposit(alice, 1e6);
    }

    function test_pause_onlyPauserCanPause() public {
        bytes32 role = vault.PAUSER_ROLE();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, role));
        vault.pause();
    }

    function test_setDepositFee_revertsAboveCap() public {
        vm.prank(feeManager);
        vm.expectRevert(abi.encodeWithSelector(InstitutionalVault.FeeTooHigh.selector, 501));
        vault.setDepositFee(501);
    }

    function test_setDepositFee_emitsAndUpdates() public {
        vm.expectEmit(address(vault));
        emit InstitutionalVault.DepositFeeUpdated(FEE_BPS, 250);
        vm.prank(feeManager);
        vault.setDepositFee(250);
        assertEq(vault.depositFeeBps(), 250);
    }

    function test_setDepositFee_onlyFeeManager() public {
        bytes32 role = vault.FEE_MANAGER_ROLE();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, role));
        vault.setDepositFee(1);
    }

    function test_setFeeRecipient_rejectsZeroAndSelf() public {
        vm.startPrank(feeManager);
        vm.expectRevert(InstitutionalVault.InvalidAddress.selector);
        vault.setFeeRecipient(address(0));
        vm.expectRevert(InstitutionalVault.InvalidAddress.selector);
        vault.setFeeRecipient(address(vault));
        vault.setFeeRecipient(bob);
        vm.stopPrank();
        assertEq(vault.feeRecipient(), bob);
    }

    function test_setDepositCap_onlyAdmin() public {
        bytes32 role = vault.DEFAULT_ADMIN_ROLE();
        vm.prank(feeManager);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, feeManager, role)
        );
        vault.setDepositCap(1);
    }

    function test_defaultAdminTransfer_enforcesDelay() public {
        vm.prank(admin);
        vault.beginDefaultAdminTransfer(bob);

        (, uint48 schedule) = vault.pendingDefaultAdmin();
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminDelay.selector, schedule
            )
        );
        vault.acceptDefaultAdminTransfer();

        vm.warp(schedule + 1);
        vm.prank(bob);
        vault.acceptDefaultAdminTransfer();
        assertEq(vault.defaultAdmin(), bob);
    }

    function test_cap_maxDepositIsRemainingRoom() public {
        _deposit(alice, 10_100e6);
        assertEq(vault.maxDeposit(alice), CAP - vault.totalAssets());
    }

    function test_cap_depositAboveRoomReverts() public {
        vm.prank(admin);
        vault.setDepositCap(SEED + 5_000e6);
        uint256 room = vault.maxDeposit(alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector, alice, room + 1, room)
        );
        vault.deposit(room + 1, alice);

        _deposit(alice, room);
        assertLe(vault.totalAssets(), vault.depositCap());
    }

    function test_cap_mintAtMaxStaysUnderCap() public {
        vm.prank(admin);
        vault.setDepositCap(SEED + 5_000e6);
        uint256 maxShares = vault.maxMint(alice);

        vm.prank(alice);
        vault.mint(maxShares, alice);

        assertLe(vault.totalAssets(), vault.depositCap());
    }

    function test_cap_belowTotalAssetsReturnsZeroWithoutRevert() public {
        _deposit(alice, 10_100e6);
        vm.prank(admin);
        vault.setDepositCap(1);
        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxMint(alice), 0);
    }

    function test_cap_unlimitedReturnsMax() public {
        vm.prank(admin);
        vault.setDepositCap(type(uint256).max);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);
    }
}
