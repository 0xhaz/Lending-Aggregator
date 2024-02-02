// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IVault
 * @notice Defines the interface for vaults extending from IERC4626
 */

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILendingProvider} from "./ILendingProvider.sol";
import {IFujiOracle} from "./IFujiOracle.sol";

interface IVault is IERC4626 {
  /**
   * @dev Emit when borrow action occurs
   * @param sender who calls {IVault-borrow}
   * @param receiver who receives the borrowed tokens
   * @param owner who will incur the debt
   * @param debtAmount amount of debt incurred
   * @param shares amount of `debtShares` received
   */
  event Borrow(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 debtAmount,
    uint256 shares
  );

  /**
   * @dev Emit when payback action occurs
   * @param sender address who calls {IVault-payback}
   * @param owner address whose debt is being paid back
   * @param debt amount of debt being paid back
   * @param shares amount of `debtShares` being burned
   */
  event Payback(address indexed sender, address indexed owner, uint256 debt, uint256 shares);

  /**
   * @dev Emit when the vault is initialized
   * @param initializer of the vault
   */
  event VaultInitialized(address initializer);

  /**
   * @dev Emit when the oracle address is changed
   * @param newOracle the new oracle address
   */
  event OracleChanged(IFujiOracle newOracle);

  /**
   * @dev Emit when the available providers for the vault change
   * @param newProviders the new providers available
   */
  event ProvidersChanged(ILendingProvider[] newProviders);

  /**
   * @dev Emit when the active provider is changed
   * @param newActiveProvider the new active provider
   */
  event ActiveProviderChanged(ILendingProvider newActiveProvider);

  /**
   * @dev Emit when the vault is rebalanced
   * @param assets amount to be rebalanced
   * @param debt amount to be rebalanced
   * @param from provider
   * @param to provider
   */
  event VaultRebalance(uint256 assets, uint256 debt, address indexed from, address indexed to);

  /**
   * @dev Emit when the max LTV is changed
   * @param newMaxLtv the new max LTV
   */
  event MaxLtvChanged(uint256 newMaxLtv);

  /**
   * @dev Emit when the liquidation ratio is changed
   * @param newLiqRatio the new liquidation ratio
   */
  event LiqRatioChanged(uint256 newLiqRatio);

  /**
   * @dev Emit when the minimum amount is changed
   * @param newMinAmount the new minimum amount
   */
  event MinAmountChanged(uint256 newMinAmount);

  /**
   * @dev Emit when the deposit cap is changed
   * @param newDepositCap the new deposit cap of this vault
   */
  event DepositCapChanged(uint256 newDepositCap);

  ////////// ASSET MANAGEMENT FUNCTIONS //////////

  /**
   * @notice Returns the amount of assets owned by `owner`
   * @param owner to check balance
   * @dev This method avoids having to do external conversions from shares to
   * assets, since {IERC4626-balanceOf} returns shares
   */
  function balanceOfAsset(address owner) external view returns (uint256 assets);

  ////////// DEBT MANAGEMENT FUNCTIONS //////////

  /**
   * @notice Returns the decimals for `debtAsset` of this vault
   * @dev Requirements:
   * - Must match the `debAsset` decimals in ERC20 token
   * - Must return zero in {YieldVault}
   */
  function debtDecimals() external view returns (uint8);

  /**
   * @notice Returns the address of the underlying token used as debt in function
   * `borrow()` and `payback()`. Based on {IERC4626-asset}
   * @dev Requirements:
   * - Must be a valid ERC20 token
   * - Must not revert
   * - Must return zero in {YieldVault}
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
   * @dev Requirements:
   * - Must account for any compounding occuring from yield or interest accrual
   * - Must be inclusive of any fees that are charged against assets in the vault
   * - Must not revert
   * - Must return zero in {YieldVault}
   */
  function totalDebt() external view returns (uint256);

  /**
   * @notice Returns the amount of shares this vault would exchange for the amount
   * of debt assets provided. Based on {IERC4626-convertToShares}
   * @param debt to convert into `debtShares`
   * @dev Requirements:
   * - Must not be inclusive of any fees that are charged against assets in the Vault
   * - Must not show any variations depending on the caller
   * - Must no reflect slippage or other on-chain conditions, when performing the actual exchange
   * - Must not revert
   *
   * NOTE: This calculation MAY not reflect the "per-user" price per share, and instead must reflect the "average-user's" price per share
   * meaning what the average user must expect to see when exchaning to and from
   */
  function convertDebtToShares(uint256 debt) external view returns (uint256 shares);

  /**
   * @notice Returns the amount of debt assets that this vault would exchange for the amount
   * of shares provided. Based on {IERC4626-convertToAsssets}
   * @param shares amount to convert into `debt`
   * @dev Requirements:
   * - Must not be inclusive for any fees that are charged against assets in the Vault
   * - Must now show any variations depending on the caller
   * - Must not reflect slippage or other on-chain conditions, when performing the actual exchange
   * - Must not revert
   *
   * NOTE: This calculation MAY not reflect the "per-user" price per share, and instead must reflect the "average-user's" price per share
   * meaning what the average user must expect to see when exchaning to and from
   */
  function convertToDebt(uint256 shares) external view returns (uint256 debt);

  /**
   * @notice Returns the maximum amount of the debt asset that can be borrowed for the `owner`
   * through a borrow call
   * @param owner to check
   * @dev Requirements:
   * - Must return a limited value if receiver is subject to some borrow limit
   * - Must return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be borrowed
   * - Must not revert
   */
  function maxBorrow(address owner) external view returns (uint256 debt);

  /**
   * @notice Returns the maximum amount of debt that can be payback by the `borrower`
   * @param owner to check
   * @dev Requirements:
   * - Must not revert
   */
  function maxPayback(address owner) external view returns (uint256 debt);

  /**
   * @notice Returns the maximum amount of debt shares that can be "minted-for-borrowing" by the `borrower`
   * @param owner to check
   * @dev Requirements:
   * - Must not revert
   */
  function maxMintDebt(address owner) external view returns (uint256 shares);

  /**
   * @notice Returns the maximum of debt shares that can be "burned-for=payback" by the `borrower`
   * @param owner to check
   * @dev Requirements:
   * - Must not revert
   */
  function maxBurnDebt(address owner) external view returns (uint256 shares);

  /**
   * @notice Returns the amount of `debtShares` that borrowing `debt` amount will generate
   * @param debt amount to check
   * @dev Requirements:
   * - Must not revert
   */
  function previewBorrow(uint256 debt) external view returns (uint256 shares);

  /**
   * @notice Returns the amount of debt that borrowing `debtShares` amount will generate
   * @param shares amount of debt to check
   * @dev Requirements:
   * - Must not revert
   */
  function previewMintDebt(uint256 shares) external view returns (uint256 debt);

  /**
   * @notice Returns the amount of `debtShares` that will be burned by paying back
   * `debt` amount of debt
   * @param debt amount of debt to check
   * @dev Requirements:
   * - Must not revert
   */
  function previewPayback(uint256 debt) external view returns (uint256 shares);

  /**
   * @notice Returns the amount of debt asset that will be pulled from user, if `debtShares` are burned to payback.
   * @param debt amount of debt to check
   * @dev Requirements:
   * - Must not revert
   */
  function previewBurnDebt(uint256 shares) external view returns (uint256 debt);

  /**
   * @notice Perform a borrow action. Function inspired by {IERC4626-deposit}
   * @param debt amount to borrow
   * @param receiver address to receive the borrowed tokens
   * @param owner address to incur the debt
   * @dev Mint `debtShares` to owner by taking a loan of exact amount of underlying tokens
   * Requirements:
   * - Must emit the Borrow event
   * - Must revert if owner does not own sufficient collateral to back debt
   * - Must revert if caller is not owner or permissioned operator to act on owner behalf
   */
  function borrow(uint256 debt, address receiver, address owner) external returns (uint256 shares);

  /**
   * @notice Perform a borrow action by minting `debtShares`
   * @param shares of debt to mint
   * @param receiver of the borrowed amount
   * @param owner who will incur the `debt` and whom `debtShares` will be minted to
   * @dev Mints `debtShares` to owner by taking a loan of exact amount of underlying tokens
   * Requirements:
   * - Must emit the Borrow event
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
   * @notice Burns `debtShares` to `receiver` by paying back loan with exact amount of underlying tokens
   * @param debt amount to payback
   * @param receiver to whom debt amount is being paid back
   * @dev Implementations will require ERC20-approval of the underlying token
   * Requirements:
   * - Must emit the Payback event
   */
  function payback(uint256 debt, address receiver) external returns (uint256 shares);

  /**
   * @notice Burns `debtShares` to `receiver` by paying back loan with exact amount of underlying tokens
   * @param shares of debt to payback
   * @param owner who will incur the `debt` and whom `debtShares` will be burned from
   * @dev Implementations will require ERC20-approval of the underlying token
   * Requirements:
   * - Must emit the Payback event
   */
  function burnDebt(uint256 shares, address owner) external returns (uint256 debt);

  ////////// GENERAL FUNCTIONS //////////
  /**
   * @notice Returns the active provider of this vault
   */
  function getProviders() external view returns (ILendingProvider[] memory);

  /**
   * @notice Returns the active provider of this vault
   */
  function activeProvider() external view returns (ILendingProvider);

  ////////// REBALANCING FUNCTIONS //////////
  /**
   * @notice Performs rebalancing of vault by moving funds across providers
   * @param assets amount of this vault to be rebalanced
   * @param debt amount of this vault to be rebalanced (Note: pass zero if this is a {YieldVault})
   * @param from provider
   * @param to provider
   * @param fee expected from rebalancing operation
   * @param setToAsActiveProvider boolean
   *
   * @dev Requirements:
   * - Must check providers `from` and `to` are valid
   * - Must be called from a {RebalancerManager} contract that makes all proper checks
   * - Must revert if caller is not an approved rebalancer
   * - Must emit the VaultRebalance event
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

  ////////// LIQUIDATION FUNCTIONS //////////
  /**
   * @notice Returns the current health factor of `owner`
   * @param owner to get health factor
   * @dev Requirements:
   * - Must return type(uint256).max when `owner` has no debt
   * - Must revert in {YieldVault}
   * 'healthFactor' is scaled up by 1e18. A value below 1e18 indicates 'owner' is insolvent
   */
  function getHealthFactor(address owner) external returns (uint256 healthFactor);

  /**
   * @notice Returns the liquidation close factor baszed on 'owner's' health factor
   * @param owner of debt position
   * @dev Requirements:
   * - Must return zero if `owner` is not liquidatable
   * - Must revert in {YieldVault}
   */
  function getLiquidationFactor(address owner) external returns (uint256 liquidationFactor);

  /**
   * @notice Performs liquidation of an unhealthy position, meaning a 'healthFactor' below 1e18
   * @param owner of debt position
   * @param receiver of liquidated assets
   * @param liqCloseFactor percentage of `owner`'s debt to be liquidated
   * @dev Requirements:
   * - Must revert if caller is not an approved liquidator
   * - Must revert if `owner` is not liquidatable
   * - Must emit the Liquidation event
   * - Must liquidate according to `liqCloseFactor` but restricted to the following:
   *    - Liquidate up to 50% of `owner` debt when: 100 >= 'healthFactor' > 95;
   *    - Liquidate up to 100% of `owner` debt when: 95 > 'healthFactor' .
   * - Must revert in {YieldVault}
   * WARNING! It is liquidator's responsibility to check if `receiver` can receive the liquidated assets
   */
  function liquidate(
    address owner,
    address receiver,
    uint256 liqCloseFactor
  )
    external
    returns (uint256 gainedShares);

  ////////// SETTER FUNCTIONS //////////
  /**
   * @notice Sets the lists of providers of this vault
   * @param providers list of providers
   * @dev Requirements:
   * - Must not contain zero address
   */
  function setProviders(ILendingProvider[] memory providers) external;

  /**
   * @notice Sets the active provider for this vault
   * @param activeProvider address
   * @dev Requirements:
   * - Must be a provider previously set by `setProviders()`
   * - Must be called from a timelock contract
   * WARNING! Changing active provider without a `rebalance()` call can result in denial of service
   * for vault users
   */
  function setActiveProvider(ILendingProvider activeProvider) external;

  /**
   * @notice Sets the minimum amount for: `deposit()`, `mint()` and `borrow()`
   * @param amount to be as minimum
   */
  function setMinAmount(uint256 amount) external;
}
