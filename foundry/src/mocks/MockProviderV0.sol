// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title MockProviderV0
 * @notice Mock implementation of a lending provider
 * used only in Connext forking testnets environments
 */

import {ILendingProvider} from "../interfaces/ILendingProvider.sol";
import {IVault} from "../interfaces/IVault.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockProviderV0 is ILendingProvider {
  // @inheritdoc ILendingProvider
  function providerName() public pure override returns (string memory) {
    return "Mock_V0";
  }

  // @inheritdoc ILendingProvider

  function approvedOperator(
    address,
    address,
    address
  )
    external
    pure
    override
    returns (address operator)
  {
    operator = address(0xAbc123);
  }

  // @inheritdoc ILendingProvider
  function deposit(uint256, IVault) external pure override returns (bool success) {
    success = true;
  }

  // @inheritdoc ILendingProvider
  function borrow(uint256 amount, IVault vault) external override returns (bool success) {
    MockERC20(vault.debtAsset()).mintDebt(address(vault), amount, providerName());
    success = true;
  }

  // @inheritdoc ILendingProvider
  function withdraw(uint256 amount, IVault vault) external override returns (bool success) {
    MockERC20(vault.asset()).mint(address(vault), amount);
    success = true;
  }

  // @inheritdoc ILendingProvider
  function payback(uint256 amount, IVault vault) external override returns (bool success) {
    MockERC20(vault.debtAsset()).burnDebt(address(vault), amount, providerName());
    success = true;
  }

  // @inheritdoc ILendingProvider
  function getDepositRateFor(IVault) external pure override returns (uint256 rate) {
    rate = 1e27; // 1:1
  }

  // @inheritdoc ILendingProvider
  function getBorrowRateFor(IVault) external pure override returns (uint256 rate) {
    rate = 1e27; // 1:1
  }

  // @inheritdoc ILendingProvider
  function getDepositBalance(
    address user,
    IVault vault
  )
    external
    view
    override
    returns (uint256 balance)
  {
    balance = MockERC20(vault.asset()).balanceOf(user);
  }

  // @inheritdoc ILendingProvider
  function getBorrowBalance(
    address user,
    IVault vault
  )
    external
    view
    override
    returns (uint256 balance)
  {
    balance = MockERC20(vault.debtAsset()).balanceOfDebt(user, providerName());
  }
}
