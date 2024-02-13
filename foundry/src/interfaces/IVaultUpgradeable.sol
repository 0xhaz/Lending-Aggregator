// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IVaultUpgradeable
 * @notice Defines the interface for vaults extending for {IERC4626Upgradeable}
 */

import {IERC4626Upgradeable} from
  "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import {ILendingProvider} from "./ILendingProvider.sol";
import {IFujiOracle} from "./IFujiOracle.sol";

interface IVaultUpgradeable is IERC4626Upgradeable {
  /////////////////////////////// EVENTS ///////////////////////////////
  /**
   * @dev Emit when borrow action occurs
   * @param sender who call {IVault-borrow}
   * @param receiver who receives the borrowed `debt` amount
   * @param owner who will incur the debt
   * @param debt the amount of debt
   * @param shares amonut of `debtShares` received
   */
  event Borrow(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 debt,
    uint256 shares
  );

  /**
   * @dev Emit when payback action occurs
   * @param sender who call {IVault-payback}
   * @param owner address whose debt will be reduced
   * @param debt the amount of debt to be reduced
   * @param shares the amount of `debtShares` to be burned
   */
  event Payback(address indexed sender, address indexed owner, uint256 debt, uint256 shares);

  /**
   * @dev Emit when vault is initialized
   * @param initializer of this vault
   */
  event VaultInitialized(address indexed initializer);

  /**
   * @dev Emit when the oracle address is changed
   * @param newOracle address of the new oracle
   */
  event OracleChanged(address indexed newOracle);

  /**
   * @dev Emit when the available providers for the vault change
   * @param newProviders array of the new providers
   */
  event ProvidersChanged(ILendingProvider[] newProviders);

  /**
   * @dev Emit when the active provider is changed
   * @param newActiveProvider address of the new active provider
   */
  event ActiveProviderChanged(ILendingProvider newActiveProvider);

  /**
   * @dev Emit when the vault is rebalance
   * @param assets amount of assets to be rebalanced
   * @param debt amount of debt to be rebalanced
   * @param from address of the provider from which the assets are taken
   * @param to address of the provider to which the assets are sent
   */
  event VaultRebalance(uint256 assets, uint256 debt, address indexed from, address indexed to);

  /**
   * @dev Emit when the max LTV is changed
   * @param newMaxLtv new max LTV
   */
  event MaxLtvChanged(uint256 newMaxLtv);

  /**
   * @dev Emit when the liquidation ratio is changed
   * @param newLiqRatio new liquidation ratio
   */
  event LiqRatioChanged(uint256 newLiqRatio);

  /**
   * @dev Emit when the minimum amount is changed
   * @param newMinAmount the new minimum amount
   */
  event MinAmountChanged(uint256 newMinAmount);

  /**
   * @dev Emit when deposit cap is changed
   * @param newDepositCap the new deposit cap
   */
  event DepositCapChanged(uint256 newDepositCap);

  /////////////////////////////// ASSET MANAGEMENT FUNCTIONS ///////////////////////////////
  /**
   * @notice Returns the amount of assets owned by `owner`
   * @param owner to check balance
   * @dev This method avoids having to do external conversions from shares to assets,
   * since {IERC4626-balanceOf} returns shares
   */
  function balanceOfAsset(address owner) external view returns (uint256 assets);

  /////////////////////////////// DEBT MANAGEMENT FUNCTIONS ///////////////////////////////
  /**
   * @notice Returns the decimals for `debtAsset` of this vault
   * @dev Requirements:
   * - Must match the `debtAsset` decimals in ERC20 token
   * - Must return zero in {YieldVault}
   */
  function debtDecimals() external view returns (uint8);

  /**
   * @notice Returns the address of the underlying token used as debt in functions
   * `borrow` and `payback` based on {IERC4626-asset}
   * @dev Requirements:
   * - Must be an ERC-20 token
   * - Must not revert
   * - Must return zero in a {YieldVault}
   */
  function debtAsset() external view returns (address);

  /**
   * @notice Returns the amount of debt owned by `owner`
   * @param owner to check balance
   */
  function balanceOfDebt(address owner) external view returns (uint256 debt);

  /**
   * @notice Returns the amount of `debtShares` owned by `owner`
   * @param owner to check balance
   */
  function balanceOfDebtShares(address owner) external view returns (uint256 debtShares);

  /**
   * @notice Returns the total amount of the underlying debt asset
   * that is "managed" by this vault. Based on {IERC4626-totalAssets}
   *
   * @dev Requirements:
   * - Must account for any compounding occuring from yield or interest accrual
   * - Must be inclusive of any fees that are charged against assets in the vault
   * - Must not revert
   * - Must return zero in a {YieldVault}
   */
  function totalDebt() external view returns (uint256);

  /**
   * @notice Returns the amount of shares this vault exchange for the amount
   * of debt assets provided. Based on {IERC4626-convertToShares}
   *
   * @param debt to convert to `debtShares`
   * @dev Requirements:
   * - Must not be inclusive of any fees that are charged agains assets in the Vault
   * - Must not show any variations depending on the caller
   * - Most not reflect slippage or other on-chain conditions, when performing the actual exchange
   * - Must not revert
   * NOTE: This calculcation MAY not reflect the "per-user" price per share, and instead must reflect
   * the "average-user's" price per share, meaning what the avergage user must expect to see when
   * exchanging to and from
   */
  function convertDebtToShares(uint256 debt) external view returns (uint256 shares);

  /**
   * @notice Returns the amount of debt assets this vault exchange for the amount
   * of shares provided. Based on {IERC4626-convertToAssets}
   *
   * @param shares to convert to `debt`
   *
   * @dev Requirements:
   * - Must not be inclusive of any fees that are charged against assets in the Vault
   * - Must not show any variations depending on the caller
   * - Must not reflect slippage or other on-chain conditions, when performing the actual exchange
   * - Must not revert
   *
   * NOTE: This calculcation MAY not reflect the "per-user" price per share, and instead must reflect
   * the "average-user's" price per share, meaning what the avergage user must expect to see when
   * exchanging to and from
   */
  function convertToDebt(uint256 shares) external view returns (uint256 debt);

  /**
   * @notice Returns the maximum amount of the debt asset that can be borrowed for the `owner`
   * through a borrow call
   *
   * @param owner to check max borrow
   *
   * @dev Requirements:
   * - Must return a limited value if receiver is subject to some borrow limit
   * - Must return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be borrowed
   * - Must not revert
   */
  function maxBorrow(address owner) external view returns (uint256 debt);

  /**
   * @notice Returns the maximum amonut of debt that can be payback by the `borrower`
   *
   * @param owner to check
   *
   * @dev Requirements:
   * - Must not revert
   */
  function maxPayback(address owner) external view returns (uint256 debt);

  /**
   * @notice Returns the maximum amount of debt shares that can be "minted-for-borrowing" by the `borrower`
   *
   * @param owner to check
   *
   * @dev Requirements:
   * - Must not revert
   */
  function maxMintDebt(address owner) external view returns (uint256 shares);

  /**
   * @notice Returns the maximum amount of debt shares that can be "burned-for-payback" by the `borrower`
   *
   * @param owner to check
   *
   * @dev Requirements:
   * - Must not revert
   */
  function maxBurnDebt(address owner) external view returns (uint256 shares);

  /**
   * @notice Returns the amount of `debtShares` that borrowing `debt` amount will generate
   *
   * @param debt to borrow
   *
   * @dev Requirements:
   * - Must not revert
   */
  function previewBorrow(uint256 debt) external view returns (uint256 shares);

  /**
   * @notice Returns the amount of `debt` that borrowing `debtShares` amount will generate
   *
   * @param shares to borrow
   *
   * @dev Requirements:
   * - Must not revert
   */
  function previewMintDebt(uint256 shares) external view returns (uint256 debt);

  /**
   * @notice Returns the amount of `debtShares` that will be burned to payback `debt` amount
   *
   * @param debt to payback
   *
   * @dev Requirements:
   * - Must not revert
   */
  function previewPayback(uint256 debt) external view returns (uint256 shares);

  /**
   * @notice Returns the amount of debt asset that will be pulled from user, if `debtShares` are
   * burned to payback debt
   *
   * @param debt to payback
   *
   * @dev Requirements:
   * - Must not revert
   */
  function previewBurnDebt(uint256 shares) external view returns (uint256 debt);

  /**
   * @notice Perform a borrow action. Function inspired on {IERC4626-deposit}
   *
   * @param debt amount to borrow
   * @param receiver address to receive the `debtShares`
   * @param owner address to incur the debt
   *
   * @dev Mint `debtShares` to owner by taking a loan of exact amount of underlying tokens
   * Requirements:
   * - Must emit a {Borrow} event
   * - Must revert if owner does not own sufficient collateral to back debt
   * - Must revert if caller is not owner or permissioned operator to act on owner behalf
   */
  function borrow(uint256 debt, address receiver, address owner) external returns (uint256 shares);

  /**
   * @notice Perform a borrow action by minting `debtShares`
   *
   * @param shares of debt to mint
   * @param receiver of the borrowed amount
   * @param owner who will incur the debt and whom `debtShares` will be minted
   *
   * @dev Mints `debtShares` to `owner`
   * Requirements:
   * - Must emit a {Borrow} event
   * - Must revert if owner does not own sufficient collateral to back debt
   * - Must revert if caller is not owner or permissioned operator to act on owner behalf
   */
  function mintDebt(
    uint256 shares,
    address receiver,
    address owner
  )
    external
    returns (uint256 debt);

  /**
   * @notice Burn `debtShares` to `receiver` by paying back exact `debt` amount of underlying tokens
   * @param debt amount to payback
   * @param receiver to whom debt amount will be paid
   * @dev Implementation will require pre-ERC20-approval of the underlying debt token
   * Requirements:
   * - Must emit a {Payback} event
   */
  function payback(uint256 debt, address receiver) external returns (uint256 shares);

  /**
   * @notice Burns `debtShares` to `owner` by paying back loan by specifying debt shares
   * @param shares of debt to to payback
   * @param owner to whom debt amount will be paid
   * @dev Implementation will require pre-ERC20-approval of the underlying debt token
   * Requirements:
   * - Must emit a {Payback} event
   */
  function burnDebt(uint256 shares, address owner) external returns (uint256 debt);

  /////////////////////////////// GENERAL FUNCTIONS ///////////////////////////////
  /**
   * @notice Returns the active provider of this vault
   */
  function getProviders() external view returns (ILendingProvider[] memory);

  /**
   * @notice Returns the active provider of this vault
   */
  function activeProvider() external view returns (ILendingProvider);

  /////////////////////////////// REBALANCING FUNCTIONS ///////////////////////////////
  /**
   * @notice Performs rebalancing of vault by moving funds across providers
   *
   * @param assets amount of this vault to be rebalanced
   * @param debt amount of this vault to be rebalanced (Note: pass zero if this a {YieldVault})
   * @param from address of the provider from which the assets are taken
   * @param to address of the provider to which the assets are sent
   * @param fee expected fee from rebalancing operation
   * @param setToAsActiveProvider boolean to set `to` as active provider
   *
   * @dev Requirements:
   * - Must check providers `from` and `to` are valid
   * - Must be called from {RebalancerManager} contract that makes all proper checks
   * - Must revert if caller is not an approved rebalancer
   * - Must emit VaultRebalance event
   * - Must check `fee` is a reasonable amount
   */
  function rebalance(
    uint256 assets,
    uint256 debt,
    ILendingProvider from,
    ILendingProvider to,
    uint256 fee,
    bool setToAsActiveProvider
  )
    external
    returns (bool);

  /////////////////////////////// LIQUIDATION FUNCTIONS ///////////////////////////////

  /**
   * @notice Returns the current health factor of `owner`
   * @param owner to check health factor
   * @dev Requirements:
   * - Must return type(uint256).max when `owner` has no debt
   * - Must revert in {YieldVault}
   *
   * "healthFactor" is scaled up by 1e18. A value below 1e18 means `owner` is eligible for liquidation
   */
  function getHealthFactor(address owner) external view returns (uint256 healthFactor);

  /**
   * @notice Returns the liquidation close factor based on `owner's` health factor
   * @param owner of the debt position
   * @dev Requirements:
   * - Must return zero if `owner` is not liquidatable
   * - Must revert in {YieldVault}
   */
  function getLiquidationFactor(address owner) external view returns (uint256 liquidationFactor);

  /**
   * @notice Performs liquidation of an unhealthy position, meaning a `healthFactor` below 1e18
   *
   * @param owner to be liquidated
   * @param receiver of the collateral shares of liquidated position
   * @param liqCloseFactor percentage of `owner` debt to be liquidated
   *
   * @dev Requirements:
   * - Must revert if caller is not an approved liquidator
   * - Must revert if `owner` is not liquidatable
   * - Must emit a Liquidation event
   * - Must liquidate according to `liqCloseFactor` but restricred to the following:
   *  - Liquidate up to 50% of `owner` debt when: 100 >= `healthFactor` > 95
   *  - Liquidate up to 100% of `owner` debt when: 95 > `healthFactor`
   * - Must revert in {YieldVault}
   *
   * WARNING! It is liquidator's responsibility to check if liquidiation is profitable
   */
  function liquidate(
    address owner,
    address receiver,
    uint256 liqCloseFactor
  )
    external
    returns (uint256 gainedShares);

  /////////////////////////////// SETTER FUNCTIONS ///////////////////////////////
  /**
   * @notice Sets the lists of providers of this vault
   * @param providers array of providers to be set
   * @dev Requirements:
   * - Must not contain a zero address
   */
  function setProviders(ILendingProvider[] memory providers) external;

  /**
   * @notice Sets the active provider of this vault
   * @param activeProvider address of the provider to be set
   * @dev Requirements:
   * - Must be a provider previously set by `setProviders`
   * - Must be called from a timelock contract
   *
   * WARNING! Changing active provider without a `rebalance` call
   * can result in denial of service for vault users
   */
  function setActiveProvider(ILendingProvider activeProvider) external;

  /**
   * @notice Sets the minimum amount for : `deposit`, `mint` and `borrow`
   *
   * @param amount to be as minimum
   */
  function setMinAmount(uint256 amount) external;
}
