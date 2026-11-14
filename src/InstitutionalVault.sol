// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/// @title InstitutionalVault
/// @notice ERC-4626 vault with a capped entry fee, deposit cap, pause, and UUPS upgrades.
contract InstitutionalVault is
    Initializable,
    ERC4626Upgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardTransient,
    UUPSUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint16 public constant MAX_FEE_BPS = 500;
    uint256 private constant BPS_SCALE = 10_000;
    uint8 private constant DECIMALS_OFFSET = 6;
    address private constant DEAD_SHARES_RECEIVER = address(0xdead);

    /// @custom:storage-location erc7201:capitalsage.storage.InstitutionalVault
    struct VaultStorage {
        address feeRecipient;
        uint16 depositFeeBps;
        uint256 depositCap;
    }

    // keccak256(abi.encode(uint256(keccak256("capitalsage.storage.InstitutionalVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULT_STORAGE_SLOT = 0x85916502d2c05b2b07632b63b7a0be85da7d258ae28db4ba4f205e10074ab800;

    struct InitParams {
        IERC20 asset;
        string name;
        string symbol;
        address admin;
        uint48 adminTransferDelay;
        address feeRecipient;
        uint16 depositFeeBps;
        uint256 depositCap;
        uint256 seedAssets;
    }

    event DepositFeeUpdated(uint16 previousBps, uint16 newBps);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event DepositCapUpdated(uint256 previousCap, uint256 newCap);

    error FeeTooHigh(uint16 bps);
    error InvalidAddress();
    error ZeroAmount();

    constructor() {
        _disableInitializers();
    }

    /// @dev Pulls `seedAssets` from the caller and mints the shares to a dead address, so the vault is never empty.
    function initialize(InitParams calldata p) external initializer {
        if (p.admin == address(0)) revert InvalidAddress();
        if (p.seedAssets == 0) revert ZeroAmount();

        __ERC20_init(p.name, p.symbol);
        __ERC4626_init(p.asset);
        __AccessControlDefaultAdminRules_init(p.adminTransferDelay, p.admin);
        __Pausable_init();

        _setFeeRecipient(p.feeRecipient);
        _setDepositFee(p.depositFeeBps);
        _setDepositCap(p.depositCap);

        uint256 seedShares = _convertToShares(p.seedAssets, Math.Rounding.Floor);
        ERC4626Upgradeable._deposit(_msgSender(), DEAD_SHARES_RECEIVER, p.seedAssets, seedShares);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setDepositFee(uint16 bps) external onlyRole(FEE_MANAGER_ROLE) {
        _setDepositFee(bps);
    }

    function setFeeRecipient(address recipient) external onlyRole(FEE_MANAGER_ROLE) {
        _setFeeRecipient(recipient);
    }

    function setDepositCap(uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setDepositCap(cap);
    }

    function depositFeeBps() external view returns (uint16) {
        return _getVaultStorage().depositFeeBps;
    }

    function feeRecipient() external view returns (address) {
        return _getVaultStorage().feeRecipient;
    }

    function depositCap() external view returns (uint256) {
        return _getVaultStorage().depositCap;
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAmount();
        shares = super.deposit(assets, receiver);
        if (shares == 0) revert ZeroAmount();
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused nonReentrant returns (uint256) {
        if (shares == 0) revert ZeroAmount();
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        if (assets == 0) revert ZeroAmount();
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenNotPaused
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroAmount();
        assets = super.redeem(shares, receiver, owner);
        if (assets == 0) revert ZeroAmount();
    }

    /// @dev Conservative: counts the gross deposit against the cap, although only the net amount stays in the vault.
    function maxDeposit(address) public view override returns (uint256) {
        if (paused()) return 0;
        uint256 cap = _getVaultStorage().depositCap;
        if (cap == type(uint256).max) return type(uint256).max;
        uint256 total = totalAssets();
        return cap > total ? cap - total : 0;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        uint256 room = maxDeposit(receiver);
        if (room == type(uint256).max) return type(uint256).max;
        return _convertToShares(room, Math.Rounding.Floor);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return paused() ? 0 : super.maxWithdraw(owner);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return paused() ? 0 : super.maxRedeem(owner);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return super.previewDeposit(assets - _feeOnTotal(assets));
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 assets = super.previewMint(shares);
        return assets + _feeOnRaw(assets);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        uint256 fee = _feeOnTotal(assets);
        super._deposit(caller, receiver, assets, shares);
        if (fee > 0) IERC20(asset()).safeTransfer(_getVaultStorage().feeRecipient, fee);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return DECIMALS_OFFSET;
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function _feeOnRaw(uint256 assets) private view returns (uint256) {
        return assets.mulDiv(_getVaultStorage().depositFeeBps, BPS_SCALE, Math.Rounding.Ceil);
    }

    function _feeOnTotal(uint256 assets) private view returns (uint256) {
        uint256 bps = _getVaultStorage().depositFeeBps;
        return assets.mulDiv(bps, bps + BPS_SCALE, Math.Rounding.Ceil);
    }

    function _setDepositFee(uint16 bps) private {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh(bps);
        VaultStorage storage $ = _getVaultStorage();
        emit DepositFeeUpdated($.depositFeeBps, bps);
        $.depositFeeBps = bps;
    }

    function _setFeeRecipient(address recipient) private {
        if (recipient == address(0) || recipient == address(this)) revert InvalidAddress();
        VaultStorage storage $ = _getVaultStorage();
        emit FeeRecipientUpdated($.feeRecipient, recipient);
        $.feeRecipient = recipient;
    }

    function _setDepositCap(uint256 cap) private {
        VaultStorage storage $ = _getVaultStorage();
        emit DepositCapUpdated($.depositCap, cap);
        $.depositCap = cap;
    }

    function _getVaultStorage() private pure returns (VaultStorage storage $) {
        assembly {
            $.slot := VAULT_STORAGE_SLOT
        }
    }
}
