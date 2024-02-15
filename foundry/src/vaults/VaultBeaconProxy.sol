// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IChief} from "../interfaces/IChief.sol";

contract VaultBeaconProxy is BeaconProxy {
  /////////////////////////////// CUSTOM ERROR ///////////////////////////////
  error VaultBeaconProxy__onlyTimelock_callerIsNotTimelock();

  /////////////////////////////// STATE VARS ///////////////////////////////
  IChief public chief;

  /////////////////////////////// MODIFIERS ///////////////////////////////
  /**
   * @dev Modifier that check msg.sender is the defined timelock in {chief} contract
   */
  modifier onlyTimelock() {
    if (msg.sender != chief.timelock()) revert VaultBeaconProxy__onlyTimelock_callerIsNotTimelock();
    _;
  }

  /////////////////////////////// CONSTRUCTOR ///////////////////////////////
  constructor(address beacon, bytes memory data, address chief_) BeaconProxy(beacon, data) {
    chief = IChief(chief_);
  }

  /////////////////////////////// EXTERNAL FUNCTIONS ///////////////////////////////
  /**
   * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon
   * it does not upgrade the imp'ementation contained in the beacon (see {UpgradeableBeacon-_setImplementation}).
   *
   * Emits a {BeaconUpgraded} event.
   */
  function upgradeBeaconAndCall(
    address newBeacon,
    bytes memory data,
    bool forceCall
  )
    external
    onlyTimelock
  {
    _upgradeToAndCall(newBeacon, data, forceCall);
  }
}
