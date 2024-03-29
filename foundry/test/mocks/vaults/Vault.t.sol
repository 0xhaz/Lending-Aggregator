// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockingSetup} from "../MockingSetup.sol";
import {MockRoutines} from "../MockRoutines.sol";
import {MockOracle} from "../../../src/mocks/MockOracle.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {ILendingProvider} from "../../../src/interfaces/ILendingProvider.sol";
import {BorrowingVault} from "../../../src/vaults/borrowing/BorrowingVault.sol";
import {BaseVault} from "../../../src/abstracts/BaseVault.sol";

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

  function test_Try_Transfer_Max_Redeem_Without_Repay(uint96 amount, uint96 borrowAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(amount > minAmount && borrowAmount > 0 && _utils_checkMaxLTV(amount, borrowAmount));
    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);
    uint256 maxTransferable = vault.maxRedeem(ALICE);

    vm.prank(ALICE);
    vault.transfer(BOB, maxTransferable);
    assertEq(vault.balanceOf(BOB), maxTransferable);

    uint256 nonTransferable = amount - maxTransferable;

    vm.expectRevert(BorrowingVault.BorrowingVault__beforeTokenTransfer_moreThanMax.selector);
    vm.prank(ALICE);
    vault.transfer(BOB, nonTransferable);

    // Bob's shares havent change
    assertEq(vault.balanceOf(BOB), maxTransferable);
  }

  function test_Set_Min_Amount(uint256 min) public {
    vm.prank(chief.timelock());
    vm.expectEmit(true, false, false, false);
    emit MinAmountChanged(min);
    vault.setMinAmount(min);
  }

  function test_Try_Less_Than_Min_Amount(uint128 min, uint128 amount) public {
    vm.assume(min > 0 && amount > 0 && amount < min);
    bytes memory encodedWithSelectorData = abi.encodeWithSelector(vault.setMinAmount.selector, min);
    _callWithTimelock(address(vault), encodedWithSelectorData);

    vm.expectRevert(BaseVault.BaseVault__deposit_lessThanMin.selector);
    vm.prank(ALICE);
    vault.deposit(amount, ALICE);
  }

  function test_Get_Health_Factor(uint40 amount, uint40 borrowamount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(amount > minAmount && borrowamount > 0 && _utils_checkMaxLTV(amount, borrowamount));

    uint256 HF = vault.getHealthFactor(ALICE);
    assertEq(HF, type(uint256).max);

    do_depositAndBorrow(amount, borrowamount, vault, ALICE);

    uint256 HF2 = vault.getHealthFactor(ALICE);
    uint256 HF2_ = _utils_getHealthFactor(amount, borrowamount);

    assertEq(HF2, HF2_);
  }

  function test_Get_Liquidation_Factor(uint256 priceDrop) public {
    uint256 amount = 1 ether;
    uint256 borrowAmount = 1000e18; // 1000 DAI
    // Make price in 1e18 decimals
    uint256 scaledUSDPerETHPrice = USD_PER_ETH_PRICE * 1e10;
    vm.assume(priceDrop > get_PriceDropToLiquidation(scaledUSDPerETHPrice, amount, borrowAmount));
    // This bound priceDrop using 788e18
    // It means ETH price is dropping anywhere between $788 usd/ETH and USD_PER_ETH_PRICE
    priceDrop = bound(priceDrop, 788e18, scaledUSDPerETHPrice);

    uint256 price = oracle.getPriceOf(debtAsset, collateralAsset, DEBT_DECIMALS);

    uint256 priceDropThresholdToMaxLiq =
      price - ((95e16 * borrowAmount * 1e18) / (amount * DEFAULT_LIQ_RATIO));

    uint256 liquidatorFactor_0 = vault.getLiquidationFactor(ALICE);
    assertEq(liquidatorFactor_0, 0);

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    uint256 liquidatorFactor_1 = vault.getLiquidationFactor(ALICE);
    assertEq(liquidatorFactor_1, 0);

    if (priceDrop > priceDropThresholdToMaxLiq) {
      uint256 newPrice = (price - priceDrop);
      mock_setPriceOf(debtAsset, collateralAsset, newPrice);
      uint256 liquidatorFactor = vault.getLiquidationFactor(ALICE);
      assertEq(liquidatorFactor, 1e18);
    } else {
      uint256 newPrice = (price - priceDrop);
      mock_setPriceOf(debtAsset, collateralAsset, newPrice);
      uint256 liquidatorFactor = vault.getLiquidationFactor(ALICE);
      assertEq(liquidatorFactor, 0.5e18);
    }
  }

  function test_Try_Liquidate_Healthy(uint96 amount, uint96 borrowAmount) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(amount > minAmount && borrowAmount > 0 && _utils_checkMaxLTV(amount, borrowAmount));
    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    vm.expectRevert(BorrowingVault.BorrowingVault__liquidate_positionHealthy.selector);
    vm.prank(BOB);
    vault.liquidate(ALICE, BOB, 1e18);
  }

  function test_Liquidiate_Max(uint256 borrowAmount) public {
    uint256 currentPrice = oracle.getPriceOf(debtAsset, collateralAsset, DEBT_DECIMALS);
    uint256 minAmount = (vault.minAmount() * currentPrice) / 1e18;

    vm.assume(borrowAmount > minAmount && borrowAmount < USD_PER_ETH_PRICE);

    uint256 maxltv = vault.maxLtv();
    uint256 unsafeAmount = (borrowAmount * 105 * 1e36) / (currentPrice * maxltv * 100);

    do_depositAndBorrow(unsafeAmount, borrowAmount, vault, ALICE);

    // Simulate 90% price drop
    uint256 liquidationPrice = (currentPrice * 10) / 100;
    uint256 inversePrice = (1e18 / liquidationPrice) * 1e18;

    mock_setPriceOf(collateralAsset, debtAsset, inversePrice);
    mock_setPriceOf(debtAsset, collateralAsset, liquidationPrice);

    _dealMockERC20(debtAsset, BOB, borrowAmount);

    assertEq(IERC20(collateralAsset).balanceOf(ALICE), 0);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
    assertEq(vault.balanceOf(ALICE), unsafeAmount);
    assertEq(vault.balanceOfDebt(ALICE), borrowAmount);

    assertEq(IERC20(collateralAsset).balanceOf(BOB), 0);
    assertEq(IERC20(debtAsset).balanceOf(BOB), borrowAmount);
    assertEq(vault.balanceOf(BOB), 0);
    assertEq(vault.balanceOfDebt(BOB), 0);

    vm.startPrank(BOB);
    IERC20(debtAsset).approve(address(vault), borrowAmount);
    vault.liquidate(ALICE, BOB, 1e18);
    vm.stopPrank();

    assertEq(IERC20(collateralAsset).balanceOf(ALICE), 0);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
    assertEq(vault.balanceOf(ALICE), 0);
    assertEq(vault.balanceOfDebt(ALICE), 0);

    assertEq(IERC20(collateralAsset).balanceOf(BOB), 0);
    assertEq(IERC20(debtAsset).balanceOf(BOB), 0);
    assertEq(vault.balanceOf(BOB), unsafeAmount);
    assertEq(vault.balanceOfDebt(BOB), 0);
  }

  function test_Liquidate_Default(uint256 priceDrop) public {
    uint256 amount = 1 ether;
    uint256 borrowAmount = 1000e18; // 1000 DAI

    // Make price in 1e18 decimals
    uint256 scaledUSDPerETHPrice = USD_PER_ETH_PRICE * 1e10;

    vm.assume(priceDrop > get_PriceDropToLiquidation(scaledUSDPerETHPrice, amount, borrowAmount));

    uint256 price = oracle.getPriceOf(debtAsset, collateralAsset, DEBT_DECIMALS);
    uint256 priceDropThresholdToMaxLiq =
      price - ((95e16 * borrowAmount * 1e18) / (amount * DEFAULT_LIQ_RATIO));
    uint256 priceDropThresholdToDiscountLiq =
      price - ((100e16 * borrowAmount * 1e18) / (amount * DEFAULT_LIQ_RATIO));

    //   priceDrop between threshold
    priceDrop = bound(priceDrop, priceDropThresholdToDiscountLiq, priceDropThresholdToMaxLiq - 1250);

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    // price drop, putting HF < 100, but aboce 95 and the close factor at 50%
    uint256 newPrice = price - priceDrop;

    mock_setPriceOf(collateralAsset, debtAsset, 1e18 / newPrice);
    mock_setPriceOf(debtAsset, collateralAsset, newPrice);
    uint256 liquidatorAmount = borrowAmount;
    _dealMockERC20(debtAsset, BOB, liquidatorAmount);

    assertEq(IERC20(collateralAsset).balanceOf(ALICE), 0);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
    assertEq(vault.balanceOf(ALICE), amount);
    assertEq(vault.balanceOfDebt(ALICE), borrowAmount);
    assertEq(IERC20(collateralAsset).balanceOf(BOB), 0);
    assertEq(IERC20(debtAsset).balanceOf(BOB), liquidatorAmount);
    assertEq(vault.balanceOf(BOB), 0);
    assertEq(vault.balanceOfDebt(BOB), 0);

    vm.startPrank(BOB);
    IERC20(debtAsset).approve(address(vault), liquidatorAmount);
    vault.liquidate(ALICE, BOB, 0.5e18);
    vm.stopPrank();

    assertEq(IERC20(collateralAsset).balanceOf(ALICE), 0);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);

    uint256 discountedPrice = (newPrice * 0.9e18) / 1e18;
    uint256 amountGivenToLiquidator = (borrowAmount * 0.5e18) / discountedPrice;

    if (amountGivenToLiquidator >= amount) {
      amountGivenToLiquidator = amount;
    }

    assertEq(vault.balanceOf(ALICE), amount - amountGivenToLiquidator);
    assertEq(vault.balanceOfDebt(ALICE), borrowAmount / 2);

    assertEq(IERC20(collateralAsset).balanceOf(BOB), 0);
    assertEq(IERC20(debtAsset).balanceOf(BOB), liquidatorAmount - (borrowAmount / 2));
    assertEq(vault.balanceOf(BOB), amountGivenToLiquidator);
    assertEq(vault.balanceOfDebt(BOB), 0);
  }

  function test_Borrow_Invalid_Input() public {
    uint256 borrowAmount = 1000e18;
    uint256 invalidBorrowAmount = 0;
    address invalidAddress = address(0);

    // invalid debt
    vm.expectRevert(BorrowingVault.BorrowingVault__borrow_invalidInput.selector);
    vault.borrow(invalidBorrowAmount, ALICE, BOB);

    // invalid receiver
    vm.expectRevert(BorrowingVault.BorrowingVault__borrow_invalidInput.selector);
    vault.borrow(borrowAmount, invalidAddress, BOB);

    // invalid owner
    vm.expectRevert(BorrowingVault.BorrowingVault__borrow_invalidInput.selector);
    vault.borrow(borrowAmount, ALICE, invalidAddress);
  }

  function test_Borrow_More_Than_Allowed(uint96 invalidBorrowAmount) public {
    uint96 amount = 1 ether;
    vm.assume(invalidBorrowAmount > 0 && !_utils_checkMaxLTV(amount, invalidBorrowAmount));

    do_deposit(amount, vault, ALICE);

    vm.expectRevert(BorrowingVault.BorrowingVault__borrow_moreThanAllowed.selector);
    vault.borrow(invalidBorrowAmount, ALICE, ALICE);
  }

  function test_Withdraw_Invalid_Input() public {
    uint256 amount = 1 ether;
    uint256 invalid = 0;

    do_deposit(amount, vault, ALICE);

    vm.startPrank(ALICE);
    // invalid amount
    vm.expectRevert(BaseVault.BaseVault__withdraw_invalidInput.selector);
    vault.withdraw(invalid, ALICE, ALICE);

    // invalid receiver
    vm.expectRevert(BaseVault.BaseVault__withdraw_invalidInput.selector);
    vault.withdraw(amount, address(0), ALICE);

    // invalid owner
    vm.expectRevert(BaseVault.BaseVault__withdraw_invalidInput.selector);
    vault.withdraw(amount, ALICE, address(0));
    vm.stopPrank();
  }

  function test_Redeem_Invalid_Input() public {
    uint256 amount = 1 ether;
    uint256 invalid = 0;

    do_deposit(amount, vault, ALICE);

    vm.startPrank(ALICE);
    // invalid amount
    vm.expectRevert(BaseVault.BaseVault__withdraw_invalidInput.selector);
    vault.redeem(invalid, ALICE, ALICE);

    // invalid receiver
    vm.expectRevert(BaseVault.BaseVault__withdraw_invalidInput.selector);
    vault.redeem(amount, address(0), ALICE);

    // invalid owner
    vm.expectRevert(BaseVault.BaseVault__withdraw_invalidInput.selector);
    vault.redeem(amount, ALICE, address(0));
    vm.stopPrank();
  }

  function test_Payback_Invalid_Input() public {
    uint256 amount = 1 ether;
    uint256 borrowAmount = 1000e18;
    uint256 invalidDebt = 0;

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    // invalid debt
    vm.expectRevert(BorrowingVault.BorrowingVault__payback_invalidInput.selector);
    vault.payback(invalidDebt, ALICE);

    // invalid owner
    vm.expectRevert(BorrowingVault.BorrowingVault__payback_invalidInput.selector);
    vault.payback(borrowAmount, address(0));
  }

  function test_Burn_Debt_Invalid_Input() public {
    uint256 amount = 1 ether;
    uint256 borrowAmount = 1000e18;
    uint256 invalidDebt = 0;

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    vm.startPrank(ALICE);
    // invalid debt
    vm.expectRevert(BorrowingVault.BorrowingVault__payback_invalidInput.selector);
    vault.payback(invalidDebt, ALICE);

    // invalid owner
    vm.expectRevert(BorrowingVault.BorrowingVault__payback_invalidInput.selector);
    vault.payback(borrowAmount, address(0));
    vm.stopPrank();
  }

  function test_Payback_More_Than_Max(uint256 amountPayback) public {
    uint256 amount = 1 ether;
    uint256 borrowAmount = 1000e18;
    vm.assume(amountPayback > borrowAmount);

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    // NOTE: we use deal() instead of _dealMockERC20
    // using the false arg for `totalSupply` update
    // in order to be capable of fuzzing very large numbers
    deal(debtAsset, address(this), amountPayback, false);
    IERC20(debtAsset).approve(address(vault), amountPayback);
    vault.payback(amountPayback, ALICE);
    assertEq(vault.balanceOfDebt(ALICE), 0);
    assertEq(vault.balanceOfDebtShares(ALICE), 0);
  }

  function test_Liquidate_Invalid_Input() public {
    vm.expectRevert(BorrowingVault.BorrowingVault__liquidate_invalidInput.selector);
    vault.liquidate(ALICE, address(0), 1e18);
  }

  function test_Withdraw_When_Full_Debt_Is_Payback_Externally(uint256 amount) public {
    vm.assume(amount > 1e6 && amount < 1000000 ether);

    address TROUBLEMAKER = vm.addr(0x1122);
    vm.label(TROUBLEMAKER, "TROUBLEMAKER");

    // Alice deposits and borrows
    uint256 price = oracle.getPriceOf(debtAsset, collateralAsset, DEBT_DECIMALS);
    uint256 borrowAmount = amount * price * DEFAULT_MAX_LTV / 1e36;
    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    // We fake that a Troublemaker payback full the vault's debt externally
    uint256 fullPaybackAmount =
      mockProvider.getBorrowBalance(address(vault), IVault(address(vault)));
    _dealMockERC20(debtAsset, TROUBLEMAKER, fullPaybackAmount);
    vm.startPrank(TROUBLEMAKER);
    IERC20(debtAsset).transfer(address(vault), fullPaybackAmount);
    mockProvider.payback(fullPaybackAmount, IVault(address(vault)));
    vm.stopPrank();

    assertEq(vault.balanceOf(ALICE), amount);
    assertEq(vault.balanceOfDebtShares(ALICE), borrowAmount);
    assertEq(vault.balanceOfDebt(ALICE), 1);

    // Bob now deposits and borrow after debt has been paid back
    // To ensure there is no DOS due to payback
    do_depositAndBorrow(amount, borrowAmount, vault, BOB);

    // Withdraw should not fail
    uint256 maxAmount = vault.maxRedeem(ALICE);
    vm.prank(ALICE);
    vault.redeem(maxAmount, ALICE, ALICE);

    assertEq(IERC20(collateralAsset).balanceOf(ALICE), maxAmount);
  }
}
