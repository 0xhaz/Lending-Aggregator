// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IVaultFactory
 * @notice Vault factory deployment interface
 */

interface IVaultFactory {
  /**
   * @notice Deploys a new type of vault
   * @param deployData The encoded data containing constructor arguments
   * @dev Requirements:
   * - Must be called from {Chief} contract only
   */
  function deployVault(bytes calldata deployData) external returns (address vault);

  /**
   * @notice Returns the address for a spefcific salt
   * @param data bytes32 used as salt in vault deployment
   */
  function configAddress(bytes32 data) external returns (address vault);
}
