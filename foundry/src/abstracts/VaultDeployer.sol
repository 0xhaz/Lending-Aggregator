// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title VaultDeployer
 * @notice Abstract contract to be inherited by vault deployer for whitelisted template factories
 * This contract provides methods that facilitate information for front-end applications
 */

import {IChief} from "../interfaces/IChief.sol";

abstract contract VaultDeployer {
  ////////////////// CUSTOM ERRORS //////////////////
  error VaultDeployer__onlyChief_notAuthorized();
  error VaultDeployer__onlyTimelock_notAuthorized();
  error VaultDeployer__zeroAddress();

  ////////////////// EVENTS //////////////////
  /**
   * @dev Emit when a vault is registered
   * @param vault Address of the vault
   * @param asset Address of the asset
   * @param salt used for address generation
   */
  event VaultRegistered(address vault, address asset, bytes32 salt);

  //////////////////////// STATE VARIABLES & MODIFIERS ////////////////////////
  address public immutable chief;

  address[] public allVaults;
  mapping(address => address[]) public vaultsByAsset;
  mapping(bytes32 => address) public configAddress;

  modifier onlyChief() {
    if (msg.sender != chief) {
      revert VaultDeployer__onlyChief_notAuthorized();
    }
    _;
  }

  modifier onlyTimelock() {
    if (msg.sender != IChief(chief).timelock()) {
      revert VaultDeployer__onlyTimelock_notAuthorized();
    }
    _;
  }

  //////////////////////// CONSTRUCTOR ////////////////////////

  /**
   * @notice Abstract constructor of a new {VaultDeployer}
   * @param chief_ address
   * @dev Requirements:
   * - Must pass non-zero {Chief} address, that could be checked at child contract
   */
  constructor(address chief_) {
    if (chief_ == address(0)) {
      revert VaultDeployer__zeroAddress();
    }
    chief = chief_;
  }

  //////////////////////// FUNCTIONS ////////////////////////

  /**
   * @notice Returns an array of vaults based on their `asset` type
   * @param asset address
   * @param startIndex number to start loop in vaults[] array
   * @param count number to end loop in vaults[] array
   */
  function getVaults(
    address asset,
    uint256 startIndex,
    uint256 count
  )
    external
    view
    returns (address[] memory vaults)
  {
    vaults = new address[](count);
    for (uint256 i; i < count; i++) {
      vaults[i] = vaultsByAsset[asset][startIndex + i];
    }
  }

  /**
   * @dev Registers a record of `vault` based on vault's `asset` type
   * @param vault address
   * @param asset address of the vault
   */

  function _registerVault(address vault, address asset, bytes32 salt) internal onlyChief {
    // Store the address of the deployed contract
    configAddress[salt] = vault;
    vaultsByAsset[asset].push(vault);
    allVaults.push(vault);
    emit VaultRegistered(vault, asset, salt);
  }
}
