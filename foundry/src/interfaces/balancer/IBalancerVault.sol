// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IBalancerVault
 *
 * @notice Partial interface for the vault, only for flash loans
 */

import {IFlashLoanRecipient} from "./IFlashLoanRecepient.sol";
import {IProtocolFeesCollector} from "./IProtocolFeesCollector.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBalancerVault {
  ////////////////////////// FLASH LOANS //////////////////////////

  /**
   * @dev Performs a `flash loan`, sending tokens to `recipient`, executing the `receiveFlashLoan` hook on it,
   * and the reverting unless the tokens plus a proportional protocol fee have been returned
   *
   * The `tokens` and `amounts` arrays must have the same length, and each entry in these indicates the loan amount
   * for each token contract. `tokens` must be sorted in ascending order
   *
   * The `userData` field is ignored by the Vault, and forwarded as-is to `recipient` as part of the `receiveFlashLoan` call
   *
   * Emit `FlashLoan` events
   */
  function flashLoan(
    IFlashLoanRecipient recipient,
    IERC20[] memory tokens,
    uint256[] memory amounts,
    bytes memory userData
  )
    external;

  /**
   * @dev Emitted for each individual flash loan performed by `flashLoan`
   *
   */
  event FlashLoan(
    IFlashLoanRecipient indexed recipient, IERC20 indexed token, uint256 amount, uint256 feeAmount
  );

  /**
   * @dev Protocol Fees
   * Some operations cause the Vault to collect tokens in the form of protocol fees, which can then be withdrawn by
   * permissioned accounts
   *
   * There are two kinds of protocol fees:
   * - Flash loan fees: charged on all flash loans, as a percentage of the amounts borrowed
   *
   * - Swap fees: a percentrage of the fees charged by Pools when performing swaps. For a number of reason, including
   * swap gas gosts and interface simplicity, protocol swap fees are not charged on each individual swap. Rather,
   * Pools are expected to keep track of how much they have charged in swap fees, and pay any outstanding debts to the
   * Vault when they are joined or exited. This prevents users from joining a Pool with unpaid debt, as well as exiting
   * a Pool in debt without first paying their share.
   */

  /**
   * @dev Returns the current protocol fee module
   */
  function getProtocolFeesCollector() external view returns (IProtocolFeesCollector);
}
