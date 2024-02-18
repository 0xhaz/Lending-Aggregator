// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import {console} from "forge-std/console.sol";
import {ForkingSetup2} from "../ForkingSetup2.sol";
import {Routines} from "../../utils/Routines.sol";
import {BorrowingVaultUpgradeable as BVault} from
  "../../../src/vaults/borrowing/BorrowingVaultUpgradeable.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {
  IV3Pool, AaveV3Goerli as SampleProvider
} from "../../../src/providers/goerli/AaveV3Goerli.sol";
import {ILendingProvider} from "../../../src/interfaces/ILendingProvider.sol";
import {ConnextRouter} from "../../../src/routers/ConnextRouter.sol";
import {ConnextHandler} from "../../../src/routers/ConnextHandler.sol";
import {ConnextReceiver} from "../../../src/routers/ConnextReceiver.sol";
import {IRouter} from "../../../src/interfaces/IRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

bool constant DEBUG = true;

contract ConnextRouterVaultIntegrations is Routines, ForkingSetup2 {
  error xReceiverFailed_recordedTransfer();

  using Math for uint256;

  BVault public vault;

  SampleProvider sprovider;

  ConnextHandler public connextHandler;
  ConnextReceiver public connextReceiver;

  uint256 internal constant DEPOSIT_AMOUNT = 0.25 ether;
  uint256 internal constant BORROW_AMOUNT = 998567;

  address collateralAsset;
  address debtAsset;

  function setUp() public {
    setUpNamedFork("goerli");

    sprovider = SampleProvider(getAddress("Aave_V3_Goerli"));
    vm.label(address(sprovider), "SampleProvider");

    setOrDeployChief(false);
    setOrDeployConnextRouter(false);
    setOrDeployFujiOracle(false);
    setOrDeployBorrowingVaultFactory(false, false);
    setOrDeployBorrowingVaults(false);

    vault = BVault(payable(allVaults[0].addr));
    console.log("Vault Address: %s", address(vault));

    collateralAsset = vault.asset();
    debtAsset = vault.debtAsset();

    console.log("Collateral Asset: %s", collateralAsset);
    console.log("Debt Asset: %s", debtAsset);

    connextHandler = connextRouter.handler();
    connextReceiver = ConnextReceiver(connextRouter.connextReceiver());

    console.log("ConnextHandler: %s", address(connextHandler));
    console.log("ConnextReceiver: %s", address(connextReceiver));

    vm.startPrank(address(timelock));
    // Assume the same address of xreceive in all domains
    connextRouter.setReceiver(GOERLI_DOMAIN, address(connextReceiver));
    connextRouter.setReceiver(OPTIMISM_GOERLI_DOMAIN, address(connextReceiver));
    connextRouter.setReceiver(MUMBAI_DOMAIN, address(connextReceiver));
    vm.stopPrank();
  }

  function test_Basic_Vault_Params_Initialized() public {
    address asset_ = vault.asset();
    address debtAsset_ = vault.debtAsset();
    uint256 maxltv_ = vault.maxLtv();
    uint256 liqRatio_ = vault.liqRatio();
    address oracle_ = address(vault.oracle());
    address activeProvider_ = address(vault.activeProvider());
    uint256 totalSupply_ = vault.totalSupply();
    uint256 debtSharesSupply_ = vault.debtSharesSupply();

    // console.log("asset: %s", asset_, "debtAsset: %s", debtAsset_);
    // console.log("maxLtv: %s", maxltv_, "liqRatio: %s", liqRatio_);
    // console.log("oracle: %s", oracle_, "activeProvider: %s", activeProvider_);
    // console.log("totalSupply: %s", totalSupply_, "debtSharesSupply: %s", debtSharesSupply_);

    assertNotEq(asset_, address(0));
    assertNotEq(debtAsset_, address(0));
    assertNotEq(oracle_, address(0));
    assertNotEq(activeProvider_, address(0));
    assertGt(maxltv_, 0);
    assertGt(liqRatio_, 0);
    assertGt(totalSupply_, 0);
    assertEq(debtSharesSupply_, 0);
  }

  function test_Basic_Connext_Router_Initialized() public {
    address chief_ = address(connextRouter.chief());
    address receiver_ = connextRouter.connextReceiver();
    address handler_ = address(connextRouter.handler());

    assertEq(chief_, address(chief));
    assertEq(receiver_, address(connextReceiver));
    assertEq(handler_, address(connextHandler));
  }

  function test_Attempt_Max_Payback_SDK_Overestimate() public {
    __doUnbalanceDebtToSharesRatio(address(vault));

    // Assume Alice already has a position in this domain
    do_depositAndBorrow(DEPOSIT_AMOUNT, BORROW_AMOUNT, IVault(address(vault)), ALICE);

    __closeBOB(address(vault));

    // Assume Alice debt for future assertion
    uint256 aliceDebtBefore = vault.balanceOfDebt(ALICE);
    uint256 aliceDebtSharesBefore = vault.balanceOfDebtShares(ALICE);
    if (DEBUG) {
      console.log("Alice original debt: %s", BORROW_AMOUNT);
      console.log("debtShare-to-debt-ratio-alteration");
      console.log("Alice Debt Before XCall: %s", aliceDebtBefore);
      console.log("Alice DebtShares Before XCall: %s", aliceDebtSharesBefore);
    }

    // From a separate domain ALICE wants to make a max payback
    // The SDK prepares the bundle for her
    IRouter.Action[] memory actions = new IRouter.Action[](1);
    bytes[] memory args = new bytes[](1);

    uint256 sdkAmount;
    uint256 feeAndSlippage;
    uint256 overEstimate = 1000 wei;

    {
      actions[0] = IRouter.Action.Payback;
      // We expect the SDK to estimate a buffer amount that includes:
      // - [ira] interest rate accrued buffer during time of xCall
      // - [cfee] the connext 5 bps fee
      // - [slippage] potential connext slippage
      // Therefore: estimate = ira + cfee + slippage
      feeAndSlippage = aliceDebtBefore.mulDiv(5, 1e4) + aliceDebtBefore.mulDiv(3, 1e3); // 0.5% + 0.3%
      uint256 buffer = overEstimate + feeAndSlippage;
      sdkAmount = aliceDebtBefore + buffer;
      args[0] = abi.encode(address(vault), sdkAmount, ALICE, address(connextRouter));
    }

    bytes memory callData = abi.encode(actions, args);

    // send directly the bridged funds to our xReceiver, thus simulating ConnextCore
    // behaviour. However, the final received amount is resultant
    // of deducting the Connext fee and slippage amount
    uint256 finalReceived;
    {
      finalReceived = sdkAmount - feeAndSlippage;
      deal(debtAsset, address(connextReceiver), finalReceived);
    }

    vm.startPrank(connextCore);
    // Call pretended from connextCore to connextReceiver from a separate domain (eg. optimism goerli)
    // simulated to be the same address as ConnextRouter in this test
    connextReceiver.xReceive(
      "0x01", finalReceived, debtAsset, address(connextRouter), OPTIMISM_GOERLI_DOMAIN, callData
    );
    vm.stopPrank();

    // Handler should have no funds
    if (IERC20(debtAsset).balanceOf(address(connextHandler)) > 0) {
      revert xReceiverFailed_recordedTransfer();
    }

    {
      // Assert Alice's debt is now zero by the amount in cross-tx
      uint256 aliceDebtAfter = vault.balanceOfDebt(ALICE);
      uint256 aliceDebtSharesAfter = vault.balanceOfDebtShares(ALICE);
      uint256 aliceUSDCBalanceAfter = IERC20(debtAsset).balanceOf(ALICE);

      assertEq(aliceDebtAfter, 0);
      assertEq(aliceDebtSharesAfter, 0);
      // Assert Alice has receive any overestimate
      assertEq(aliceUSDCBalanceAfter, BORROW_AMOUNT + overEstimate);

      if (DEBUG) {
        console.log(
          "Alice Debt After : %s",
          aliceDebtAfter,
          "Alice DebtShares After: %s",
          aliceDebtSharesAfter
        );
        console.log("Alice USDC Balance After: %s", aliceUSDCBalanceAfter);
      }
    }

    {
      // Check vault status
      //   uint256 vaultDebtSharesSupply = vault.debtSharesSupply();
      //   uint256 vaultDebtBalanceAtProvider =
      //     sprovider.getBorrowBalance(address(vault), IVault(address(vault)));

      //   assertEq(vaultDebtSharesSupply, 0);
      //   assertEq(vaultDebtBalanceAtProvider, 0);

      //   if (DEBUG) {
      //     console.log("Vault DebtShares Supply: %s", vaultDebtSharesSupply);
      //     console.log("Vault Debt Balance at Provider: %s", vaultDebtBalanceAtProvider);
      //   }
    }
  }

  function test_Attempt_Max_Payback_SDK_Underestimate() public {
    __doUnbalanceDebtToSharesRatio(address(vault));

    // Assume ALICE already has a position in this domain
    do_depositAndBorrow(DEPOSIT_AMOUNT, BORROW_AMOUNT, IVault(address(vault)), ALICE);

    __closeBOB(address(vault));

    // Record Alice debt for future assertion
    uint256 aliceDebtBefore = vault.balanceOfDebt(ALICE);
    uint256 aliceDebtSharesBefore = vault.balanceOfDebtShares(ALICE);

    if (DEBUG) {
      console.log("Alice original debt: %s", BORROW_AMOUNT);
      console.log("debtShare-to-debt-ratio-alteration");
      console.log("Alice Debt Before XCall: %s", aliceDebtBefore);
      console.log("Alice DebtShares Before XCall: %s", aliceDebtSharesBefore);
    }

    // From a separate domain ALICE wants to make a max payback
    // The SDK prepares the bundle for her
    IRouter.Action[] memory actions = new IRouter.Action[](1);
    bytes[] memory args = new bytes[](1);

    uint256 sdkAmount;
    uint256 feeAndSlippage;
    uint256 underEstimation = 99999 wei;
    {
      actions[0] = IRouter.Action.Payback;
      // We expet the SDK to estimate a buffer amount that includes:
      // - [ira] interest rate accrued buffer during time of xCall
      // - [cfee] the connext 5 bps fee
      // - [slippage] potential connext slippage
      // Therefore: estimate = ira + cfee + slippage
      feeAndSlippage = aliceDebtBefore.mulDiv(5, 1e4) + aliceDebtBefore.mulDiv(3, 1e3); // 0.5% + 0.3%
      sdkAmount = aliceDebtBefore + feeAndSlippage - underEstimation;
      args[0] = abi.encode(address(vault), sdkAmount, ALICE, address(connextRouter));
    }

    bytes memory callData = abi.encode(actions, args);

    // send directly the bridged funds to our xReceiver, thus simulating ConnextCore
    // behaviour. However, the final received amount is resultant
    // of deducting the Connext fee and slippage amount
    uint256 finalReceived;
    {
      finalReceived = sdkAmount - feeAndSlippage;
      deal(debtAsset, address(connextReceiver), finalReceived);
    }

    vm.startPrank(connextCore);
    // Call pretended from connextCore to connextReceiver from a separate domain (eg. optimism goerli)
    // simulated to be the same address as ConnextRouter in this test
    connextReceiver.xReceive(
      "0x01", finalReceived, debtAsset, address(connextRouter), OPTIMISM_GOERLI_DOMAIN, callData
    );

    // Handler should have no funds
    if (IERC20(debtAsset).balanceOf(address(connextHandler)) > 0) {
      revert xReceiverFailed_recordedTransfer();
    }

    {
      // Assert Alice's debt is now zero by the amount in cross-tx
      uint256 aliceDebtAfter = vault.balanceOfDebt(ALICE);
      uint256 aliceDebtSharesAfter = vault.balanceOfDebtShares(ALICE);
      uint256 aliceUSDCBalanceAfter = IERC20(debtAsset).balanceOf(ALICE);

      assertGt(aliceDebtAfter, 0);
      assertGt(aliceDebtSharesAfter, 0);
      // Assert ALICE has NOT receive any overestimate
      assertEq(aliceUSDCBalanceAfter, BORROW_AMOUNT);

      if (DEBUG) {
        console.log(
          "Alice Debt After : %s",
          aliceDebtAfter,
          "Alice DebtShares After: %s",
          aliceDebtSharesAfter
        );
        console.log("Alice USDC Balance After: %s", aliceUSDCBalanceAfter);
      }
    }
    // {
    //   // Check vault status
    //   uint256 vaultDebtSharesSupply = vault.debtSharesSupply();
    //   uint256 vaultDebtBalanceAtProvider =
    //     sprovider.getBorrowBalance(address(vault), IVault(address(vault)));

    //   assertGt(vaultDebtSharesSupply, 0);
    //   assertGt(vaultDebtBalanceAtProvider, 0);

    //   if (DEBUG) {
    //     console.log("Vault DebtShares Supply: %s", vaultDebtSharesSupply);
    //     console.log("Vault Debt Balance at Provider: %s", vaultDebtBalanceAtProvider);
    //   }
    // }
  }

  function __doUnbalanceDebtToSharesRatio(address vault_) internal {
    ILendingProvider activeProvider_ = BVault(payable(vault_)).activeProvider();

    do_depositAndBorrow(DEPOSIT_AMOUNT, BORROW_AMOUNT, IVault(address(vault)), BOB);

    uint256 debtBalance = activeProvider_.getBorrowBalance(vault_, IVault(vault_));
    address debtAsset_ = IVault(vault_).debtAsset();

    uint256 amountToAdjust = debtBalance / 2;

    deal(debtAsset_, address(this), amountToAdjust);
    IV3Pool aave = IV3Pool(activeProvider_.approvedOperator(address(0), address(0), address(0)));

    IERC20(debtAsset_).approve(address(aave), amountToAdjust);
    aave.repay(debtAsset_, amountToAdjust, 2, vault_);
  }

  function __closeBOB(address vault_) internal {
    uint256 maxPayback = IVault(vault_).maxPayback(BOB);
    address debtAsset_ = IVault(vault_).debtAsset();
    deal(debtAsset_, address(this), maxPayback);
    IERC20(debtAsset_).approve(vault_, maxPayback);
    IVault(vault_).payback(maxPayback, BOB);
  }
}
