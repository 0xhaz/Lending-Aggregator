// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {LibSigUtils} from "../../src/libraries/LibSigUtils.sol";
import {BorrowingVault} from "../../src/vaults/borrowing/BorrowingVault.sol";
import {BorrowingVaultUpgradeable} from "../../src/vaults/borrowing/BorrowingVaultUpgradeable.sol";
import {BorrowingVaultBeaconFactory} from
  "../../src/vaults/borrowing/BorrowingVaultBeaconFactory.sol";
import {FujiOracle} from "../../src/FujiOracle.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRouter} from "../../src/interfaces/IRouter.sol";
import {IVaultPermissions} from "../../src/interfaces/IVaultPermissions.sol";
import {Chief} from "../../src/Chief.sol";
import {IWETH9} from "../../src/abstracts/WETH9.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IConnext} from "../../src/interfaces/connext/IConnext.sol";
import {ILendingProvider} from "../../src/interfaces/ILendingProvider.sol";
import {CoreRoles} from "../../src/access/CoreRoles.sol";
import {IFujiOracle} from "../../src/interfaces/IFujiOracle.sol";
import {ConnextRouter} from "../../src/routers/ConnextRouter.sol";

contract ForkingSetup2 is CoreRoles, Test {
  using SafeERC20 for IERC20;
  using Address for address;

  struct PriceFeed {
    string asset;
    address chainlink;
  }

  struct NestedMapping {
    string asset1;
    string asset2;
    address market;
  }

  struct Vault {
    string name;
    address addr;
    address asset;
    address debtAsset;
    uint256 sampleDeposit;
    uint256 sampleBorrow;
  }

  struct VaultConfig {
    string collateral;
    string debt;
    uint256 liqRatio;
    uint256 maxLtv;
    string name;
    string[] providers;
    uint256 rating;
  }

  struct YieldVaultConfig {
    string asset;
    string name;
    string[] providers;
    uint256 rating;
  }

  uint32 public constant MAINNET_DOMAIN = 6648936;
  uint32 public constant OPTIMISM_DOMAIN = 1869640809;
  uint32 public constant ARBITRUM_DOMAIN = 1634886255;
  uint32 public constant POLYGON_DOMAIN = 1886350457;
  uint32 public constant GOERLI_DOMAIN = 1735353714;
  uint32 public constant OPTIMISM_GOERLI_DOMAIN = 1735356532;
  uint32 public constant MUMBAI_DOMAIN = 9991;

  uint32 public constant MAINNET_BLOCK = 17775621;
  uint32 public constant OPTIMISM_BLOCK = 107378765;
  uint32 public constant ARBITRUM_BLOCK = 115050048;
  uint32 public constant POLYGON_BLOCK = 45530260;
  uint32 public constant GOERLI_BLOCK = 9410146;
  uint32 public constant OPTIMISM_GOERLI_BLOCK = 12463641;
  uint32 public constant MUMBAI_BLOCK = 38311402;

  uint256 public constant ALICE_PK = 0xA;
  address public ALICE = vm.addr(ALICE_PK);
  uint256 public constant BOB_PK = 0xB;
  address public BOB = vm.addr(BOB_PK);
  uint256 public constant CHARLIE_PK = 0xC;
  address public CHARLIE = vm.addr(CHARLIE_PK);

  Chief chief;
  ConnextRouter connextRouter;
  TimelockController timelock;
  IFujiOracle oracle;
  BorrowingVaultBeaconFactory factory;
  address implementation;

  Vault[] allVaults;
  mapping(address => mapping(address => uint256)) cachedPrices;
  mapping(address => uint8) cachedDecimals;

  address connextCore;

  uint256 public constant BORROW_BASE = 500;

  string chainName;
  string configJson;

  constructor() {
    vm.label(ALICE, "alice");
    vm.label(BOB, "bob");
    vm.label(CHARLIE, "charlie");
  }

  function setUpFork() public {
    chainName = vm.envString("CHAIN_NAME");

    _createAndSelectFork();

    string memory path = string.concat("deploy-configs/", chainName, ".json");
    configJson = vm.readFile(path);
  }

  function _createAndSelectFork() internal {
    bool ignoreCacheBlock = tryLoadEnvBool(false, "IGNORE_CACHE_BLOCK");

    if (ignoreCacheBlock) {
      vm.createSelectFork(chainName);
    } else if (areEq(chainName, "ethereum")) {
      vm.createSelectFork(chainName, MAINNET_BLOCK);
    } else if (areEq(chainName, "optimism")) {
      vm.createSelectFork(chainName, OPTIMISM_BLOCK);
    } else if (areEq(chainName, "arbitrum")) {
      vm.createSelectFork(chainName, ARBITRUM_BLOCK);
    } else if (areEq(chainName, "polygon")) {
      vm.createSelectFork(chainName, POLYGON_BLOCK);
    } else if (areEq(chainName, "goerli")) {
      vm.createSelectFork(chainName, GOERLI_BLOCK);
    } else if (areEq(chainName, "optimism_goerli")) {
      vm.createSelectFork(chainName, OPTIMISM_GOERLI_BLOCK);
    } else if (areEq(chainName, "mumbai")) {
      vm.createSelectFork(chainName, MUMBAI_BLOCK);
    }
  }

  function setOrDeployChief(bool deploy) internal {
    if (deploy) {
      chief = new Chief(true, false);
    } else {
      chief = Chief(getAddress("Chief"));
    }
    vm.label(address(chief), "Chief");
    timelock = TimelockController(payable(chief.timelock()));
    vm.label(address(timelock), "Timelock");
  }

  function setOrDeployConnextRouter(bool deploy) internal {
    if (deploy) {
      connextCore = readAddrFromConfig("ConnextCore");
      address weth = readAddrFromConfig("WETH");

      connextRouter = new ConnextRouter(IWETH9(weth), IConnext(connextCore), Chief(chief));
    } else {
      connextRouter = ConnextRouter(payable(getAddress("ConnextRouter")));
    }
  }

  function setOrDeployFujiOracle(bool deploy) internal {
    bytes memory raw = vm.parseJson(configJson, ".price-feeds");
    PriceFeed[] memory list = abi.decode(raw, (PriceFeed[]));

    uint256 len = list.length;

    if (deploy) {
      address[] memory addrs = new address[](len);
      address[] memory feeds = new address[](len);

      for (uint256 i; i < len; i++) {
        addrs[i] = readAddrFromConfig(list[i].asset);
        vm.label(addrs[i], list[i].asset);
        feeds[i] = list[i].chainlink;
      }
      oracle = new FujiOracle(addrs, feeds, address(chief));
    } else {
      oracle = IFujiOracle(getAddress("FujiOracle"));
    }
    vm.label(address(oracle), "FujiOracle");
  }

  function setOrDeployBorrowingVaultFactory(bool deployFactory, bool deployImplementation) internal {
    if (deployFactory) {
      if (deployImplementation) {
        implementation = address(new BorrowingVaultUpgradeable());
      } else {
        implementation = getAddress("BorrowingVaultImplementation");
      }
      factory = new BorrowingVaultBeaconFactory(address(chief), implementation);
    } else {
      factory = BorrowingVaultBeaconFactory(getAddress("BorrowingVaultBeaconFactory"));
      implementation = getAddress("BorrowingVaultUpgradeable");
    }
    vm.label(address(factory), "BorrowingVaultBeaconFactory");

    if (!chief.allowedVaultFactory(address(factory))) {
      bytes memory data2 =
        abi.encodeWithSelector(chief.allowVaultFactory.selector, address(factory), true);
      _callWithTimelock(address(chief), data2);
    }
  }

  function setOrDeployBorrowingVaults(bool deploy) internal {
    bytes memory raw = vm.parseJson(configJson, ".borrowing-vaults");
    VaultConfig[] memory vaults = abi.decode(raw, (VaultConfig[]));

    uint256 minCollateral = 1e6;

    uint256 len = vaults.length;
    address collateral;
    address debt;
    string memory name;
    uint256 rating;
    uint256 liqRatio;
    uint256 maxLtv;
    string[] memory providerNames;

    for (uint256 i; i < len; i++) {
      collateral = readAddrFromConfig(vaults[i].collateral);
      vm.label(collateral, vaults[i].collateral);
      debt = readAddrFromConfig(vaults[i].debt);
      vm.label(debt, vaults[i].debt);
      name = vaults[i].name;
      rating = vaults[i].rating;
      liqRatio = vaults[i].liqRatio;
      maxLtv = vaults[i].maxLtv;
      providerNames = vaults[i].providers;

      if (deploy) {
        uint256 providersLen = providerNames.length;
        ILendingProvider[] memory providers = new ILendingProvider[](providersLen);
        for (uint256 j; j < providersLen; j++) {
          providers[j] = ILendingProvider(getAddress(providerNames[j]));
        }

        if (IERC20(collateral).allowance(msg.sender, address(factory)) < minCollateral) {
          IERC20(collateral).safeIncreaseAllowance(address(factory), minCollateral);
        }
        deal(collateral, msg.sender, minCollateral);
        address v =
          chief.deployVault(address(factory), abi.encode(collateral, debt, providers), rating);
        _pushVault(v, collateral, debt, maxLtv, name);

        _callWithTimelock(
          v, abi.encodeWithSelector(BorrowingVaultUpgradeable.setOracle.selector, address(oracle))
        );
        _callWithTimelock(
          v,
          abi.encodeWithSelector(BorrowingVaultUpgradeable.setLtvFactors.selector, maxLtv, liqRatio)
        );
      } else {
        address addr = getAddress(name);
        _pushVault(addr, collateral, debt, maxLtv, name);
      }
    }
  }

  function _pushVault(
    address vault,
    address collateral,
    address debt,
    uint256 maxLtv,
    string memory name
  )
    internal
  {
    uint8 debtDecimals = _getDecimalsOf(debt);
    uint256 price = _getPriceOf(collateral, debt);
    uint256 debtAmount = BORROW_BASE * 10 ** debtDecimals;
    // calculate required collateral amount for BORROW_BASE then multiply by 1.2
    uint256 collateralAmount = (debtAmount * 1e36) / (maxLtv * price) * 60 / 50;

    allVaults.push(Vault(name, vault, collateral, debt, collateralAmount, debtAmount));
    vm.label(vault, name);
  }

  function _getDecimalsOf(address asset) internal returns (uint8 decimals) {
    if (cachedDecimals[asset] == 0) {
      decimals = IERC20Metadata(asset).decimals();
      cachedDecimals[asset] = decimals;
    } else {
      decimals = cachedDecimals[asset];
    }
  }

  function _getPriceOf(address asset1, address asset2) internal returns (uint256 price) {
    if (cachedPrices[asset1][asset2] == 0) {
      uint8 decimals = _getDecimalsOf(asset2);
      price = oracle.getPriceOf(asset2, asset1, decimals);
      cachedPrices[asset1][asset2] = price;
    } else {
      price = cachedPrices[asset1][asset2];
    }
  }

  function getAddress(string memory contractName) internal view returns (address addr) {
    require(bytes(chainName).length != 0, "Set 'chainName' in setUp()");

    addr = _getAddress(string.concat("deployments/", chainName, "/", contractName));
  }

  function getAdressAt(
    string memory contractName,
    string memory _chainName
  )
    internal
    view
    returns (address addr)
  {
    addr = _getAddress(string.concat("deployments/", _chainName, "/", contractName));
  }

  function readAddrFromConfig(string memory key) internal returns (address) {
    return vm.parseJsonAddress(configJson, string.concat(".", key));
  }

  function _getAddress(string memory path) internal view returns (address addr) {
    string memory content = vm.readFile(path);
    addr = vm.parseAddress(content);
  }

  function _callWithTimelock(address target, bytes memory callData) internal {
    vm.prank(address(timelock));
    target.functionCall(callData);
  }
}
