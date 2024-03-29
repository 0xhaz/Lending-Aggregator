// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ForkingSetup} from "../forking/ForkingSetup.sol";
import {ILendingProvider} from "../../src/interfaces/ILendingProvider.sol";
import {AaveV2} from "../../src/providers/mainnet/AaveV2.sol";
import {SimpleRouter} from "../../src/routers/SimpleRouter.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";
import {Routines} from "../utils/Routines.sol";
import {IWETH9} from "../../src/abstracts/WETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibSigUtils} from "../../src/libraries/LibSigUtils.sol";

contract AttackApprovals is ForkingSetup, Routines {
  address attacker;

  ILendingProvider public aaveV2;
  IRouter public simpleRouter;

  uint256 public constant DEPOSIT_AMOUNT = 1 ether;
  uint256 public constant BORROW_AMOUNT = 200e18; // 200 DAI

  function setUp() public {
    setUpFork(MAINNET_DOMAIN);

    aaveV2 = new AaveV2();
    ILendingProvider[] memory providers = new ILendingProvider[](1);
    providers[0] = aaveV2;

    deploy(providers);

    vm.label(CHARLIE, "attacker");
    attacker = CHARLIE;

    simpleRouter = new SimpleRouter(IWETH9(collateralAsset), chief);
  }

  function test_Permit_Attack() public {
    deal(collateralAsset, ALICE, DEPOSIT_AMOUNT);
    vm.prank(ALICE);
    IERC20(collateralAsset).approve(address(simpleRouter), DEPOSIT_AMOUNT);

    // Attacker somehow gets hold of this signed mesage and calls simpleRouter
    IRouter.Action[] memory actions = new IRouter.Action[](1);
    bytes[] memory args = new bytes[](1);

    actions[0] = IRouter.Action.Deposit;
    // Attacker sets themself as `receiver`
    args[0] = abi.encode(address(vault), DEPOSIT_AMOUNT, attacker, ALICE);

    vm.expectRevert();
    vm.prank(attacker);
    simpleRouter.xBundle(actions, args);

    // Assert attacker received no funds
    assertEq(IERC20(debtAsset).balanceOf(attacker), 0);
  }
}
