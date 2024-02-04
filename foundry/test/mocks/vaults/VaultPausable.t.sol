// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockingSetup} from "../MockingSetup.sol";
import {MockRoutines} from "../MockRoutines.sol";
import {ILendingProvider} from "../../../src/interfaces/ILendingProvider.sol";
import {BorrowingVault} from "../../../src/vaults/borrowing/BorrowingVault.sol";
import {IPausableVault} from "../../../src/interfaces/IPausableVault.sol";
import {PausableVault} from "../../../src/abstracts/PausableVault.sol";

contract VaultPausableUnitTests is MockingSetup, MockRoutines {
  event Paused(address account, IPausableVault.VaultActions actions);
  event Unpaused(address account, IPausableVault.VaultActions actions);
  event PausedForceAll(address account);
  event UnpausedForceAll(address account);

  IPausableVault[] public vaults;

  BorrowingVault public bVault;

  uint256 public constant DEPOSIT_AMOUNT = 1 ether;
  uint256 public constant BORROW_AMOUNT = 1000e18;

  function setUp() public {
    _grantRoleChief(PAUSER_ROLE, CHARLIE);
    _grantRoleChief(UNPAUSER_ROLE, CHARLIE);

    ILendingProvider[] memory providers = new ILendingProvider[](1);
    providers[0] = mockProvider;

    bVault = new BorrowingVault(
      collateralAsset,
      debtAsset,
      address(oracle),
      address(chief),
      "Fuji-V2 tWETH-tDAI BorrowingVault",
      "fbvtWETHtDAI",
      providers,
      DEFAULT_MAX_LTV,
      DEFAULT_LIQ_RATIO
    );

    // Initialize vaults
    _initializeVault(address(bVault), INITIALIZER, initVaultShares);

    // Set up {Chief-_vaults} manually to bypass vault factory set-up
    IPausableVault[] memory vaults_ = new IPausableVault[](2);
    vaults_[0] = IPausableVault(address(vault));
    vaults_[1] = IPausableVault(address(bVault));

    vaults = vaults_;

    bytes memory executionCall = abi.encodeWithSelector(chief.setVaultStatus.selector, bVault, true);
    _callWithTimelock(address(chief), executionCall);
  }

  function test_Emit_Pause_Actions() public {
    vm.startPrank(CHARLIE);
    vm.expectEmit(true, true, false, false);
    emit Paused(CHARLIE, IPausableVault.VaultActions.Deposit);
    vault.pause(IPausableVault.VaultActions.Deposit);
    vm.expectEmit(true, true, false, false);
    emit Paused(CHARLIE, IPausableVault.VaultActions.Withdraw);
    vault.pause(IPausableVault.VaultActions.Withdraw);
    vm.expectEmit(true, true, false, false);
    emit Paused(CHARLIE, IPausableVault.VaultActions.Borrow);
    vault.pause(IPausableVault.VaultActions.Borrow);
    vm.expectEmit(true, true, false, false);
    emit Paused(CHARLIE, IPausableVault.VaultActions.Payback);
    vault.pause(IPausableVault.VaultActions.Payback);
    vm.expectEmit(true, false, false, false);
    emit PausedForceAll(CHARLIE);
    vault.pauseForceAll();
    vm.stopPrank();
  }

  function test_Emit_Unpause_Actions() public {
    vm.startPrank(CHARLIE);
    vault.pauseForceAll();

    vm.expectEmit(true, true, false, false);
    emit Unpaused(CHARLIE, IPausableVault.VaultActions.Deposit);
    vault.unpause(IPausableVault.VaultActions.Deposit);
    vm.expectEmit(true, true, false, false);
    emit Unpaused(CHARLIE, IPausableVault.VaultActions.Withdraw);
    vault.unpause(IPausableVault.VaultActions.Withdraw);
    vm.expectEmit(true, true, false, false);
    emit Unpaused(CHARLIE, IPausableVault.VaultActions.Borrow);
    vault.unpause(IPausableVault.VaultActions.Borrow);
    vm.expectEmit(true, true, false, false);
    emit Unpaused(CHARLIE, IPausableVault.VaultActions.Payback);
    vault.unpause(IPausableVault.VaultActions.Payback);

    vault.pauseForceAll();

    vm.expectEmit(true, false, false, false);
    emit UnpausedForceAll(CHARLIE);
    vault.unpauseForceAll();
    vm.stopPrank();
  }

  function testFail_Try_Deposit_When_Paused() public {
    vm.prank(CHARLIE);
    vault.pause(IPausableVault.VaultActions.Deposit);
    vm.stopPrank();
    do_deposit(DEPOSIT_AMOUNT, vault, ALICE);
    assertEq(vault.paused(IPausableVault.VaultActions.Deposit), true);
  }

  function testFail_Try_Withdraw_When_Paused() public {
    do_deposit(DEPOSIT_AMOUNT, vault, ALICE);
    vm.prank(CHARLIE);
    vault.pause(IPausableVault.VaultActions.Withdraw);
    vm.stopPrank();
    assertEq(vault.balanceOf(ALICE), DEPOSIT_AMOUNT);
    do_withdraw(DEPOSIT_AMOUNT, vault, ALICE);
    assertEq(vault.paused(IPausableVault.VaultActions.Withdraw), true);
  }

  function testFail_Try_Borrow_When_Paused() public {
    do_deposit(DEPOSIT_AMOUNT, vault, ALICE);
    vm.prank(CHARLIE);
    vault.pause(IPausableVault.VaultActions.Borrow);
    vm.stopPrank();
    assertEq(vault.balanceOf(ALICE), DEPOSIT_AMOUNT);
    do_borrow(BORROW_AMOUNT, vault, ALICE);
    assertEq(vault.paused(IPausableVault.VaultActions.Borrow), true);
  }

  function testFail_Try_Payback_When_Paused() public {
    do_deposit(DEPOSIT_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), DEPOSIT_AMOUNT);
    do_borrow(BORROW_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOfDebt(ALICE), BORROW_AMOUNT);
    vm.prank(CHARLIE);
    vault.pause(IPausableVault.VaultActions.Payback);
    vm.stopPrank();
    do_payback(BORROW_AMOUNT, vault, ALICE);
    assertEq(vault.paused(IPausableVault.VaultActions.Payback), true);
  }

  function test_Pause_Fail_Actions_Then_Unpause_To_All_Actions() public {
    vm.prank(CHARLIE);
    vault.pauseForceAll();

    assertEq(vault.paused(IPausableVault.VaultActions.Deposit), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Withdraw), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Borrow), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Payback), true);

    dealMockERC20(collateralAsset, ALICE, DEPOSIT_AMOUNT);

    vm.startPrank(ALICE);
    IERC20(collateralAsset).approve(address(vault), DEPOSIT_AMOUNT);
    vm.expectRevert();
    vault.deposit(DEPOSIT_AMOUNT, ALICE);
    vm.stopPrank();

    vm.prank(CHARLIE);
    vault.unpause(IPausableVault.VaultActions.Deposit);
    do_deposit(DEPOSIT_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), DEPOSIT_AMOUNT);

    vm.prank(CHARLIE);
    vault.unpause(IPausableVault.VaultActions.Borrow);
    do_borrow(BORROW_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOfDebt(ALICE), BORROW_AMOUNT);

    vm.prank(CHARLIE);
    vault.unpause(IPausableVault.VaultActions.Payback);
    do_payback(BORROW_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOfDebt(ALICE), 0);

    vm.prank(CHARLIE);
    vault.unpause(IPausableVault.VaultActions.Withdraw);
    do_withdraw(DEPOSIT_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), 0);
  }

  function test_Pause_Withdraw_All_Vaults_From_Chief() public {
    do_deposit(DEPOSIT_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), DEPOSIT_AMOUNT);
    do_deposit(DEPOSIT_AMOUNT, bVault, BOB);
    assertEq(bVault.balanceOf(BOB), DEPOSIT_AMOUNT);

    vm.prank(CHARLIE);
    chief.pauseActionInVaults(vaults, IPausableVault.VaultActions.Withdraw);

    assertEq(vault.paused(IPausableVault.VaultActions.Withdraw), true);
    assertEq(bVault.paused(IPausableVault.VaultActions.Withdraw), true);

    // Borrowingvault called by Alice
    vm.startPrank(ALICE);
    vm.expectRevert();
    vault.withdraw(DEPOSIT_AMOUNT, ALICE, ALICE);
    vm.stopPrank();

    // Borrowingvault called by Bob
    vm.startPrank(BOB);
    vm.expectRevert();
    bVault.withdraw(DEPOSIT_AMOUNT, BOB, BOB);
    vm.stopPrank();
  }

  function test_Pause_Borrow_All_Vaults_From_Chief() public {
    do_deposit(DEPOSIT_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), DEPOSIT_AMOUNT);
    do_deposit(DEPOSIT_AMOUNT, bVault, BOB);
    assertEq(bVault.balanceOf(BOB), DEPOSIT_AMOUNT);

    vm.prank(CHARLIE);
    chief.pauseActionInVaults(vaults, IPausableVault.VaultActions.Borrow);

    // Borrowingvault called by Alice
    vm.startPrank(ALICE);
    vm.expectRevert();
    vault.borrow(BORROW_AMOUNT, ALICE, ALICE);
    vm.stopPrank();

    // Borrowingvault called by Bob
    vm.startPrank(BOB);
    vm.expectRevert();
    bVault.borrow(BORROW_AMOUNT, BOB, BOB);
    vm.stopPrank();
  }

  function test_Pause_Payback_All_Vaults_From_Chief() public {
    do_deposit(DEPOSIT_AMOUNT, vault, ALICE);
    do_borrow(BORROW_AMOUNT, vault, ALICE);
    assertEq(vault.balanceOf(ALICE), DEPOSIT_AMOUNT);
    assertEq(vault.balanceOfDebt(ALICE), BORROW_AMOUNT);

    do_deposit(DEPOSIT_AMOUNT, bVault, BOB);
    do_borrow(BORROW_AMOUNT, bVault, BOB);
    assertEq(bVault.balanceOf(BOB), DEPOSIT_AMOUNT);
    assertEq(bVault.balanceOfDebt(BOB), BORROW_AMOUNT);

    vm.prank(CHARLIE);
    chief.pauseActionInVaults(vaults, IPausableVault.VaultActions.Payback);

    assertEq(vault.paused(IPausableVault.VaultActions.Payback), true);
    assertEq(bVault.paused(IPausableVault.VaultActions.Payback), true);

    // Borrowingvault called by Alice
    vm.startPrank(ALICE);
    IERC20(debtAsset).approve(address(vault), BORROW_AMOUNT);
    vm.expectRevert(PausableVault.PausableVault__requiredNotPaused_actionPaused.selector);
    vault.payback(BORROW_AMOUNT, ALICE);
    vm.stopPrank();

    // Borrowingvault called by Bob
    vm.startPrank(BOB);
    IERC20(debtAsset).approve(address(bVault), BORROW_AMOUNT);
    vm.expectRevert(PausableVault.PausableVault__requiredNotPaused_actionPaused.selector);
    bVault.payback(BORROW_AMOUNT, BOB);
    vm.stopPrank();
  }

  function test_Pause_Force_All_Actions_All_Vaults_From_Chief() public {
    vm.prank(CHARLIE);
    chief.pauseForceVaults(vaults);

    assertEq(vault.paused(IPausableVault.VaultActions.Deposit), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Withdraw), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Borrow), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Payback), true);

    assertEq(bVault.paused(IPausableVault.VaultActions.Deposit), true);
    assertEq(bVault.paused(IPausableVault.VaultActions.Withdraw), true);
    assertEq(bVault.paused(IPausableVault.VaultActions.Borrow), true);
    assertEq(bVault.paused(IPausableVault.VaultActions.Payback), true);
  }

  function test_Unpause_Force_All_Actions_All_Vaults_From_Chief() public {
    vm.prank(CHARLIE);
    chief.pauseForceVaults(vaults);

    assertEq(vault.paused(IPausableVault.VaultActions.Deposit), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Withdraw), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Borrow), true);
    assertEq(vault.paused(IPausableVault.VaultActions.Payback), true);

    assertEq(bVault.paused(IPausableVault.VaultActions.Deposit), true);
    assertEq(bVault.paused(IPausableVault.VaultActions.Withdraw), true);
    assertEq(bVault.paused(IPausableVault.VaultActions.Borrow), true);
    assertEq(bVault.paused(IPausableVault.VaultActions.Payback), true);

    vm.prank(CHARLIE);
    chief.unpauseForceVaults(vaults);

    assertEq(vault.paused(IPausableVault.VaultActions.Deposit), false);
    assertEq(vault.paused(IPausableVault.VaultActions.Withdraw), false);
    assertEq(vault.paused(IPausableVault.VaultActions.Borrow), false);
    assertEq(vault.paused(IPausableVault.VaultActions.Payback), false);

    assertEq(bVault.paused(IPausableVault.VaultActions.Deposit), false);
    assertEq(bVault.paused(IPausableVault.VaultActions.Withdraw), false);
    assertEq(bVault.paused(IPausableVault.VaultActions.Borrow), false);
    assertEq(bVault.paused(IPausableVault.VaultActions.Payback), false);
  }
}
