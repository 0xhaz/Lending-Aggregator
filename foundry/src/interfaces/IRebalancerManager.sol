// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IRebalancerManager
 * @notice Defines the interface of {RebalancerManager}
 */

import {IVault} from "./IVault.sol";
import {ILendingProvider} from "./ILendingProvider.sol";
import {IFlasher} from "./IFlasher.sol";

interface IRebalancerManager {
  /**
   * @dev Emit when `executor's` `allowed` state is updated
   * @param executor address of the executor
   * @param allowed new state of the executor
   */
  event AllowExecutor(address indexed executor, bool allowed);

  /**
   * @notice Rebalance funds of a vault between providers
   * @param vault address of the vault
   * @param assets amount to be rebalanced
   * @param debt amount to be rebalanced (zero if `vault` is a {YieldVault})
   * @param from provider address
   * @param to provider address
   * @param flasher contract address (zero address if `vault` is a {YieldVault})
   * @param setToAsActiveProvider boolean if `activeProvider` should change
   * @dev Requirements:
   * - Must only be called by a valid executor
   * - Must check `assets` and `debt` amounts are less than `vault` managed amounts
   * NOTE: For arguments `assets` and `debt` you can pass `type(uint256).max` in solidity
   * to effectively rebalance 100% of both assets and debt from a provider to another
   * Hints:
   * - In ether.js use `ethers.constants.MaxUint256` to return equivalent BigNumber
   * - In Foundry, using console use $(cast max-uint)
   */
  function rebalanceVault(
    IVault vault,
    uint256 assets,
    uint256 debt,
    ILendingProvider from,
    ILendingProvider to,
    IFlasher flasher,
    bool setToAsActiveProvider
  )
    external
    returns (bool success);

  /**
   * @notice Set `executor` as an authorized address for calling rebalancer operations
   * or remove authorization
   * @param executor address of the executor
   * @param allowed boolean if `executor` is allowed to call rebalancer operations
   * @dev Requirements:
   * - Must be called from a timelock
   * - Must emit a `AllowExecutor` event
   */
  function allowExecutor(address executor, bool allowed) external;

  /**
   * @notice Callback function that completes execution logic of a rebalance
   * operation with a flashloan
   * @param vault being rebalanced
   * @param assets amount to be rebalanced
   * @param debt amount to be rebalanced
   * @param from provider address
   * @param to provider address
   * @param flasher contract address
   * @param setToAsActiveProvider boolean if `to` should change
   * @dev Requirements:
   * - Must check this address was the flashloan originator
   * - Must clear the check state variable `_entryPoint`
   */
  function completeRebalance(
    IVault vault,
    uint256 assets,
    uint256 debt,
    ILendingProvider from,
    ILendingProvider to,
    IFlasher flasher,
    bool setToAsActiveProvider
  )
    external
    returns (bool success);
}
