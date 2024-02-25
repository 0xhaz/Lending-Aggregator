// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IFlashLoanRecipient
 * @notice Interface required to implement Balancer's flashloan
 * From Balance: "Inspired by the Aave Protocol's IFlashLoanReceiver"
 */

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IFlashLoanRecipient {
  /**
   * @dev When `flashloan` is called on the vault, it invokes the `receiveFlashLoan` hook on the recipient
   *
   * At the time of the call, the Vault will have transferred `amounts` for `tokens` to the recipient. Before this
   * calls returns, the recipient must have transferred `amounts` plus `feeAmounts` for each token back to the
   * Vault, or else the entire flash loan will revert
   *
   * `userData` is the same value passed in the `IVault.flasLoan` call
   */

  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes calldata userData
  )
    external;
}
