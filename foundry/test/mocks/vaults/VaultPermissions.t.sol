// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockingSetup} from "../MockingSetup.sol";
import {MockRoutines} from "../MockRoutines.sol";
import {LibSigUtils} from "../../../src/libraries/LibSigUtils.sol";
import {VaultPermissions} from "../../../src/vaults/VaultPermissions.sol";

contract VaultPermissionsUnitsTest is MockingSetup, MockRoutines {
  uint256 ownerPkey = 0x10;
  address owner = vm.addr(ownerPkey);
  uint256 operatorPkey = 0x11;
  address operator = vm.addr(operatorPkey);
  uint256 receiverPkey = 0x12;
  address receiver = vm.addr(receiverPkey);

  uint256 public BORROW_LIMIT = 500 * 1e18;

  function setUp() public {
    vm.label(owner, "owner");
    vm.label(operator, "operator");
    vm.label(receiver, "receiver");
  }

  function test_Increase_Withdraw_Allowance(uint256 amount) public {
    vm.assume(amount > 0);

    assertEq(vault.withdrawAllowance(owner, operator, receiver), 0);

    vm.prank(owner);
    vault.increaseWithdrawAllowance(operator, receiver, amount);

    assertEq(vault.withdrawAllowance(owner, operator, receiver), amount);
  }

  function test_Decrease_Withdraw_Allowance(uint256 decreaseAmount_) public {
    vm.assume(decreaseAmount_ > 0 && decreaseAmount_ <= 1 ether);

    uint256 difference = 1 ether - decreaseAmount_;

    vm.startPrank(owner);
    vault.increaseWithdrawAllowance(operator, receiver, 1 ether);
    vault.decreaseWithdrawAllowance(operator, receiver, decreaseAmount_);
    vm.stopPrank();

    assertEq(vault.withdrawAllowance(owner, operator, receiver), difference);
  }

  function test_Increase_Borrow_Allowance(uint256 amount) public {
    vm.assume(amount > 0);

    assertEq(vault.borrowAllowance(owner, operator, receiver), 0);

    vm.prank(owner);
    vault.increaseBorrowAllowance(operator, receiver, amount);

    assertEq(vault.borrowAllowance(owner, operator, receiver), amount);
  }

  function test_Decrease_Borrow_Allowance(uint256 decreaseAmount_) public {
    vm.assume(decreaseAmount_ > 0 && decreaseAmount_ <= 1 ether);

    uint256 difference = 1 ether - decreaseAmount_;

    vm.startPrank(owner);
    vault.increaseBorrowAllowance(operator, receiver, 1 ether);
    vault.decreaseBorrowAllowance(operator, receiver, decreaseAmount_);
    vm.stopPrank();

    assertEq(vault.borrowAllowance(owner, operator, receiver), difference);
  }

  function test_Check_Allowance_Set_Via_ERC4626_Approve(uint256 amount) public {
    vm.assume(amount > 0);

    assertEq(vault.allowance(owner, receiver), 0);

    vm.prank(owner);
    // BaseVault should override erc20-approve function and assign `operator` and
    // `receiver` as the same address when calling an "approve" function.
    vault.approve(receiver, amount);

    assertEq(vault.allowance(owner, receiver), amount);
    assertEq(vault.withdrawAllowance(owner, receiver, receiver), amount);
  }

  function testFail_Check_Allowance_Decrease_Via_ERC4626_Reverts(uint256 decreaseAmount_) public {
    vm.assume(decreaseAmount_ > 0 && decreaseAmount_ <= 1 ether);

    vm.startPrank(owner);
    vault.approve(receiver, 1 ether);
    vault.decreaseAllowance(receiver, decreaseAmount_);

    assertEq(vault.allowance(owner, receiver), 1 ether);
    assertEq(vault.withdrawAllowance(owner, receiver, receiver), 1 ether);
  }

  function testFail_Operator_Try_To_Withdraw(
    uint256 depositAmount_,
    uint256 withdrawDelegated_
  )
    public
  {
    vm.assume(depositAmount_ > 0 && withdrawDelegated_ > 0 && withdrawDelegated_ < depositAmount_);
    do_deposit(depositAmount_, vault, owner);

    vm.prank(operator);
    vault.withdraw(withdrawDelegated_, receiver, owner);
  }

  function testFail_Receiver_Try_To_Withdraw(
    uint256 depositAmount_,
    uint256 withdrawDelegated_
  )
    public
  {
    vm.assume(depositAmount_ > 0 && withdrawDelegated_ > 0 && withdrawDelegated_ < depositAmount_);
    do_deposit(depositAmount_, vault, owner);

    vm.prank(receiver);
    vault.withdraw(withdrawDelegated_, receiver, owner);
  }

  function test_Withdraw_With_Permit(uint128 depositAmount_, uint128 withdrawDelegated_) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(
      depositAmount_ > minAmount && withdrawDelegated_ > 0 && withdrawDelegated_ < depositAmount_
    );
    do_deposit(depositAmount_, vault, owner);

    bytes32 pretendedActionArgsHash = keccak256(abi.encode(1));

    LibSigUtils.Permit memory permit = LibSigUtils.Permit({
      chainid: block.chainid,
      owner: owner,
      operator: operator,
      receiver: receiver,
      amount: withdrawDelegated_,
      nonce: vault.nonces(owner),
      deadline: block.timestamp + 1 days,
      actionArgsHash: pretendedActionArgsHash
    });

    bytes32 digest = LibSigUtils.getHashTypedDataV4Digest(
      vault.DOMAIN_SEPARATOR(), LibSigUtils.getStructHashWithdraw(permit)
    );

    // This message signin is supposed to be off-chain
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPkey, digest);
    vm.prank(operator);
    vault.permitWithdraw(
      permit.owner, permit.receiver, permit.amount, permit.deadline, permit.actionArgsHash, v, r, s
    );

    assertEq(vault.withdrawAllowance(owner, operator, receiver), withdrawDelegated_);

    vm.prank(operator);
    vault.withdraw(withdrawDelegated_, receiver, owner);

    assertEq(IERC20(collateralAsset).balanceOf(receiver), withdrawDelegated_);
  }

  function testFail_Receiver_Try_To_Borrow(uint256 depositAmount_, uint256 borrowDelegated_) public {
    vm.assume(depositAmount_ > 0 && borrowDelegated_ > 0 && borrowDelegated_ <= BORROW_LIMIT);
    do_deposit(depositAmount_, vault, owner);

    vm.prank(receiver);
    vault.borrow(borrowDelegated_, receiver, owner);
  }

  function test_Borrow_With_Permit(uint256 borrowDelegated_) public {
    uint256 minAmount = vault.minAmount();
    vm.assume(borrowDelegated_ > minAmount && borrowDelegated_ <= BORROW_LIMIT);
    do_deposit(10 ether, vault, owner);

    bytes32 pretendedActionArgsHash = keccak256(abi.encode(1));

    LibSigUtils.Permit memory permit = LibSigUtils.Permit({
      chainid: block.chainid,
      owner: owner,
      operator: operator,
      receiver: receiver,
      amount: borrowDelegated_,
      nonce: vault.nonces(owner),
      deadline: block.timestamp + 1 days,
      actionArgsHash: pretendedActionArgsHash
    });

    bytes32 digest = LibSigUtils.getHashTypedDataV4Digest(
      vault.DOMAIN_SEPARATOR(), LibSigUtils.getStructHashBorrow(permit)
    );

    // This message signin is supposed to be off-chain
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPkey, digest);

    vm.prank(operator);
    vault.permitBorrow(
      permit.owner, permit.receiver, permit.amount, permit.deadline, permit.actionArgsHash, v, r, s
    );

    assertEq(vault.borrowAllowance(owner, operator, receiver), borrowDelegated_);

    vm.prank(operator);
    vault.borrow(borrowDelegated_, receiver, owner);

    assertEq(IERC20(debtAsset).balanceOf(receiver), borrowDelegated_);
  }

  function test_Error_Zero_Address() public {
    vm.startPrank(owner);

    vm.expectRevert(VaultPermissions.VaultPermissions__zeroAddress.selector);
    vault.increaseWithdrawAllowance(address(0), receiver, 1 ether);

    vm.expectRevert(VaultPermissions.VaultPermissions__zeroAddress.selector);
    vault.increaseWithdrawAllowance(operator, address(0), 1 ether);

    vault.increaseWithdrawAllowance(operator, receiver, 1 ether);

    vm.expectRevert();
    vault.decreaseWithdrawAllowance(address(0), receiver, 1 ether);

    vm.expectRevert();
    vault.decreaseWithdrawAllowance(operator, address(0), 1 ether);

    vm.expectRevert(VaultPermissions.VaultPermissions__zeroAddress.selector);
    vault.increaseBorrowAllowance(address(0), receiver, 1 ether);

    vm.expectRevert(VaultPermissions.VaultPermissions__zeroAddress.selector);
    vault.increaseBorrowAllowance(operator, address(0), 1 ether);

    vault.increaseBorrowAllowance(operator, receiver, 1 ether);

    vm.expectRevert();
    vault.decreaseBorrowAllowance(address(0), receiver, 1 ether);

    vm.expectRevert();
    vault.decreaseBorrowAllowance(operator, address(0), 1 ether);

    vm.stopPrank();
  }

  function test_Error_Allowance_Below_Zero() public {
    vm.startPrank(owner);

    vault.increaseWithdrawAllowance(operator, receiver, 1 ether);
    vm.expectRevert(VaultPermissions.VaultPermissions__allowanceBelowZero.selector);
    vault.decreaseWithdrawAllowance(operator, receiver, 2 ether);

    vault.increaseBorrowAllowance(operator, receiver, 1 ether);
    vm.expectRevert(VaultPermissions.VaultPermissions__allowanceBelowZero.selector);
    vault.decreaseBorrowAllowance(operator, receiver, 2 ether);

    vm.stopPrank();
  }

  function test_Error_Insufficient_Withdraw_Allowance() public {
    do_deposit(2 ether, vault, owner);

    vm.prank(owner);
    vault.increaseWithdrawAllowance(operator, receiver, 1 ether);

    vm.expectRevert(VaultPermissions.VaultPermissions__insufficientWithdrawAllowance.selector);
    vm.prank(operator);
    vault.withdraw(2 ether, receiver, owner);
  }

  function test_Error_Insufficient_Borrow_Allowance() public {
    do_deposit(2 ether, vault, owner);

    vm.prank(owner);
    vault.increaseBorrowAllowance(operator, receiver, BORROW_LIMIT);

    vm.expectRevert(VaultPermissions.VaultPermissions__insufficientBorrowAllowance.selector);
    vm.prank(operator);
    vault.borrow(BORROW_LIMIT + 1, receiver, owner);
  }

  function test_Error_Expired_Deadline_Withdraw_Permit() public {
    do_deposit(1 ether, vault, owner);

    bytes32 pretendedActionArgsHash = keccak256(abi.encode(1));

    LibSigUtils.Permit memory permit = LibSigUtils.Permit({
      chainid: block.chainid,
      owner: owner,
      operator: operator,
      receiver: receiver,
      amount: 1 ether,
      nonce: vault.nonces(owner),
      deadline: block.timestamp + 1 days,
      actionArgsHash: pretendedActionArgsHash
    });

    bytes32 digest = LibSigUtils.getHashTypedDataV4Digest(
      vault.DOMAIN_SEPARATOR(), LibSigUtils.getStructHashWithdraw(permit)
    );

    // This message signin is supposed to be off-chain
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPkey, digest);

    // warp to a timestamp is supposed to be off-chain
    uint256 expiredDeadlineTimestamp = block.timestamp + 1 days + 1;
    vm.warp(expiredDeadlineTimestamp);

    vm.expectRevert(VaultPermissions.VaultPermissions__expiredDeadline.selector);
    vm.prank(operator);
    vault.permitWithdraw(
      permit.owner, permit.receiver, permit.amount, permit.deadline, permit.actionArgsHash, v, r, s
    );
  }

  function test_Error_Expired_Deadline_Borrow_Permit() public {
    do_deposit(1 ether, vault, owner);

    bytes32 pretendedActionArgsHash = keccak256(abi.encode(1));

    LibSigUtils.Permit memory permit = LibSigUtils.Permit({
      chainid: block.chainid,
      owner: owner,
      operator: operator,
      receiver: receiver,
      amount: BORROW_LIMIT,
      nonce: vault.nonces(owner),
      deadline: block.timestamp + 1 days,
      actionArgsHash: pretendedActionArgsHash
    });

    bytes32 digest = LibSigUtils.getHashTypedDataV4Digest(
      vault.DOMAIN_SEPARATOR(), LibSigUtils.getStructHashBorrow(permit)
    );

    // This message signin is supposed to be off-chain
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPkey, digest);

    // warp to a timestamp is supposed to be off-chain
    uint256 expiredDeadlineTimestamp = block.timestamp + 1 days + 1;
    vm.warp(expiredDeadlineTimestamp);

    vm.expectRevert(VaultPermissions.VaultPermissions__expiredDeadline.selector);
    vm.prank(operator);
    vault.permitBorrow(
      permit.owner, permit.receiver, permit.amount, permit.deadline, permit.actionArgsHash, v, r, s
    );
  }

  function test_Error_Vault_Permissions_Invalid_Signature_Withdraw_Permit() public {
    do_deposit(1 ether, vault, owner);

    bytes32 pretendedActionArgsHash = keccak256(abi.encode(1));

    LibSigUtils.Permit memory permit = LibSigUtils.Permit({
      chainid: block.chainid,
      owner: owner,
      operator: operator,
      receiver: receiver,
      amount: 1 ether,
      nonce: vault.nonces(owner),
      deadline: block.timestamp + 1 days,
      actionArgsHash: pretendedActionArgsHash
    });

    bytes32 digest = LibSigUtils.getHashTypedDataV4Digest(
      vault.DOMAIN_SEPARATOR(), LibSigUtils.getStructHashWithdraw(permit)
    );

    // This message signin is supposed to be off-chain
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPkey, digest);

    LibSigUtils.Permit memory wrongPermit = permit;

    // Change owner
    wrongPermit.owner = receiver;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitWithdraw(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );

    // Change operator
    wrongPermit.operator = receiver;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitWithdraw(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );

    // Change receiver
    wrongPermit.receiver = operator;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitWithdraw(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );

    // Change amount
    wrongPermit.amount = 2 ether;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitWithdraw(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );

    // Change deadline
    wrongPermit.deadline = block.timestamp + 2 days;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitWithdraw(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );
  }

  function test_Error_Vault_Permissions_Invalid_Signature_Borrow_Permit() public {
    do_deposit(1 ether, vault, owner);

    bytes32 pretendedActionArgsHash = keccak256(abi.encode(1));

    LibSigUtils.Permit memory permit = LibSigUtils.Permit({
      chainid: block.chainid,
      owner: owner,
      operator: operator,
      receiver: receiver,
      amount: BORROW_LIMIT,
      nonce: vault.nonces(owner),
      deadline: block.timestamp + 1 days,
      actionArgsHash: pretendedActionArgsHash
    });

    bytes32 digest = LibSigUtils.getHashTypedDataV4Digest(
      vault.DOMAIN_SEPARATOR(), LibSigUtils.getStructHashBorrow(permit)
    );

    // This message signin is supposed to be off-chain
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPkey, digest);

    LibSigUtils.Permit memory wrongPermit = permit;

    // Change owner
    wrongPermit.owner = receiver;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitBorrow(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );

    // Change operator
    wrongPermit.operator = receiver;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitBorrow(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );

    // Change receiver
    wrongPermit.receiver = operator;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitBorrow(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );

    // Change amount
    wrongPermit.amount = 2 ether;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitBorrow(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );

    // Change deadline
    wrongPermit.deadline = block.timestamp + 2 days;
    vm.expectRevert(VaultPermissions.VaultPermissions__invalidSignature.selector);
    vm.prank(operator);
    vault.permitBorrow(
      wrongPermit.owner,
      wrongPermit.receiver,
      wrongPermit.amount,
      wrongPermit.deadline,
      wrongPermit.actionArgsHash,
      v,
      r,
      s
    );
  }

  function testFail_Spend_Allowance_Issue() public {
    do_deposit(1 ether, vault, owner);

    vm.startPrank(owner);
    vault.approve(receiver, 1 ether);
    uint256 allowance = vault.allowance(owner, receiver);
    vm.stopPrank();

    vm.startPrank(receiver);
    vault.transferFrom(owner, receiver, 1 ether);
    uint256 allowance2 = vault.allowance(owner, receiver);
    vm.stopPrank();

    assertEq(allowance, allowance2);
  }

  function test_Spend_Allowance_Issue() public {
    do_deposit(1 ether, vault, owner);

    vm.startPrank(owner);
    vault.approve(receiver, 1 ether);
    uint256 allowance = vault.allowance(owner, receiver);
    vm.stopPrank();

    vm.startPrank(receiver);
    vault.transferFrom(owner, receiver, 1 ether);
    uint256 allowance2 = vault.allowance(owner, receiver);
    vm.stopPrank();

    assertEq(allowance, 1 ether);
    assertEq(allowance2, 0);
  }
}
