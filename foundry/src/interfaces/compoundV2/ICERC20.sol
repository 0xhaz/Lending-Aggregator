// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title ICERC20
 * @notice Interface to interact with CompoundV2 cTokens
 */

import {ICToken} from "./ICToken.sol";

interface ICERC20 is ICToken {
  function mint(uint256 amount) external returns (uint256);

  function repayBorrow(uint256 amount) external returns (uint256);

  function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);
}
