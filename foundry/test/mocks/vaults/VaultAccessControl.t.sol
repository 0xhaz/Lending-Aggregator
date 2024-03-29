// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {MockingSetup} from "../MockingSetup.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {MockProvider} from "../../../src/mocks/MockProvider.sol";
import {MockOracle} from "../../../src/mocks/MockOracle.sol";
import {ILendingProvider} from "../../../src/interfaces/ILendingProvider.sol";
import {BaseVault} from "../../../src/abstracts/BaseVault.sol";
import {SystemAccessControl} from "../../../src/access/SystemAccessControl.sol";

contract VaultAccessControlUnitTests is MockingSetup {
  event MinDepositAmountChanged(uint256 newMinDeposit);
  event DepositCapChanged(uint256 newDepositCap);

  function setUp() public {}

  // BaseVault parameter changing fuzz tests
  function test_Try_Foe_Set_Min_Deposit_Amount(address foe, uint256 amount) public {
    vm.assume(
      foe != address(timelock) && foe != address(0) && foe != address(this) && foe != address(chief)
        && amount > 0
    );
    vm.expectRevert(
      SystemAccessControl.SystemAccessControl__onlyTimelock_callerIsNotTimelock.selector
    );
    vm.prank(foe);
    vault.setMinAmount(amount);
  }

  function test_Try_Foe_Set_Providers(address foe) public {
    vm.assume(
      foe != address(timelock) && foe != address(0) && foe != address(this) && foe != address(chief)
    );
    ILendingProvider maliciousProvider = new MockProvider();
    ILendingProvider[] memory providers = new ILendingProvider[](1);
    providers[0] = maliciousProvider;
    vm.expectRevert(
      SystemAccessControl.SystemAccessControl__onlyTimelock_callerIsNotTimelock.selector
    );
    vm.prank(foe);
    vault.setProviders(providers);
  }

  function test_Try_Foe_Set_Active_Provider(address foe) public {
    vm.assume(
      foe != address(timelock) && foe != address(0) && foe != address(this) && foe != address(chief)
    );
    ILendingProvider maliciousProvider = new MockProvider();
    vm.expectRevert(
      abi.encodeWithSelector(
        SystemAccessControl.SystemAccessControl__onlyTimelock_callerIsNotTimelock.selector
      )
    );
    vm.prank(foe);
    vault.setActiveProvider(maliciousProvider);
  }

  // BorrowingVault borrowing parameters changing tests
  function test_Try_Foe_Set_Oracle(address foe) public {
    vm.assume(
      foe != address(timelock) && foe != address(0) && foe != address(this) && foe != address(chief)
    );
    MockOracle maliciousOracle = new MockOracle();
    vm.expectRevert(
      SystemAccessControl.SystemAccessControl__onlyTimelock_callerIsNotTimelock.selector
    );
    vm.prank(foe);
    vault.setOracle(maliciousOracle);
  }

  function test_Try_Foe_Set_Max_Ltv(address foe) public {
    vm.assume(
      foe != address(timelock) && foe != address(0) && foe != address(this) && foe != address(chief)
    );
    uint256 newMaliciousMaxLtv = 1 * 1e16;
    vm.expectRevert(
      SystemAccessControl.SystemAccessControl__onlyTimelock_callerIsNotTimelock.selector
    );
    vm.prank(foe);
    vault.setMaxLtv(newMaliciousMaxLtv);
  }

  function test_Try_Foe_Set_Liq_Ratio(address foe) public {
    vm.assume(
      foe != address(timelock) && foe != address(0) && foe != address(this) && foe != address(chief)
    );
    uint256 newMaliciousLiqRatio = 10 * 1e16;
    vm.expectRevert(
      SystemAccessControl.SystemAccessControl__onlyTimelock_callerIsNotTimelock.selector
    );
    vm.prank(foe);
    vault.setLiqRatio(newMaliciousLiqRatio);
  }
}
