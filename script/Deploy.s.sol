// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {InstitutionalVault} from "../src/InstitutionalVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract Deploy is Script {
    error ProxyAddressMismatch(address predicted, address actual);

    function run() external returns (InstitutionalVault) {
        InstitutionalVault.InitParams memory p = InstitutionalVault.InitParams({
            asset: IERC20(vm.envAddress("ASSET")),
            name: vm.envString("VAULT_NAME"),
            symbol: vm.envString("VAULT_SYMBOL"),
            admin: vm.envAddress("ADMIN"),
            adminTransferDelay: uint48(vm.envUint("ADMIN_DELAY")),
            feeRecipient: vm.envAddress("FEE_RECIPIENT"),
            depositFeeBps: uint16(vm.envUint("FEE_BPS")),
            depositCap: vm.envUint("DEPOSIT_CAP"),
            seedAssets: vm.envUint("SEED_ASSETS")
        });
        vm.startBroadcast();
        InstitutionalVault vault = _deploy(p);
        vm.stopBroadcast();
        return vault;
    }

    /// @dev Anvil only: deploys a mock asset and funds the seed.
    function runLocal() external returns (InstitutionalVault vault) {
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(deployer, 1e6);
        vault = _deploy(
            InstitutionalVault.InitParams({
                asset: IERC20(address(usdc)),
                name: "CapitalSage USDC Vault",
                symbol: "csUSDC",
                admin: deployer,
                adminTransferDelay: 2 days,
                feeRecipient: deployer,
                depositFeeBps: 100,
                depositCap: 10_000_000e6,
                seedAssets: 1e6
            })
        );
        vm.stopBroadcast();
    }

    function _deploy(InstitutionalVault.InitParams memory p) internal returns (InstitutionalVault vault) {
        (, address deployer,) = vm.readCallers();
        InstitutionalVault impl = new InstitutionalVault();

        // Seed is pulled in `initialize`, so the proxy (next nonce after `approve`) must be approved before it exists.
        address predicted = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);
        p.asset.approve(predicted, p.seedAssets);
        vault = InstitutionalVault(address(new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, (p)))));
        if (address(vault) != predicted) revert ProxyAddressMismatch(predicted, address(vault));

        console2.log("implementation", address(impl));
        console2.log("vault (proxy) ", address(vault));
        console2.log("dead shares   ", vault.balanceOf(address(0xdead)));
    }
}
