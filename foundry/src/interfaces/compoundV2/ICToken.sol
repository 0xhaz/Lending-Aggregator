// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title ICToken
 * @notice General base interface to interact with Compound V2 cTokens
 * This interface is inherited in other Compound interfaces
 */

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICToken is IERC20 {
  function getCash() external view returns (uint256);

  function totalBorrows() external view returns (uint256);

  function totalReserves() external view returns (uint256);

  function redeemUnderlying(uint256) external returns (uint256);

  function borrow(uint256 amount) external returns (uint256);

  function exchangeRateStored() external view returns (uint256);

  function borrowRatePerBlock() external view returns (uint256);

  function supplyRatePerBlock() external view returns (uint256);

  function accrualBlockNumber() external view returns (uint256);

  function borrowIndex() external view returns (uint256);

  function borrowBalanceStored(address account) external view returns (uint256);

  function borrowBalanceCurrent(address account) external returns (uint256);

  function reserveFactorMantissa() external view returns (uint256);
}
