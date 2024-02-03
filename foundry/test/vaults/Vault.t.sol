// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockingSetup} from "../MockingSetup.sol";
import {MockRoutines} from "../MockRoutines.sol";
import {MockOracle} from "../../src/mocks/MockOracle.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {ILendingProvider} from "../../src/interfaces/ILendingProvider.sol";
import {BorrowingVault} from "../../src/vaults/borrowing/BorrowingVault.sol";
import {BaseVault} from "../../src/abstracts/BaseVault.sol";

contract VaultUnitTest is MockingSetup, MockRoutines {
  event MinAmountChanged(uint256 newMinAmount);
  event DepositCapChanged(uint256 newDepositCap);

  uint8 public constant DEBT_DECIMALS = 18;
  uint8 public constant ASSET_DECIMALS = 18;

  function setUp() public {
    _grantRoleChief(LIQUIDATOR_ROLE, BOB);
  }

  function mock_setPriceOf(address asset1, address asset2, uint256 price) internal {
    vm.mockCall(
      address(oracle),
      abi.encodeWithSelector(MockOracle.getPriceOf.selector, asset1, asset2, 18),
      abi.encode(price)
    );
  }

  function _utils_getHealthFactor(
    uint96 amount,
    uint96 borrowAmount
  )
    internal
    view
    returns (uint256)
  {
    uint256 price = oracle.getPriceOf(debtAsset, collateralAsset, DEBT_DECIMALS);
    return (amount * DEFAULT_LIQ_RATIO * price) / (borrowAmount * 10 ** ASSET_DECIMALS);
  }

  function _utils_getFutureHealthFactor(
    uint96 amount,
    uint96 borrowAmount,
    uint80 priceDrop
  )
    internal
    view
    returns (uint256)
  {
    uint256 priceBefore = oracle.getPriceOf(debtAsset, collateralAsset, DEBT_DECIMALS);
    return (amount * DEFAULT_LIQ_RATIO * (priceBefore - priceDrop))
      / (borrowAmount * 1e16 * 10 ** ASSET_DECIMALS);
  }

  function get_PriceDropToLiquidation(
    uint256 price,
    uint256 deposit,
    uint256 borrowAmount
  )
    internal
    pure
    returns (uint256)
  {
    require(
      price / 1e18 > 0 && deposit / 1e18 > 0 && borrowAmount / 1e18 > 0,
      "VaultUnitTest: price, deposit, or borrowAmount should be 1e18"
    );
    return (price - ((borrowAmount * 1e36) / (deposit * DEFAULT_LIQ_RATIO)));
  }

  function _utils_checkLiquidateMaxFuture(
    uint96 amount,
    uint96 borrowAmount,
    uint80 priceDrop
  )
    internal
    view
    returns (bool)
  {
    uint256 price = oracle.getPriceOf(debtAsset, collateralAsset, DEBT_DECIMALS);
    uint256 hf = (amount * DEFAULT_LIQ_RATIO * (price - priceDrop))
      / (borrowAmount * 1e18 * 10 ** ASSET_DECIMALS);

    return hf <= 95;
  }

  function _utils_checkLiquidateDiscountFuture(
    uint96 amount,
    uint96 borrowAmount,
    uint80 priceDrop
  )
    internal
    view
    returns (bool)
  {
    uint256 price = oracle.getPriceOf(debtAsset, collateralAsset, DEBT_DECIMALS);
    uint256 hf = (amount * DEFAULT_LIQ_RATIO * (price - priceDrop))
      / (borrowAmount * 1e18 * 10 ** ASSET_DECIMALS);

    return hf > 95 && hf < 100;
  }

  function _utils_add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a && c >= b, "VaultUnitTest: addition overflow");
    return c;
  }

  function test_deposit(uint128 amount) public {
    vm.assume(amount > vault.minAmount());
    do_deposit(amount, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), amount);
  }

  function test_mint(uint128 shares) public {
    vm.assume(shares > vault.minAmount());
    do_mint(shares, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), shares);
  }

  function test_withdraw(uint128 amount) public {
    vm.assume(amount > vault.minAmount());
    do_deposit(amount, vault, ALICE);
    do_withdraw(amount, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), 0);
  }

  function test_redeem(uint128 shares) public {
    vm.assume(shares > vault.minAmount());
    do_mint(shares, vault, ALICE);
    do_redeem(shares, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), 0);
  }

  function test_Deposit_And_Borrow(uint96 amount, uint96 borrowAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(amount > minAmount && borrowAmount > 0 && _utils_checkMaxLTV(amount, borrowAmount));

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    assertEq(vault.totalDebt(), borrowAmount);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
  }

  function test_Deposit_Then_Mint_Debt(uint96 amount, uint96 borrowAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(amount > minAmount && borrowAmount > 0 && _utils_checkMaxLTV(amount, borrowAmount));

    do_deposit(amount, vault, ALICE);
    uint256 debtShares = vault.previewBorrow(borrowAmount);

    do_mintDebt(debtShares, vault, ALICE);

    assertEq(vault.totalDebt(), borrowAmount);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
  }

  function test_Payback_And_Withdraw(uint96 amount, uint96 borrowAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(amount > minAmount && borrowAmount > 0 && _utils_checkMaxLTV(amount, borrowAmount));

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    do_payback(borrowAmount, vault, ALICE);
    do_withdraw(amount, vault, ALICE);

    assertEq(vault.balanceOfDebt(ALICE), 0);
    assertEq(vault.balanceOf(ALICE), 0);
  }

  function test_Burn_Debt_Then_Withdraw(uint96 amount, uint96 borrowAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(amount > minAmount && borrowAmount > 0 && _utils_checkMaxLTV(amount, borrowAmount));

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    uint256 debtShares = vault.balanceOfDebtShares(ALICE);

    do_burnDebt(debtShares, vault, ALICE);
    do_withdraw(amount, vault, ALICE);

    assertEq(vault.balanceOfDebt(ALICE), 0);
    assertEq(vault.balanceOf(ALICE), 0);
  }

  function test_Try_Borrow_Without_Collateral(uint256 borrowAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(borrowAmount > minAmount);
    vm.expectRevert(BorrowingVault.BorrowingVault__borrow_moreThanAllowed.selector);

    vm.prank(ALICE);
    vault.borrow(borrowAmount, ALICE, ALICE);
  }

  function test_Withdraw_Max(uint128 amount, uint128 moreThanAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(moreThanAmount > amount && amount >= minAmount);
    do_deposit(amount, vault, ALICE);

    vm.prank(ALICE);
    vault.withdraw(moreThanAmount, ALICE, ALICE);

    // Default borrowing vault behavior when passing a higher than `maxWithdraw` amount
    // is to only withdraw max possible that user has deposited
    assertEq(IERC20((vault.asset())).balanceOf(ALICE), amount);
    assertEq(vault.balanceOf(ALICE), 0);
  }

  function test_Redeem_Max(uint128 shares, uint128 moreThanShares) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(moreThanShares > shares && shares >= minAmount);

    do_mint(shares, vault, ALICE);

    vm.prank(ALICE);
    vault.redeem(moreThanShares, ALICE, ALICE);

    // Default borrowing vault behavior when passing a higher than `maxRedeem` amount
    // is to only redeem max possible that user has minted
    assertEq(IERC20((vault.asset())).balanceOf(ALICE), shares);
    assertEq(vault.balanceOf(ALICE), 0);
  }

  function test_Withdraw_Max_Without_Repay(uint96 amount, uint96 borrowAmount) public {
    // 1e14 is a reasonable ETH amount, and 1e18 is above 1 usd for DAI
    // This was done to consider test that are not handling dust amounts
    vm.assume(amount > 1e14 && borrowAmount > 1e18 && _utils_checkMaxLTV(amount, borrowAmount));

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    uint256 aliceShares = vault.balanceOf(ALICE);
    uint256 maxWithdrawable = vault.maxWithdraw(ALICE);
    uint256 maxRedeemable = vault.maxRedeem(ALICE);

    vm.prank(ALICE);
    vault.withdraw(type(uint256).max, ALICE, ALICE);

    uint256 aliceSharesAfter = vault.balanceOf(ALICE);

    // Asset user received exactly the maxWithdrawable amount
    assertEq(IERC20((vault.asset())).balanceOf(ALICE), maxWithdrawable);
    // Asset user has remainder shares after maxWithdrawable amount
    assertEq(aliceSharesAfter, aliceShares - maxRedeemable);
  }

  function test_Redeem_Max_Without_Repay(uint96 amount, uint96 borrowAmount) public {
    // 1e14 is a reasonable ETH amount, and 1e18 is above 1 usd for DAI
    // This was done to consider test that are not handling dust amounts
    vm.assume(amount > 1e14 && borrowAmount > 1e18 && _utils_checkMaxLTV(amount, borrowAmount));

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    uint256 aliceShares = vault.balanceOf(ALICE);
    uint256 maxWithdrawable = vault.maxWithdraw(ALICE);
    uint256 maxRedeemable = vault.maxRedeem(ALICE);

    vm.prank(ALICE);
    vault.redeem(type(uint256).max, ALICE, ALICE);

    uint256 aliceSharesAfter = vault.balanceOf(ALICE);

    // Asset user received exactly the maxWithdrawable amount
    assertEq(IERC20((vault.asset())).balanceOf(ALICE), maxWithdrawable);
    // Asset user has remainder shares after maxWithdrawable amount
    assertEq(aliceSharesAfter, aliceShares - maxRedeemable);
  }

  function test_Try_Transfer_Without_Repay(uint96 amount, uint96 borrowAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(amount > minAmount && borrowAmount > 0 && _utils_checkMaxLTV(amount, borrowAmount));
    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    vm.expectRevert(BorrowingVault.BorrowingVault__beforeTokenTransfer_moreThanMax.selector);
    vm.prank(ALICE);
    vault.transfer(BOB, uint256(amount));
  }
}
