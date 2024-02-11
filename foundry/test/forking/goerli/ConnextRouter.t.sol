// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Routines} from "../../utils/Routines.sol";
import {ForkingSetup} from "../ForkingSetup.sol";
import {AaveV3Goerli} from "../../../src/providers/goerli/AaveV3Goerli.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {IVaultPermissions} from "../../../src/interfaces/IVaultPermissions.sol";
import {ILendingProvider} from "../../../src/interfaces/ILendingProvider.sol";
import {IConnext} from "../../../src/interfaces/connext/IConnext.sol";
import {MockProviderV0} from "../../../src/mocks/MockProviderV0.sol";
import {MockERC20} from "../../../src/mocks/MockERC20.sol";
import {IRouter} from "../../../src/interfaces/IRouter.sol";
import {IConnext, TransferInfo, ExecuteArgs} from "../../../src/interfaces/connext/IConnext.sol";
import {BorrowingVault} from "../../../src/vaults/borrowing/BorrowingVault.sol";
import {
  ConnextRouter, ConnextHandler, ConnextReceiver
} from "../../../src/routers/ConnextRouter.sol";
import {BaseRouter} from "../../../src/abstracts/BaseRouter.sol";
import {IWETH9} from "../../../src/abstracts/WETH9.sol";
import {LibSigUtils} from "../../../src/libraries/LibSigUtils.sol";
import {FlasherAaveV3} from "../../../src/flashloans/FlasherAaveV3.sol";
import {IFlasher} from "../../../src/interfaces/IFlasher.sol";
import {MockFlasher} from "../../../src/mocks/MockFlasher.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {TransferInfo} from "../../../src/interfaces/connext/IConnext.sol";

contract MockTestFlasher is Routines, IFlasher {
  using SafeERC20 for IERC20;
  using Address for address;

  bool public flashloanCalled = false;

  function initiateFlashloan(
    address asset,
    uint256 amount,
    address requestor,
    bytes memory requestorCalldata
  )
    external
  {
    deal(asset, address(this), amount);
    flashloanCalled = true;
    SafeERC20.safeTransfer(IERC20(asset), requestor, amount);
    requestor.functionCall(requestorCalldata);
  }

  /// @inheritdoc IFlasher
  function getFlashloanSourceAddr(address) public view override returns (address) {
    return address(this);
  }

  /// @inheritdoc IFlasher
  function computeFlashloanFee(address, uint256) external pure override returns (uint256 fee) {
    fee = 0;
  }
}

contract ConnextRouterForkingTests is Routines, ForkingSetup {
  event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

  event Borrow(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 debt,
    uint256 shares
  );

  event Dispatch(bytes32 leaft, uint256 index, bytes32 root, bytes message);

  ConnextRouter public connextRouter;
  ConnextHandler public connextHandler;
  ConnextReceiver public connextReceiver;

  uint32 domain;
  IConnext public connext = IConnext(registry[GOERLI_DOMAIN].connext);

  function setUp() public {
    domain = GOERLI_DOMAIN;
    setUpFork(domain);

    // test with a mock provider because Connext's and Aave's WETH mismatch
    MockProviderV0 mockProvider = new MockProviderV0();
    ILendingProvider[] memory providers = new ILendingProvider[](1);
    providers[0] = mockProvider;

    deploy(providers);

    connextRouter =
      new ConnextRouter(IWETH9(collateralAsset), IConnext(registry[domain].connext), chief);

    connextHandler = connextRouter.handler();
    connextReceiver = ConnextReceiver(connextRouter.connextReceiver());

    // Address are supposed to be the same across different chains
    /*connextRouter.setReceiver(OPTIMISM_GOERLI_DOMAIN, address(connextRouter));*/
    bytes memory callData = abi.encodeWithSelector(
      ConnextRouter.setReceiver.selector, OPTIMISM_GOERLI_DOMAIN, address(connextReceiver)
    );
    _callWithTimelock(address(connextRouter), callData);
  }

  function test_Bridge_Outbound() public {
    uint256 amount = 2 ether;
    deal(collateralAsset, ALICE, amount);

    uint32 destDomain = OPTIMISM_GOERLI_DOMAIN;

    vm.startPrank(ALICE);

    SafeERC20.safeApprove(IERC20(collateralAsset), address(connextRouter), type(uint256).max);

    IRouter.Action[] memory actions = new IRouter.Action[](1);
    bytes[] memory args = new bytes[](1);

    actions[0] = IRouter.Action.XTransferWithCall;

    IRouter.Action[] memory destActions = new IRouter.Action[](1);
    bytes[] memory destArgs = new bytes[](1);

    destActions[0] = IRouter.Action.Deposit;
    destArgs[0] = abi.encode(address(vault), amount, ALICE, address(connextRouter));

    bytes memory destCallData = abi.encode(destActions, destArgs);
    args[0] = abi.encode(destDomain, 30, collateralAsset, amount, ALICE, destCallData);

    vm.expectEmit(false, false, false, false);
    emit Dispatch("", 1, "", "");

    connextRouter.xBundle(actions, args);
  }

  function test_Bridge_Inbound() public {
    uint256 amount = 2 ether;
    uint256 borrowAmount = 1000e6; // 1000 USDC

    bytes memory callData = _getDepositAndBorrowCallData(
      ALICE, ALICE_PK, amount, borrowAmount, address(connextRouter), address(vault)
    );

    vm.expectEmit(true, true, true, false);
    emit Deposit(address(connextRouter), ALICE, amount, amount);

    vm.expectEmit(true, true, true, false);
    emit Borrow(address(connextRouter), ALICE, ALICE, borrowAmount, borrowAmount);

    // Send directly the bridged funds to our router
    // thus mocking Connext behavior
    deal(collateralAsset, address(connextReceiver), amount);

    vm.startPrank(registry[domain].connext);
    // Call from OPTIMISM_GOERLI_DOMAIN where `originSender` is router that's supposed to have
    // the same address as the one on GOERLI
    connextReceiver.xReceive(
      "", amount, vault.asset(), address(connextRouter), OPTIMISM_GOERLI_DOMAIN, callData
    );
    vm.stopPrank();

    // Assert ALICE has received shares
    assertGt(vault.balanceOf(ALICE), 0);
    // Assert ALICE received borrowAmount
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
    // Assert router or ConnextHandler does not have collateral
    assertEq(IERC20(collateralAsset).balanceOf(address(connextRouter)), 0);
    assertEq(IERC20(collateralAsset).balanceOf(address(connextHandler)), 0);
  }

  function test_Attack_XReceive() public {
    uint256 amount = 2 ether;
    uint256 borrowAmount = 1000e6; // 1000 USDC

    // This calldata has to fail and funds handled accordingly by the router
    bytes memory failingCallData = _getDepositAndBorrowCallData(
      ALICE, ALICE_PK, amount, borrowAmount, address(0), address(vault)
    );

    // Send directly the bridged funds to our router thus mocking Connext behavior
    deal(collateralAsset, address(connextReceiver), amount);

    vm.startPrank(registry[domain].connext);
    // Call attack faked as from OPTIMISM_GOERLI_DOMAIN where `originSender` is router that's
    // supposed to have the same address as the one on GOERLI
    connextReceiver.xReceive(
      "", amount, vault.asset(), address(connextRouter), OPTIMISM_GOERLI_DOMAIN, failingCallData
    );
    vm.stopPrank();

    // Asset that funds are kept at the ConnextHandler
    assertEq(IERC20(collateralAsset).balanceOf(address(connextHandler)), amount);

    // Attacker makes first attempt to take funds using xReceive, BOB
    address attacker = BOB;
    bytes memory attackCallData = _getDepositAndBorrowCallData(
      attacker, BOB_PK, amount, borrowAmount, address(connextRouter), address(vault)
    );

    // Call attacked faked as from OPTIMISM_GOERLI_DOMAIN where `originSender` is router that's
    // supposed to have the same address as the one on GOERLI
    vm.startPrank(attacker);
    try connextRouter.xReceive(
      "", 1 wei, vault.asset(), address(connextRouter), OPTIMISM_GOERLI_DOMAIN, attackCallData
    ) {
      console.log("xReceive attack succeeded");
    } catch {
      console.log("xReceive attack failed");
    }
    vm.stopPrank();

    // Assert attacker has not received shares
    assertEq(vault.balanceOf(attacker), 0);
    // Assert attacker has not received borrowAmount
    assertEq(IERC20(debtAsset).balanceOf(attacker), 0);

    // Attacker makes second attemp to take funds using xBundle, BOB
    (IRouter.Action[] memory attackActions, bytes[] memory attackArgs) = _getDepositAndBorrow(
      attacker, BOB_PK, 1 ether, borrowAmount, address(connextRouter), address(vault)
    );

    vm.startPrank(attacker);
    try connextRouter.xBundle(attackActions, attackArgs) {
      console.log("xBundle attack succeeded");
    } catch {
      console.log("xBundle attack failed");
    }
    vm.stopPrank();

    // Assert attacker has not received shares
    assertEq(vault.balanceOf(attacker), 0);
    // Assert attacker has not received borrowAmount
    assertEq(IERC20(debtAsset).balanceOf(attacker), 0);
  }

  function test_Fails_Bridge_Inbound_XBundle() public {
    uint256 amount = 2 ether;
    uint256 borrowAmount = 1000e6; // 1000 USDC

    // make the callData to fail
    bytes memory callData = _getDepositAndBorrowCallData(
      ALICE, ALICE_PK, amount, borrowAmount, address(0), address(vault)
    );

    // Send directly the bridged funds to our router thus mocking Connext behavior
    deal(collateralAsset, address(connextReceiver), amount);

    vm.startPrank(registry[domain].connext);
    // Call from OPTIMISM_GOERLI_DOMAIN where `originSender` is router that's supposed to have
    // the same address as the one on GOERLI
    connextReceiver.xReceive(
      "", amount, vault.asset(), address(connextRouter), OPTIMISM_GOERLI_DOMAIN, callData
    );
    vm.stopPrank();

    assertEq(vault.balanceOf(ALICE), 0);
    // funds are kept at the ConnextHandler contract
    assertEq(IERC20(collateralAsset).balanceOf(address(connextHandler)), amount);
  }

  function test_Retry_Failed_Inbound_XReceive() public {
    uint256 amount = 2 ether;
    uint256 borrowAmount = 1000e6; // 1000 USDC

    // make the callData to fail
    bytes memory badCallData = _getDepositAndBorrowCallData(
      ALICE, ALICE_PK, amount, borrowAmount, address(0), address(vault)
    );

    // Send directly the bridged funds to our router thus mocking Connext behavior
    deal(collateralAsset, address(connextReceiver), amount);

    vm.startPrank(registry[domain].connext);
    // Call from OPTIMISM_GOERLI_DOMAIN where `originSender` is router that's supposed to have
    // the same address as the one on GOERLI
    bytes32 transferId = 0x0000000000000000000000000000000000000000000000000000000000000001;
    connextReceiver.xReceive(
      transferId, amount, vault.asset(), address(connextRouter), OPTIMISM_GOERLI_DOMAIN, badCallData
    );
    vm.stopPrank();

    assertEq(vault.balanceOf(ALICE), 0);
    // funds are kept at the ConnextHandler contract
    assertEq(IERC20(collateralAsset).balanceOf(address(connextHandler)), amount);

    // Ensure calldata is fixed
    // In this case the badCalldata previously had sender as address(0)
    // The ConnextHandler replaces `sender` with its address when recording the failed transfer
    ConnextHandler.FailedTxn memory transfer =
      connextHandler.getFailedTxn(transferId, connextHandler.getFailedTxnNextNonce(transferId) - 1);

    //   Fix the args that failed
    transfer.args[0] = abi.encode(address(vault), amount, ALICE, address(connextHandler));
    transfer.args[1] =
      LibSigUtils.getZeroPermitEncodedArgs(address(vault), ALICE, ALICE, borrowAmount);
    transfer.args[2] = abi.encode(address(vault), borrowAmount, ALICE, ALICE);

    bytes32 actionArgsHash = LibSigUtils.getActionArgsHash(transfer.actions, transfer.args);

    // It is assumed that Alice gets involved to sign again the correct data
    transfer.args[1] = _buildPermitAsBytes(
      ALICE,
      ALICE_PK,
      address(connextRouter),
      ALICE,
      borrowAmount,
      0,
      address(vault),
      actionArgsHash
    );

    connextHandler.executeFailedWithUpdatedArgs(
      transferId,
      connextHandler.getFailedTxnNextNonce(transferId) - 1,
      transfer.actions,
      transfer.args
    );

    // Assert Alice has funds deposited in the vault
    assertGt(vault.balanceOf(ALICE), 0);
    // Assert Alice was able to borrow from the vault
    assertEq(IERC20(debtAsset).balanceOf(ALICE), borrowAmount);
  }

  function test_Deposit_And_Borrow_And_Transfer() public {
    uint256 amount = 2 ether;
    uint256 borrowAmount = 1000e6; // 1000 USDC

    IRouter.Action[] memory actions = new IRouter.Action[](4);
    actions[0] = IRouter.Action.Deposit;
    actions[1] = IRouter.Action.PermitBorrow;
    actions[2] = IRouter.Action.Borrow;
    actions[3] = IRouter.Action.XTransfer;

    bytes[] memory args = new bytes[](4);
    args[0] = abi.encode(address(vault), amount, ALICE, ALICE);
    args[1] = LibSigUtils.getZeroPermitEncodedArgs(
      address(vault), ALICE, address(connextRouter), borrowAmount
    );
    args[2] = abi.encode(address(vault), borrowAmount, address(connextRouter), ALICE);
    args[3] = abi.encode(MUMBAI_DOMAIN, 30, debtAsset, borrowAmount, ALICE, address(connextRouter));

    bytes32 actionArgsHash = LibSigUtils.getActionArgsHash(actions, args);

    LibSigUtils.Permit memory permit = LibSigUtils.buildPermitStruct(
      ALICE,
      address(connextRouter),
      address(connextRouter),
      borrowAmount,
      0,
      address(vault),
      actionArgsHash
    );

    (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
      _getPermitBorrowArgs(permit, ALICE_PK, address(vault));

    //   Replace permit action arguments, now with signature values
    args[1] =
      abi.encode(address(vault), ALICE, address(connextRouter), borrowAmount, deadline, v, r, s);

    deal(collateralAsset, ALICE, amount);

    // Mock Connext because it doesn't allow bridging of assets other than TEST token
    vm.mockCall(
      registry[GOERLI_DOMAIN].connext,
      abi.encodeWithSelector(IConnext.xcall.selector),
      abi.encode(1)
    );

    // Mock balanceOf to avoid BaseRouter__bundleInternal_noRemnantBalance error
    vm.mockCall(
      debtAsset,
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(connextRouter)),
      abi.encode(0)
    );

    vm.startPrank(ALICE);
    SafeERC20.safeApprove(IERC20(collateralAsset), address(connextRouter), amount);

    vm.expectEmit(true, true, true, true);
    emit Deposit(address(connextRouter), ALICE, amount, amount);

    vm.expectEmit(true, true, true, true);
    emit Borrow(address(connextRouter), address(connextRouter), ALICE, borrowAmount, borrowAmount);

    connextRouter.xBundle(actions, args);
    vm.stopPrank();

    assertEq(vault.balanceOf(ALICE), amount);
    assertEq(vault.balanceOfDebt(ALICE), borrowAmount);
  }

  function test_Overriding_Failed_Transfer_In_Handler() public {
    bytes32 transferId_ = 0x000000000000000000000000000000000000000000000000000000000000000a;
    uint256 amount = 2 ether;
    uint256 borrowAmount = 1000e6; // 1000 USDC

    // This calldata has to fail and funds handled accordingly by the router
    bytes memory failingCallData = _getDepositAndBorrowCallData(
      ALICE, ALICE_PK, amount, borrowAmount, address(0), address(vault)
    );

    // Send directly the bridged funds to our router thus mocking Connext behavior
    deal(collateralAsset, address(connextReceiver), amount);

    vm.startPrank(registry[domain].connext);
    // Call from OPTIMISM_GOERLI_DOMAIN where `originSender` is router that's supposed to have
    // the same address as the one on GOERLI
    connextReceiver.xReceive(
      transferId_,
      amount,
      vault.asset(),
      address(connextRouter),
      OPTIMISM_GOERLI_DOMAIN,
      failingCallData
    );
    vm.stopPrank();

    // Assert handler has recorded the failed transfer
    uint256 expectedNonce = connextHandler.getFailedTxnNextNonce(transferId_) - 1;
    ConnextHandler.FailedTxn memory ftxn = connextHandler.getFailedTxn(transferId_, expectedNonce);

    assertEq(ftxn.transferId, transferId_);
    assertEq(ftxn.asset, collateralAsset);
    assertEq(ftxn.amount, amount);
    assertEq(ftxn.nonce, expectedNonce);

    // Create different callData
    uint256 newAmount = 1.5 ether;
    bytes memory newfailingCallData = _getDepositAndBorrowCallData(
      ALICE, ALICE_PK, newAmount, borrowAmount, address(0), address(vault)
    );

    // Send directly the bridged funds to our router thus mocking Connext behavior
    deal(collateralAsset, address(connextReceiver), newAmount);

    vm.startPrank(registry[domain].connext);
    // Call from OPTIMISM_GOERLI_DOMAIN where `originSender` is router that's supposed to have
    // the same address as the one on GOERLI
    connextReceiver.xReceive(
      transferId_,
      newAmount,
      vault.asset(),
      address(connextRouter),
      OPTIMISM_GOERLI_DOMAIN,
      newfailingCallData
    );
    vm.stopPrank();

    // Assert handler has recorded the failed transfer
    expectedNonce = connextHandler.getFailedTxnNextNonce(transferId_) - 1;
    ConnextHandler.FailedTxn memory newftxn =
      connextHandler.getFailedTxn(transferId_, expectedNonce);

    assertEq(newftxn.transferId, transferId_);
    assertEq(newftxn.asset, collateralAsset);
    assertEq(newftxn.amount, newAmount);
    assertEq(newftxn.nonce, expectedNonce);
  }

  /**
   * @dev NOTE: This test has xBundle actions that seem illogical
   * The main purpose is to check that ConnextRouter is able
   * to obtain the beneficiary from a flashloan to be executed
   * after a cross-chain tx
   */
  function test_Simple_Flashloan() public {
    // Setup flasher accordingly
    MockTestFlasher flasher = new MockTestFlasher();
    bytes memory data =
      abi.encodeWithSelector(chief.allowedFlasher.selector, address(flasher), true);
    _callWithTimelock(address(chief), data);

    // Perform a preliminary deposit in the vault
    uint256 amount = 2 ether;
    do_deposit(amount, vault, ALICE);

    vm.prank(ALICE);
    BorrowingVault(payable(address(vault))).increaseWithdrawAllowance(
      address(connextRouter), address(connextRouter), amount
    );

    IRouter.Action[] memory actions = new IRouter.Action[](2);
    bytes[] memory args = new bytes[](2);

    actions[0] = IRouter.Action.Withdraw;
    args[0] = abi.encode(address(vault), amount, address(connextRouter), ALICE);
    actions[1] = IRouter.Action.XTransferWithCall;

    IRouter.Action[] memory flashAction = new IRouter.Action[](1);
    bytes[] memory flashArgs = new bytes[](1);

    flashAction[0] = IRouter.Action.Flashloan;

    IRouter.Action[] memory innerActions = new IRouter.Action[](1);
    bytes[] memory innerArgs = new bytes[](1);

    innerActions[0] = IRouter.Action.Deposit;
    innerArgs[0] = abi.encode(address(vault), amount, ALICE, address(connextRouter));

    flashArgs[0] = abi.encode(
      address(flasher), collateralAsset, amount, address(connextRouter), innerActions, innerArgs
    );

    {
      uint32 destDomain = OPTIMISM_GOERLI_DOMAIN;
      bytes memory destCalldata = abi.encode(flashAction, flashArgs);
      args[1] =
        abi.encode(destDomain, 30, collateralAsset, amount, address(connextRouter), destCalldata);
    }
    vm.startPrank(ALICE);
    SafeERC20.safeApprove(IERC20(collateralAsset), address(connextRouter), type(uint256).max);

    vm.expectEmit(false, false, false, false);
    emit Dispatch("", 1, "", "");
    connextRouter.xBundle(actions, args);

    vm.stopPrank();

    assertEq(vault.balanceOf(ALICE), 0);
    assertEq(vault.balanceOf(address(connextRouter)), 0);
  }

  function test_Flashloan_With_Incorrect_Action_After() public {
    // Setup flasher accordingly
    MockTestFlasher flasher = new MockTestFlasher();
    bytes memory data = abi.encodeWithSelector(chief.allowFlasher.selector, address(flasher), true);
    _callWithTimelock(address(chief), data);

    uint256 amount = 2 ether;
    deal(collateralAsset, ALICE, amount);

    IRouter.Action[] memory actions1 = new IRouter.Action[](1);
    actions1[0] = IRouter.Action.Flashloan;

    IRouter.Action[] memory actions = new IRouter.Action[](1);
    actions[0] = IRouter.Action.Swap;

    bytes[] memory args = new bytes[](1);

    bytes[] memory args1 = new bytes[](1);

    args1[0] =
      abi.encode(address(flasher), collateralAsset, amount, address(connextRouter), actions, args);

    vm.startPrank(ALICE);
    SafeERC20.safeApprove(IERC20(collateralAsset), address(connextRouter), type(uint256).max);

    vm.expectRevert(BaseRouter.BaseRouter__bundleInternal_notFirstAction.selector);
    connextRouter.xBundle(actions1, args1);
  }

  /**
   * @notice Tests that a flashloan can be used to perform a flashclose
   * @dev Note:
   * - make a transfer with call to destChain - XTransferWithCall
   * - call on destination chain is deposit and borrow, opening a simple position
   * - use a flashloan to perform a flashclose in destChain
   */
  function test_Deposit_And_Borrow_Flash_Close() public {
    // Stack too deep to have these variables in the same function
    uint256 amount = 1 ether;
    uint256 borrowAmount = 100e6; // 100 USDC

    uint32 destDomain = OPTIMISM_GOERLI_DOMAIN;
    MockTestFlasher flasher = new MockTestFlasher();

    // SECTION 1: test_depositAndBorrowFlashClose
    // This section of the test open a position on the destination chain
    {
      deal(collateralAsset, ALICE, 2 * amount);
      vm.startPrank(ALICE);
      SafeERC20.safeApprove(IERC20(collateralAsset), address(connextRouter), type(uint256).max);

      assertEq(IERC20(collateralAsset).balanceOf(ALICE), 2 * amount);

      //   deposit and borrow in destination chain
      IRouter.Action[] memory originActions1 = new IRouter.Action[](1);
      bytes[] memory originArgs1 = new bytes[](1);
      originActions1[0] = IRouter.Action.XTransferWithCall;

      //   deposit and borrow
      IRouter.Action[] memory destChainDepositAndBorrowActions = new IRouter.Action[](2);
      bytes[] memory destChainDepositAndBorrowArgs = new bytes[](2);

      //  Deposit
      destChainDepositAndBorrowActions[0] = IRouter.Action.Deposit;
      destChainDepositAndBorrowArgs[0] =
        abi.encode(address(vault), amount, ALICE, address(connextRouter));

      // Borrow
      destChainDepositAndBorrowActions[1] = IRouter.Action.Borrow;
      destChainDepositAndBorrowArgs[1] =
        abi.encode(address(vault), borrowAmount, ALICE, address(connextRouter));

      bytes memory destChainDepositAndBorrowCalldata =
        abi.encode(destChainDepositAndBorrowActions, destChainDepositAndBorrowArgs, 0);

      originArgs1[0] = abi.encode(
        destDomain, 30, collateralAsset, amount, ALICE, destChainDepositAndBorrowCalldata
      );

      //   assert dispatch
      vm.expectEmit(false, false, false, false);
      emit Dispatch("", 1, "", "");
      connextRouter.xBundle(originActions1, originArgs1);

      assertEq(IERC20(collateralAsset).balanceOf(ALICE), amount);
    }

    // SECTION 2: test_depositAndBorrowFlashClose
    // This section of the test checks that the beneficiary can be extracted from a flashloan action
    {
      // XTransferWithCall from origin chain
      IRouter.Action[] memory originActions2 = new IRouter.Action[](1);
      bytes[] memory originArgs2 = new bytes[](1);
      originActions2[0] = IRouter.Action.XTransferWithCall;

      // flashloan in optimism
      IRouter.Action[] memory destActions = new IRouter.Action[](1);
      bytes[] memory destArgs = new bytes[](1);
      destActions[0] = IRouter.Action.Flashloan;

      // Perform a flashclose
      IRouter.Action[] memory destInnerActions = new IRouter.Action[](4);
      bytes[] memory destInnerArgs = new bytes[](4);
      destInnerActions[0] = IRouter.Action.Payback;
      destInnerActions[1] = IRouter.Action.PermitWithdraw;
      destInnerActions[2] = IRouter.Action.Withdraw;
      destInnerActions[3] = IRouter.Action.XTransfer;
      destInnerArgs[0] = abi.encode(address(vault), borrowAmount, ALICE, address(connextRouter));
      destInnerArgs[1] =
        LibSigUtils.getZeroPermitEncodedArgs(address(vault), ALICE, address(connextRouter), amount);
      destInnerArgs[2] = abi.encode(address(vault), amount, ALICE, address(connextRouter));
      destInnerArgs[3] = abi.encode(GOERLI_DOMAIN, 0, collateralAsset, amount, ALICE, ALICE);

      //   optimism args for flashloan
      destArgs[0] = abi.encode(
        address(flasher),
        debtAsset,
        borrowAmount,
        address(connextRouter),
        destInnerActions,
        destInnerArgs
      );
      bytes memory destCallData = abi.encode(destActions, destArgs, 0);

      originArgs2[0] = abi.encode(destDomain, 0, collateralAsset, 0, ALICE, destCallData);

      //  assert dispatch
      vm.expectEmit(false, false, false, false);
      emit Dispatch("", 1, "", "");
      connextRouter.xBundle(originActions2, originArgs2);
    }
  }

  function test_Flash_Close_XTransfer_Attack() public {
    uint32 destDomain = OPTIMISM_GOERLI_DOMAIN;

    // Setup test such that the router has withdrawAllowance for some reason
    deal(collateralAsset, ALICE, 2 ether);
    vm.startPrank(ALICE);
    SafeERC20.safeApprove(IERC20(collateralAsset), address(vault), 2 ether);
    vault.deposit(2 ether, ALICE);
    IVaultPermissions(address(vault)).increaseWithdrawAllowance(
      address(connextRouter), address(connextRouter), 2 ether
    );
    vm.stopPrank();

    // Attacker
    address attacker = BOB;

    // XTransferWithCall from origin chain
    IRouter.Action[] memory originActions = new IRouter.Action[](2);
    originActions[0] = IRouter.Action.Withdraw;
    originActions[1] = IRouter.Action.XTransferWithCall;

    bytes[] memory originArgs = new bytes[](2);
    originArgs[0] = abi.encode(address(vault), 1 ether, address(connextRouter), ALICE);

    // flashloan in optimism
    IRouter.Action[] memory destActions = new IRouter.Action[](1);
    destActions[0] = IRouter.Action.Flashloan;

    bytes[] memory destArgs = new bytes[](1);

    // Perform a flashloan
    // Attacker creates dumb flashloan action at destination to attempt bypass checks
    IRouter.Action[] memory destInnerActions = new IRouter.Action[](1);
    bytes[] memory destInnerArgs = new bytes[](1);
    destInnerActions[0] = IRouter.Action.Deposit;
    destInnerArgs[0] = abi.encode(address(vault), 1 ether, attacker, address(connextRouter));

    // Args for flashloan
    address supposedDestinationFlasher = 0x000000000000000000000000000000000000001a;
    destArgs[0] = abi.encode(
      supposedDestinationFlasher,
      debtAsset,
      1 wei,
      address(connextRouter),
      destInnerActions,
      destInnerArgs
    );

    bytes memory destCallData = abi.encode(destActions, destArgs, 0);

    originArgs[1] = abi.encode(destDomain, 0, collateralAsset, 0, ALICE, destCallData);

    // Expect revert due to wring beneficiary in cross transaction
    vm.expectRevert(BaseRouter.BaseRouter__bundleInternal_notBeneficiary.selector);
    connextRouter.xBundle(originActions, originArgs);
  }

  function test_Try_Change_XTransfer_Slippage_Without_Permission() public {
    uint256 amount = 1 ether;
    uint256 borrowAmount = 100e6; // 100 USDC
    uint256 slippage = 0;
    uint256 newSlippage = 3;
    uint256 slippageThreshold = 5;

    bytes memory callData = _getDepositAndBorrowCallData(
      ALICE, ALICE_PK, amount, borrowAmount, address(connextRouter), address(vault)
    );

    vm.expectEmit(true, true, true, false);
    emit Deposit(address(connextRouter), ALICE, amount, amount);

    vm.expectEmit(true, true, true, false);
    emit Borrow(address(connextRouter), ALICE, ALICE, borrowAmount, borrowAmount);

    // Send directly the bridged funds to our router thus mocking Connext behavior
    // including a 0.03% slippage (3 basis points)
    uint256 slippageAmount = ((amount * 10000) / 10_003);
    deal(collateralAsset, address(connextReceiver), slippageAmount);

    vm.expectRevert();
    // Try to change slippage without permission
    vm.startPrank(BOB);
    connext.forceUpdateSlippage(
      TransferInfo({
        originDomain: OPTIMISM_GOERLI_DOMAIN,
        destinationDomain: GOERLI_DOMAIN,
        canonicalDomain: GOERLI_DOMAIN,
        to: address(connextRouter),
        delegate: ALICE,
        receiveLocal: false,
        callData: "",
        slippage: 0,
        originSender: ALICE,
        bridgedAmt: amount,
        normalizedIn: amount,
        nonce: 0,
        canonicalId: ""
      }),
      newSlippage
    );
  }
}
