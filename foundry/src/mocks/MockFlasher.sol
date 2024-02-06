// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title MockFlasher
 * @notice Mock contract for testing flashloan operations
 * @dev Mock mints the flashloaned amount and charges no fee
 */

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFlasher} from "../interfaces/IFlasher.sol";
import {MockERC20} from "./MockERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract MockFlasher is IFlasher {
  using SafeERC20 for IERC20;
  using Address for address;

  // @inheritdoc IFlasher
  function initiateFlashLoan(
    address asset,
    uint256 amount,
    address requestor,
    bytes memory requestorCalldata
  )
    external
  {
    MockERC20(asset).mint(address(this), amount);
    IERC20(asset).safeTransfer(requestor, amount);
    requestor.functionCall(requestorCalldata);
  }

  /// @inheritdoc IFlasher
  function getFlashloanSourceAddr(address) external view override returns (address) {
    return address(this);
  }

  /// @inheritdoc IFlasher
  function computeFlashloanFee(address, uint256) external pure override returns (uint256) {
    return 0;
  }
}
