// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {MockingSetup} from "../MockingSetup.sol";
import {MockRoutines} from "../MockRoutines.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";
import {MockFlasher} from "../../../src/mocks/MockFlasher.sol";
import {MockOracle} from "../../../src/mocks/MockOracle.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {ISwapper} from "../../../src/interfaces/ISwapper.sol";
import {MockSwapper} from "../../../src/mocks/MockSwapper.sol";
import {IFlasher} from "../../../src/interfaces/IFlasher.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BorrowingVault} from "../../../src/vaults//borrowing/BorrowingVault.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {LiquidationManager} from "../../../src/LiquidationManager.sol";

contract VaultLiquidationUnitTests is MockingSetup, MockRoutines {
  uint256 public constant TREASURY_PK = 0xF;
  address public TREASURY = vm.addr(TREASURY_PK);
  uint256 public constant KEEPER_PK = 0xE;
  address public KEEPER = vm.addr(KEEPER_PK);

  IFlasher public flasher;
  ISwapper public swapper;

  LiquidationManager public liquidationManager;

  uint8 public constant DEBT_DECIMALS = 18;
  uint8 public constant ASSET_DECIMALS = 18;

  function setUp() public {
    flasher = new MockFlasher();

    bytes memory executionCall =
      abi.encodeWithSelector(chief.allowFlasher.selector, address(flasher), true);
    _callWithTimelock(address(chief), executionCall);

    swapper = new MockSwapper(oracle);
    executionCall = abi.encodeWithSelector(chief.allowSwapper.selector, address(swapper), true);
    _callWithTimelock(address(chief), executionCall);

    liquidationManager = new LiquidationManager(address(chief), TREASURY);
    _grantRoleChief(LIQUIDATOR_ROLE, address(liquidationManager));

    executionCall =
      abi.encodeWithSelector(liquidationManager.allowExecutor.selector, address(KEEPER), true);
    _callWithTimelock(address(liquidationManager), executionCall);
  }

  function mock_getPriceOf(address asset1, address asset2, uint256 price) internal {
    vm.mockCall(
      address(oracle),
      abi.encodeWithSelector(MockOracle.getPriceOf.selector, asset1, asset2, 18),
      abi.encode(price)
    );
  }

  function _utils_getLiquidationThresholdValue(
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
      "Price, deposit, and borrowAmount should be 1e18"
    );
    return (price - ((borrowAmount * 1e36) / (deposit * DEFAULT_LIQ_RATIO)));
  }

  function test_liquidateMax(uint256 borrowAmount) public {
    uint256 currentPrice = oracle.getPriceOf(debtAsset, collateralAsset, 18);
    uint256 minAmount = (vault.minAmount() * currentPrice) / 1e18;

    vm.assume(borrowAmount > minAmount && borrowAmount < USD_PER_ETH_PRICE);

    uint256 maxltv = vault.maxLtv();
    uint256 unsafeAmount = (borrowAmount * 105 * 1e36) / (currentPrice * maxltv * 100);

    do_depositAndBorrow(unsafeAmount, borrowAmount, vault, ALICE);

    // Simulate 25% price drop
    // enough for user to be liquidated
    // liquidation is still profitable
    uint256 liquidationPrice = (currentPrice * 75) / 100; // 25% drop
    uint256 inversePrice = (1e18 / liquidationPrice) * 1e18; // 25% increase

    mock_getPriceOf(collateralAsset, debtAsset, inversePrice);
    mock_getPriceOf(debtAsset, collateralAsset, liquidationPrice);

    // check balance of alice
    assertEq(IERC20(collateralAsset).balanceOf(ALICE), 0);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
    assertEq(vault.balanceOf(ALICE), unsafeAmount);
    assertEq(vault.balanceOfDebt(ALICE), borrowAmount);

    // check balance of treasury
    assertEq(IERC20(collateralAsset).balanceOf(TREASURY), 0);
    assertEq(IERC20(debtAsset).balanceOf(TREASURY), 0);

    // liquidate alice
    address[] memory users = new address[](1);
    users[0] = ALICE;
    // do not specify a liquidation close factor
    uint256[] memory liqCloseFactors = new uint256[](users.length);
    liqCloseFactors[0] = 0;
    vm.startPrank(address(KEEPER));
    liquidationManager.liquidate(users, liqCloseFactors, vault, borrowAmount, flasher, swapper);
    vm.stopPrank();

    // check balance of alice
    assertEq(IERC20(collateralAsset).balanceOf(ALICE), 0);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
    assertEq(vault.balanceOf(ALICE), 0);
    assertEq(vault.balanceOfDebt(ALICE), 0);

    // check balance of treasury
    uint256 collectedAmount = unsafeAmount - (borrowAmount * 1e18 / liquidationPrice);

    assertEq(IERC20(collateralAsset).balanceOf(TREASURY), collectedAmount);
    assertEq(IERC20(debtAsset).balanceOf(TREASURY), 0);
  }

  function test_liquidateDefault(uint256 priceDrop) public {
    uint256 amount = 1 ether;
    uint256 borrowAmount = 1000e18;

    // Make price in 1e18 decimals
    uint256 scaledUSDPerETHPrice = USD_PER_ETH_PRICE * 1e10;

    vm.assume(
      priceDrop > _utils_getLiquidationThresholdValue(scaledUSDPerETHPrice, amount, borrowAmount)
    );

    uint256 price = oracle.getPriceOf(debtAsset, collateralAsset, 18);
    uint256 priceDropThresholdToMaxLiq =
      price - ((95e16 * borrowAmount * 1e18) / (amount * DEFAULT_LIQ_RATIO));
    uint256 priceDropThresholdToDiscountLiq =
      price - ((100e16 * borrowAmount * 1e18) / (amount * DEFAULT_LIQ_RATIO));

    //   priceDrop between threshold
    priceDrop = bound(priceDrop, priceDropThresholdToDiscountLiq, priceDropThresholdToMaxLiq - 1250);

    do_depositAndBorrow(amount, borrowAmount, vault, ALICE);

    // price drop, putting HF < 100, but above 95 and the close factor to 50%
    uint256 newPrice = price - priceDrop;

    mock_getPriceOf(collateralAsset, debtAsset, 1e18 / newPrice);
    mock_getPriceOf(debtAsset, collateralAsset, newPrice);

    // check balance of alice
    assertEq(IERC20(collateralAsset).balanceOf(ALICE), 0);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
    assertEq(vault.balanceOf(ALICE), amount);
    assertEq(vault.balanceOfDebt(ALICE), borrowAmount);

    // check balance of treasury
    assertEq(IERC20(collateralAsset).balanceOf(TREASURY), 0);
    assertEq(IERC20(debtAsset).balanceOf(TREASURY), 0);
    assertEq(vault.balanceOf(TREASURY), 0);
    assertEq(vault.balanceOfDebt(TREASURY), 0);

    // liquidate alice
    address[] memory users = new address[](1);
    users[0] = ALICE;
    // do not specify a liquidation close factor
    uint256[] memory liqCloseFactors = new uint256[](users.length);
    liqCloseFactors[0] = 0;
    vm.startPrank(address(KEEPER));
    liquidationManager.liquidate(
      users, liqCloseFactors, vault, borrowAmount * 0.5e18 / 1e18, flasher, swapper
    );
    vm.stopPrank();

    // check balance of alice
    assertEq(IERC20(collateralAsset).balanceOf(ALICE), 0);
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);

    uint256 discountedPrice = (newPrice * 0.9e18) / 1e18; // 10% discount
    uint256 amountGivenToLiquidator = (borrowAmount * 0.5e18) / discountedPrice;

    if (amountGivenToLiquidator >= amount) {
      amountGivenToLiquidator = amount;
    }

    assertEq(vault.balanceOf(ALICE), amount - amountGivenToLiquidator);
    assertEq(vault.balanceOfDebt(ALICE), borrowAmount / 2);

    uint256 amountToRepayFlashloan = (borrowAmount * 0.5e18 / newPrice);

    // check balance of treasury
    assertEq(
      IERC20(collateralAsset).balanceOf(TREASURY), amountGivenToLiquidator - amountToRepayFlashloan
    );
    assertEq(IERC20(debtAsset).balanceOf(TREASURY), 0);
    assertEq(vault.balanceOf(TREASURY), 0);
    assertEq(vault.balanceOfDebt(TREASURY), 0);
  }
}
