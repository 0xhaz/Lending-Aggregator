// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title BorrowingVaultBeaconFactory
 * @notice A factory contract through which new borrowing vaults are created
 * This vault factory deploys (OZ implementation) VaultBeaconProxy contracts that
 * point to `implementation` state variable as the target implementation of the proxy
 */

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VaultBeaconProxy} from "../VaultBeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Create2Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/Create2Upgradeable.sol";
import {VaultDeployer} from "../../abstracts/VaultDeployer.sol";
import {ILendingProvider} from "../../interfaces/ILendingProvider.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {IChief} from "../../interfaces/IChief.sol";

contract BorrowingVaultBeaconFactory is IBeacon, VaultDeployer {
  using SafeERC20 for IERC20;
  using Strings for uint256;

  struct BVaultData {
    address asset;
    address debtAsset;
    string name;
    string symbol;
    bytes32 salt;
    bytes bytecode;
  }

  /////////////////////////////// CUSTOM ERROR ///////////////////////////////
  error BorrowingVaultBeaconFactory__deployVault_noImplementation();
  error BorrowingVaultBeaconFactory__setImplementation_notContract();

  /////////////////////////////// EVENTS ///////////////////////////////
  /**
   * @dev Emit when a new borrowing vault is deployed
   *
   * @param vault The address of the new borrowing vault
   * @param asset The address of the asset the vault is using
   * @param debtAsset The address of the debt asset the vault is using
   * @param name The name of the tokenized asset shares
   * @param symbol The symbol of the tokenized asset shares
   * @param salt distinguishing this vault
   */
  event DeployBorrowingVault(
    address indexed vault,
    address indexed asset,
    address indexed debtAsset,
    string name,
    string symbol,
    bytes32 salt
  );

  /**
   * @dev Emitted when the implementation returned by the beacon is changed
   * @param implementation Address of the new implementation
   */
  event Upgraded(address indexed implementation);

  /////////////////////////////// STATE VARS ///////////////////////////////
  uint256 public nonce;
  address private _implementation;

  /////////////////////////////// CONSTRUCTOR ///////////////////////////////
  /**
   * @notice Constructor of a new {BorrowingVaultFactory}
   *
   * @param chief_ The address of the chief contract
   * @param implementation_ The address of the BorrowingVault
   *
   * @dev Requirements:
   * - Must comply with {VaultDeployer} requirements
   */
  constructor(address chief_, address implementation_) VaultDeployer(chief_) {
    _setImplementation(implementation_);
  }

  /////////////////////////////// FUNCTIONS ///////////////////////////////
  /**
   * @dev Returns the current implementation address
   */
  function implementation() public view virtual override returns (address) {
    return _implementation;
  }

  /**
   * @notice Deploys a new {BorrowingVault}
   * @param deployData the encoded data containing asset, debtAsset, oracle and providers
   * @dev Requirements:
   * - Must be called from {Chief} contract
   */
  function deployVault(bytes memory deployData) external onlyChief returns (address vault) {
    if (implementation() == address(0)) {
      revert BorrowingVaultBeaconFactory__deployVault_noImplementation();
    }

    uint256 initAssets = 1e6;

    BVaultData memory vdata;
    address futureVault;

    /// @dev Scoped section created to avoid stack too deep error
    {
      (address asset, address debtAsset, ILendingProvider[] memory providers) =
        abi.decode(deployData, (address, address, ILendingProvider[]));

      // use tx.origin because it will put assets from EOA who originated the `Chief.deployVault`
      IERC20(asset).safeTransferFrom(tx.origin, address(this), initAssets);

      vdata.asset = asset;
      vdata.debtAsset = debtAsset;

      string memory assetSymbol = IERC20Metadata(asset).symbol();
      string memory debtSymbol = IERC20Metadata(debtAsset).symbol();

      //   Example of `name_`: "Fuji-V2 WETH-DAI BorrowingVault-1"
      vdata.name = string(
        abi.encodePacked(
          "Fuji-V2 ", assetSymbol, "-", debtSymbol, " BorrowingVault", "-", nonce.toString()
        )
      );

      //   Example of `symbol_`: "fbvWETHDAI-1"
      vdata.symbol = string(abi.encodePacked("fbv", assetSymbol, debtSymbol, "-", nonce.toString()));

      vdata.salt = keccak256(abi.encode(deployData, nonce, block.number));

      bytes memory initCall = abi.encodeWithSignature(
        "initialize(address,address,address,string,string,address[])",
        vdata.asset,
        vdata.debtAsset,
        chief,
        vdata.name,
        vdata.symbol,
        providers
      );

      vdata.bytecode = abi.encodePacked(
        type(VaultBeaconProxy).creationCode, abi.encode(address(this), initCall, address(chief))
      );

      //   Predict address to safeIncreaseAllowance to future vault initialization of shares
      futureVault = Create2Upgradeable.computeAddress(vdata.salt, keccak256(vdata.bytecode));

      //   Allow future vault to pull assets from factory for deployment
      IERC20(asset).safeIncreaseAllowance(futureVault, initAssets);

      nonce++;
    }

    // Create2 library reverts if returned address is zero
    vault = Create2Upgradeable.deploy(0, vdata.salt, vdata.bytecode);
    require(vault == futureVault, "BorrowingVaultBeaconFactory: invalid vault address");

    _registerVault(vault, vdata.asset, vdata.salt);

    emit DeployBorrowingVault(
      vault, vdata.asset, vdata.debtAsset, vdata.name, vdata.symbol, vdata.salt
    );

    IVault(vault).deposit(initAssets, IChief(chief).timelock());
  }

  /**
   * @dev Upgrades the beacon to a new implementation
   *
   * Emits an {Upgraded} event
   *
   * @dev Requirements:
   * - msg.sender must be the timelock of the chief contract
   * - `newImplementation` must be a contract
   */
  function upgradeTo(address newImplementation) external onlyTimelock {
    _setImplementation(newImplementation);

    emit Upgraded(newImplementation);
  }

  /**
   * @notice Sets the implementation of the beacon
   *
   * @param newImplementation The address of the new implementation
   * @dev Requirements:
   * -`newImplementation` must be a contract
   */
  function _setImplementation(address newImplementation) private {
    if (!Address.isContract(newImplementation)) {
      revert BorrowingVaultBeaconFactory__setImplementation_notContract();
    }
    _implementation = newImplementation;
  }
}
