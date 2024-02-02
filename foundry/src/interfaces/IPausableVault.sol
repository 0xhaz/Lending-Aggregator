// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IPausableVault
 * @notice Defines the interface {PausableVault} contract
 */

interface IPausableVault {
  enum VaultActions {
    Deposit,
    Withdraw,
    Borrow,
    Payback
  }

  /**
   * @dev Emit when pause of `action` is triggered by `account`
   * @param account who called the pause
   * @param action which action is paused
   */
  event Paused(address account, VaultActions action);

  /**
   * @dev Emit when the pause of `action` is lifted by `account`
   * @param account who called the unpause
   * @param action which action is unpaused
   */
  event UnPaused(address account, VaultActions action);

  /**
   * @dev Emitted when forced pause all `VaultAction` triggered by `account`
   * @param account who called all pause
   */
  event PauseForceAll(address account);

  /**
   * @dev Emit when forced pause is lifted to all `VaultAction` triggered by `account`
   * @param account who called all unpause
   */
  event UnpausedForceAll(address account);

  /**
   * @notice Returns true if `action` in contract is paused, otherwise false
   * @param action to check pause state
   */
  function paused(VaultActions action) external view returns (bool);

  /**
   * @notice Force pause all `VaultAction` in contract
   * @dev Requirements:
   * - Must be implemented in child contract with access restriction
   */
  function pauseForceAll() external;

  /**
   * @notice Force unpause all `VaultAction` in contract
   * @dev Requirements:
   * - Must be implemented in child contract with access restriction
   */
  function unpauseForceAll() external;

  /**
   * @notice Set paused state for `action` of this vault
   * @param action Enum: 0 = Deposit, 1 = Withdraw, 2 = Borrow, 3 = Payback
   * Requirements:
   * - The `action` in contract must not be paused
   * - Must be implemented in child contract with access restriction
   */
  function pause(VaultActions action) external;

  /**
   * @notice Set unpaused state for `action` of this vault
   * @param action Enum: 0 = Deposit, 1 = Withdraw, 2 = Borrow, 3 = Payback
   * Requirements:
   * - The `action` in contract must be paused
   * - Must be implemented in child contract with access restriction
   */
  function unpause(VaultActions action) external;
}
