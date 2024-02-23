// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title YieldVaultBeaconFactory
 * @notice A factory contract through which new yield vaults are created
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

contract YieldVaultBeaconFactory is IBeacon, VaultDeployer {
  using SafeERC20 for IERC20;
  using Strings for uint256;

  struct YVaultData {
    address asset;
    string name;
    string symbol;
    bytes32 salt;
    bytes bytecode;
  }

  /////////////////////////////// CUSTOM ERROR ///////////////////////////////
  error YieldVaultBeaconFactory__deployVault_noImplementation();
  error YieldVaultBeaconFactory__setImplementation_notContract();

  /////////////////////////////// EVENTS ///////////////////////////////
  /**
   * @dev Emit when a new yield vault is deployed
   *
   * @param vault The address of the new yield vault
   * @param asset The address of the asset the vault is using
   * @param name The name of the tokenized asset shares
   * @param symbol of the tokenized asset shares
   * @param salt distinguishing this vault
   */
  event DeployYieldVault(
    address indexed vault, address indexed asset, string name, string symbol, bytes32 salt
  );

  /**
   * @dev Emitted when the implementation returned by the beacon is updated
   * @param implementation Address of the new implementation
   */
  event Upgraded(address indexed implementation);

  /////////////////////////////// STATE VARS ///////////////////////////////
  uint256 public nonce;
  address private _implementation;

  /////////////////////////////// CONSTRUCTOR ///////////////////////////////
  /**
   * @notice Constructor of a new {YieldVaultFactory}
   * @param chief_ address of {Chief}
   * @param implementation_ address of the master YieldVault.sol
   * @dev Requirements:
   * - Must comply with {VaultDeployer} requirements
   */
  constructor(address chief_, address implementation_) VaultDeployer(chief_) {
    _implementation = implementation_;
  }

  /////////////////////////////// EXTERNAL FUNCTIONS ///////////////////////////////
  /**
   * @dev Returns the current implementation address
   */
  function implementation() public view virtual override returns (address) {
    return _implementation;
  }

  /**
   * @notice deploys a new {YieldVault}
   * @param deployData the encoded data containing asset and providers
   * @dev Requirements:
   * - Must be called by the chief contract
   */
  function deployVault(bytes memory deployData) external onlyChief returns (address vault) {
    if (implementation() == address(0)) {
      revert YieldVaultBeaconFactory__deployVault_noImplementation();
    }

    uint256 initAssets = 1e6;

    YVaultData memory vdata;
    address futureVault;

    /// @dev Scoped section created to avoid stack too deep error
    {
      (address asset, ILendingProvider[] memory providers) =
        abi.decode(deployData, (address, ILendingProvider[]));

      // use tx.origin because it will pull assets from EOA who originated the `Chief.deployVault`
      IERC20(asset).safeTransferFrom(tx.origin, address(this), initAssets);

      vdata.asset = asset;

      string memory assetSymbol = IERC20Metadata(asset).symbol();

      // Example of `name_`: "Fuji-V2 WETH YieldVault-1"
      vdata.name =
        string(abi.encodePacked("Fuji-V2 ", assetSymbol, " YieldVault", "-", nonce.toString()));
      // Example of `symbol_`: 'fyvWETH-1"
      vdata.symbol = string(abi.encodePacked("fyv", assetSymbol, "-", nonce.toString()));

      vdata.salt = keccak256(abi.encode(deployData, nonce, block.number));

      bytes memory initCall = abi.encodeWithSignature(
        "initialize(address,address,string,string,address[])",
        vdata.asset,
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
    require(vault == futureVault, "Addresses not equal");

    _registerVault(vault, vdata.asset, vdata.salt);

    emit DeployYieldVault(vault, vdata.asset, vdata.name, vdata.symbol, vdata.salt);

    IVault(vault).deposit(initAssets, IChief(chief).timelock());
  }

  /**
   * @dev Upgrades the beacon to a new implementation
   * Emits an {Upgraded} event
   * @dev Requirements:
   * - msg.sender must be the timelock
   * - `newImplementation` must be a contract
   */
  function upgradeTo(address newImplementation) public virtual onlyTimelock {
    _setImplementation(newImplementation);
    emit Upgraded(newImplementation);
  }

  /**
   * @notice Sets the implementation contract address for this beacon
   * @param newImplementation The address of the new implementation
   * @dev Requirements:
   * - `newImplementation` must be a contract
   */
  function _setImplementation(address newImplementation) private {
    if (!Address.isContract(newImplementation)) {
      revert YieldVaultBeaconFactory__setImplementation_notContract();
    }
    _implementation = newImplementation;
  }
}
