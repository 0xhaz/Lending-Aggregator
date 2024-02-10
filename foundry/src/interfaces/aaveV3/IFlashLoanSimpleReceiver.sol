// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IFlashLoanSimpleReceiver
 * @notice Interface for the Aave V3 flash loan receiver
 * @dev Implmenet this interface to develop a flashloan-compatible flashLoanReceiver contract
 */

interface IFlashLoanSimpleReceiver {
  /**
   * @notice Executes an operation after receiving the flash-borrowed asset
   * @param asset The address of the flash-borrowed asset
   * @param amount The amount of the flash-borrowed asset
   * @param premium The fee of the flash-borrowed asset
   * @param initiator The address of the flashloan initiator
   * @param params The encoded data to pass to the receiver
   *
   * @dev Ensure that the contract can return the debt + premium, e.g
   * has enough funds to repay and has approved the Pool to pull the total amount
   */

  function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address initiator,
    bytes calldata params
  )
    external
    returns (bool);
}
