// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IWETH9
 * @notice Abstract contract of add-on functions of a typical ERC20 wrapped native token
 */

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract IWETH9 is ERC20 {
  // @notice Deposit ether to get wrapped ether
  function deposit() external payable virtual;

  // @notice Withdraw wrapped ether to get ether
  function withdraw(uint256) external virtual;
}
