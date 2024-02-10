// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title AaveEModeHelper
 * @notice Helper contract that aids to determine config Ids if a collateral debt pair is eligible
 * for Aave-V3 efficiency mode (e-mode)
 * @dev This helper contract needs to be set up
 * to find the existing emode configuration Ids use
 * query schema:
 * {
 *  emodeCategories{
 *   id
 *      label
 *   }
 * }
 *
 * Refer to each chain subgraph site at:
 * https://github.com/aave/protocol-subgraph#production-networks
 */

import {IV3Pool} from "../interfaces/aaveV3/IV3Pool.sol";
import {SystemAccessControl, IChief} from "../access/SystemAccessControl.sol";

contract AaveEModeHelper is SystemAccessControl {
  ///////////////////////////////// EVENTS /////////////////////////////////
  event EmodeConfigSet(address indexed asset, address indexed debt, uint8 configId);

  ///////////////////////////////// CUSTOM ERRORS /////////////////////////////////
  error AaveEModeHelper__constructor_addressZero();
  error AaveEModeHelper__setEModeConfig_arrayDiscrepancy();

  ///////////////////////////////// CONSTANTS /////////////////////////////////
  // collateral asset => debt asset => configId
  mapping(address => mapping(address => uint8)) internal _eModeConfigIds;

  ///////////////////////////////// CONSTRUCTOR /////////////////////////////////
  constructor(address chief_) {
    if (chief_ == address(0)) revert AaveEModeHelper__constructor_addressZero();
    __SystemAccessControl_init(chief_);
  }

  ///////////////////////////////// EXTERNAL FUNCTIONS /////////////////////////////////
  /**
   * @notice Returns the config Id if any asset-debt pair in AaveV3 pool
   * If none is found, returns 0
   * @param asset erc-20 address of the collateral asset
   * @param debt erc-20 address of the debt asset
   */
  function getEModeConfigIds(address asset, address debt) external view returns (uint8 id) {
    return _eModeConfigIds[asset][debt];
  }

  /**
   * @notice Sets the configIds for an array of `assets` and `debts`
   * @param assets ERC-20 address array to set e-mode config
   * @param debts ERC-20 address array of corresponding asset in mappings
   * @param configIds from aaveV3 pool
   */
  function setEModeConfig(
    address[] calldata assets,
    address[] calldata debts,
    uint8[] calldata configIds
  )
    external
    onlyTimelock
  {
    uint256 len = assets.length;
    if (len != debts.length || len != configIds.length) {
      revert AaveEModeHelper__setEModeConfig_arrayDiscrepancy();
    }

    for (uint256 i; i < len;) {
      if (assets[i] != address(0) && debts[i] != address(0)) {
        _eModeConfigIds[assets[i]][debts[i]] = configIds[i];

        emit EmodeConfigSet(assets[i], debts[i], configIds[i]);
      }

      unchecked {
        ++i;
      }
    }
  }
}
