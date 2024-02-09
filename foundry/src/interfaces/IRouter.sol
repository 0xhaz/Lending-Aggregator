// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IRouter
 * @notice Define the interface for router operations
 */
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IRouter {
  /// @dev List of actions allowed to be executed by the router
  enum Action {
    Deposit,
    Withdraw,
    Borrow,
    Payback,
    Flashloan,
    Swap,
    PermitWithdraw,
    PermitBorrow,
    XTransfer,
    XTransferWithCall,
    DepositETH,
    WithdrawETH
  }

  /**
   * @notice An entry-point function that executes encoded commands along with provider inputs
   * @param actions List of actions to execute in a row
   * @param args an array of encoded arguments for each action
   */
  function xBundle(Action[] memory actions, bytes[] memory args) external payable;

  /**
   * @notice Similar to `xBundle()` but with an additional argumetns for flash loan
   * @param actions List of actions to execute in a row
   * @param args an array of encoded arguments for each action
   * @param flashloanAsset being sent by IFlasher
   * @param amount of flashloanAsset being sent by IFlasher
   */
  function xBundleFlashloan(
    Action[] memory actions,
    bytes[] memory args,
    address flashloanAsset,
    uint256 amount
  )
    external
    payable;

  /**
   * @notice Sweeps accidental ERC-20 transfers to this contract or stuck funds
   * due to failed cross-chain transfers (cf. ConnextRouter)
   * @param token address of ERC-20 token to sweep
   * @param receiver address of the receiver to send the funds to
   */
  function sweepToken(ERC20 token, address receiver) external;

  /**
   * @notice Sweeps accidental ETH transfers to this contract or stuck funds
   * @param receiver address of the receiver to send the funds to
   */
  function sweepETH(address receiver) external;
}
