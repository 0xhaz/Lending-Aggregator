// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {MockingSetup} from "../mocks/MockingSetup.sol";
import {ILendingProvider} from "../../src/interfaces/ILendingProvider.sol";
import {MockProvider} from "../../src/mocks/MockProvider.sol";
import {SimpleRouter} from "../../src/routers/SimpleRouter.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";
import {Routines} from "../utils/Routines.sol";
import {IWETH9} from "../../src/abstracts/WETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibSigUtils} from "../../src/libraries/LibSigUtils.sol";

contract AttackPermits is MockingSetup, Routines {
  address attacker;

  IRouter public simpleRouter;

  uint256 public constant DEPOSIT_AMOUNT = 1 ether;
  uint256 public constant BORROW_AMOUNT = 200e18; // 200 DAI

  function setUp() public {
    vm.label(CHARLIE, "attacker");
    attacker = CHARLIE;

    oracle.setUSDPriceOf(collateralAsset, USD_PER_ETH_PRICE);
    oracle.setUSDPriceOf(debtAsset, USD_PER_DAI_PRICE);

    simpleRouter = new SimpleRouter(IWETH9(collateralAsset), chief);

    do_depositAndBorrow(DEPOSIT_AMOUNT, BORROW_AMOUNT, vault, ALICE);
  }

  function test_Permit_Attack() public {
    // Alice signs a message for `simpleRouter` to borrow 800 tDAI
    uint256 newBorrowAmount = 800e18;

    bytes32 pretendedActionArgsHash = keccak256(abi.encode(1));

    LibSigUtils.Permit memory permit = LibSigUtils.buildPermitStruct(
      ALICE,
      address(simpleRouter),
      ALICE,
      newBorrowAmount,
      0,
      address(vault),
      pretendedActionArgsHash
    );

    (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
      _getPermitBorrowArgs(permit, ALICE_PK, address(vault));

    //   Attacker somehow gets hold of this signed mesage and calls simpleRouter
    IRouter.Action[] memory actions = new IRouter.Action[](2);
    bytes[] memory args = new bytes[](2);

    actions[0] = IRouter.Action.PermitBorrow;
    actions[1] = IRouter.Action.Borrow;

    args[0] = abi.encode(address(vault), ALICE, attacker, newBorrowAmount, deadline, v, r, s);

    // Attacker sets themself as `receiver`
    args[1] = abi.encode(address(vault), newBorrowAmount, attacker, ALICE);

    vm.expectRevert();
    vm.prank(attacker);
    simpleRouter.xBundle(actions, args);

    // Assert attacker received no funds
    assertEq(IERC20(debtAsset).balanceOf(attacker), 0);
  }

  function test_Permit_Attack_With_Receiver() public {
    // Alice signs a message for `simpleRouter` to borrow 800 tDAI and do "something" with funds
    // Therefore `receiver` is also `operator`
    uint256 newBorrowAmount = 800e18;

    bytes32 pretendedActionArgsHash = keccak256(abi.encode(1));

    LibSigUtils.Permit memory permit = LibSigUtils.buildPermitStruct(
      ALICE,
      address(simpleRouter),
      address(simpleRouter),
      newBorrowAmount,
      0,
      address(vault),
      pretendedActionArgsHash
    );

    (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
      _getPermitBorrowArgs(permit, ALICE_PK, address(vault));

    //   Read the balance of the simpleRouter prior to the attack
    uint256 previousBalance = IERC20(debtAsset).balanceOf(address(simpleRouter));

    // Attacker somehow gets hold of this signed mesage and calls simpleRouter
    IRouter.Action[] memory actions = new IRouter.Action[](2);
    bytes[] memory args = new bytes[](2);

    actions[0] = IRouter.Action.PermitBorrow;
    actions[1] = IRouter.Action.Borrow;

    args[0] =
      abi.encode(address(vault), ALICE, address(simpleRouter), newBorrowAmount, deadline, v, r, s);
    args[1] = abi.encode(address(vault), newBorrowAmount, address(simpleRouter), ALICE);

    // With this call the attacker tries to lock the funds in the simpleRouter contract
    vm.expectRevert();
    vm.prank(attacker);
    simpleRouter.xBundle(actions, args);

    // Read the balance of the simpleRouter after attempted attack
    uint256 afterBalance = IERC20(debtAsset).balanceOf(address(simpleRouter));

    // No change in balances in simpleRouter
    assertEq(previousBalance, afterBalance);
  }
}
