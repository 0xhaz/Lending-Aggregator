// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title ProxyReceiver
 * @notice This contract helps forward ether or equivalent evm native token
 * using `address.call{value: x}()` for old implementations that still
 * use gas restricted obsolete methods such `address.send()` or `address.transfer()`
 */

import {ICToken} from "../interfaces/compoundV2/ICToken.sol";

contract ProxyReceiver {
  /**
   * @notice Receives a certain amount of assets
   * @dev This function is used the integration of some protocols because the withdraw function runs out of gas
   * This is used to withdraw the collateral and later on transfer it to the intended user through the withdraw function
   */
  receive() external payable {}

  /**
   * @notice Withdraw native and transfer to msg.sender
   *
   * @param amount integer amount to withdraw
   * @param cToken ICToken to interact with
   *
   * @dev msg.sender needs to transfer before calling this withdraw
   */
  function withdraw(uint256 amount, ICToken cToken) external {
    require(cToken.redeemUnderlying(amount) == 0, "Withdraw failed");

    (bool success,) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
  }
}
