// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IChief
 * @notice Defines interface for {Chief} access control operations
 */

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IChief is IAccessControl {
  // @notice Returns the timelock address of the system
  function timelock() external view returns (address);

  // @notice Returns the address mapper contract address of the system
  function addrMapper() external view returns (address);

  /**
   * @notice Returns true if `vault` is active
   * @param vault to check status
   */
  function isVaultActive(address vault) external view returns (bool);

  /**
   * @notice Returns true if `flasher` is an allowed {IFlasher}
   * @param flasher address to check
   */
  function allowedFlasher(address flasher) external view returns (bool);

  /**
   * @notice Returns true if `swapper` is an allowed {ISwapper}
   * @param swapper address to check
   */
  function allowedSwapper(address swapper) external view returns (bool);
}
