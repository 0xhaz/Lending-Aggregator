// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title ILiquidationManager
 * @notice Interface for the LiquidationManager contract
 */

import {IVault} from "./IVault.sol";
import {ISwapper} from "./ISwapper.sol";
import {IFlasher} from "./IFlasher.sol";

interface ILiquidationManager {
  /**
   * @dev Emit when `executor's` `allowed` state is updated
   * @param executor address of the executor
   * @param allowed new state of the executor
   */
  event AllowExecutor(address indexed executor, bool allowed);

  /**
   * @notice Set `executor` as an authorized address for calling liquidation operations
   * or remove authorization
   *
   * @param executor address of the executor
   * @param allowed boolean if `executor` is allowed to call liquidation operations
   * @dev Requirements:
   * - Must be called from a timelock
   * - Must emit a `AllowExecutor` event
   */
  function allowExecutor(address executor, bool allowed) external;

  /**
   * @notice Liquidate the position of a given user
   * @param users address of the user
   * @param liqCloseFactors (optional array) for each user, otherwise pass zero for each
   * @param vault who holds the `users` position
   * @param flasher to be used in liquidation
   * @param debtToCover total amount debt to cover for all `users`
   * @param swapper to be used in liquidation
   *
   * @dev Requirements:
   * - Must be called from a keeper
   * - Must emit a `AllowExecutor` event
   * - Must not revert if at least one user is liquidated
   */
  function liquidate(
    address[] calldata users,
    uint256[] calldata liqCloseFactors,
    IVault vault,
    uint256 debtToCover,
    IFlasher flasher,
    ISwapper swapper
  )
    external;
}
