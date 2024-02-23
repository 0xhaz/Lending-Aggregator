// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IProtocolFeesCollector
 *
 * @notice Required interface to estimate cost of flashloan in Balancer
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IProtocolFeesCollector {
  event FlashLoanFeePercentageChanged(uint256 newFlashLoanFeePercentage);

  function getFlashloanFeePercentrage() external view returns (uint256);
}
