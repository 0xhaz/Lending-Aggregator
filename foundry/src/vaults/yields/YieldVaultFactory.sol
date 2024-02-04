// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title YieldVaultFactory
 * @notice Factory contract to create new yield vaults
 */

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {VaultDeployer} from "../../abstracts/VaultDeployer.sol";
import {YieldVault} from "./YieldVault.sol";
import {ILendingProvider} from "../../interfaces/ILendingProvider.sol";

contract YieldVaultFactory is VaultDeployer {
  uint256 public nonce;

  //////////////////////// CONSTRUCTOR ////////////////////////
  /**
   * @notice Constructor of a new {YieldVaultFactory} contract
   * @param chief_ address of {Chief}
   * @dev Requirements:
   * - Must comply with {VaultDeployer} requirements
   */
  constructor(address chief_) VaultDeployer(chief_) {}

  //////////////////////// EXTERNAL FUNCTIONS ////////////////////////

  /**
   * @notice Deploy a new YieldVault
   * @param deployData The encoded data containing asset and providers
   * @dev Requirements:
   * - Must be called by {Chief}
   */
  function deployVault(bytes memory deployData) external onlyChief returns (address vault) {
    (address asset, ILendingProvider[] memory providers) =
      abi.decode(deployData, (address, ILendingProvider[]));

    string memory assetSymbol = IERC20Metadata(asset).symbol();

    //   Example of `name_`: "Fuji-V2 Dai Stablecoin YieldVault"
    string memory name = string(abi.encodePacked("Fuji-V2 ", assetSymbol, " YieldVault"));
    //  Example of `symbol_`: "fyvDAI"
    string memory symbol = string(abi.encodePacked("fyv", assetSymbol));

    bytes32 salt = keccak256(abi.encode(deployData, nonce));
    nonce++;
    vault = address(new YieldVault{salt: salt}(asset, chief, name, symbol, providers));
    _registerVault(vault, asset, salt);
  }
}
