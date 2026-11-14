// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InstitutionalVault} from "../../src/InstitutionalVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

abstract contract VaultDeployer is Test {
    uint256 internal constant SEED = 1e6;
    uint48 internal constant ADMIN_DELAY = 2 days;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal feeManager = makeAddr("feeManager");
    address internal upgrader = makeAddr("upgrader");
    address internal treasury = makeAddr("treasury");

    function _deployVault(MockERC20 asset, uint16 feeBps, uint256 cap) internal returns (InstitutionalVault vault) {
        InstitutionalVault impl = new InstitutionalVault();
        InstitutionalVault.InitParams memory p = InstitutionalVault.InitParams({
            asset: IERC20(address(asset)),
            name: "CapitalSage Vault",
            symbol: "csVLT",
            admin: admin,
            adminTransferDelay: ADMIN_DELAY,
            feeRecipient: treasury,
            depositFeeBps: feeBps,
            depositCap: cap,
            seedAssets: SEED
        });

        asset.mint(address(this), SEED);
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        asset.approve(predicted, SEED);
        vault = InstitutionalVault(address(new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, (p)))));
        assertEq(address(vault), predicted);

        vm.startPrank(admin);
        vault.grantRole(vault.PAUSER_ROLE(), pauser);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), feeManager);
        vault.grantRole(vault.UPGRADER_ROLE(), upgrader);
        vm.stopPrank();
    }
}
