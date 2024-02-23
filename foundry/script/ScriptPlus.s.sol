// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ScriptUtilities} from "./ScriptUtilities.s.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IWETH9} from "../src/abstracts/WETH9.sol";
import {IConnext} from "../src/interfaces/connext/IConnext.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {ILendingProvider} from "../src/interfaces/ILendingProvider.sol";
import {BorrowingVaultBeaconFactory} from "../src/vaults/borrowing/BorrowingVaultBeaconFactory.sol";
import {BorrowingVaultUpgradeable as BorrowingVault} from
  "../src/vaults/borrowing/BorrowingVaultUpgradeable.sol";
import {VaultBeaconProxy} from "../src/vaults/VaultBeaconProxy.sol";
import {YieldVaultBeaconFactory as YieldVaultFactory} from
  "../src/vaults/yields/YieldVaultBeaconFactory.sol";
import {YieldVaultUpgradeable as YieldVault} from "../src/vaults/yields/YieldVaultUpgradeable.sol";
import {AddrMapper} from "../src/helpers/AddrMapper.sol";
import {FujiOracle} from "../src/FujiOracle.sol";
import {Chief} from "../src/Chief.sol";
import {ConnextRouter} from "../src/routers/ConnextRouter.sol";
import {CoreRoles} from "../src/access/CoreRoles.sol";
import {RebalancerManager} from "../src/RebalancerManager.sol";
import {FlasherBalancer} from "../src/flashloans/FlasherBalancer.sol";
