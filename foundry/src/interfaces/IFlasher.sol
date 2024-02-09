// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IFlasher
 * @notice Defines the interface for all flashloan providers
 */

interface IFlasher {
  /**
   * @notice Initiates a flashloan from the pool provider
   * @param asset The address of the asset to be flashloaned
   * @param amount The amount of the asset to be flashloaned
   * @param requestor The address of the account initiating the flashloan
   * @param requestorCalldata encoded args with selector that will be OPCODE-CALLed to the requestor
   * @dev To encode `param` see below:
   * • solidity:
   *   > abi.encodeWithSelector(contract.transferFrom.selector, from, to, amount);
   * • ethersJS:
   *   > contract.interface.encodeFunctionData("transferFrom", [from, to, amount]);
   * • foundry cast:
   *   > cast calldata "transferFrom(address,address,uint256)" from, to, amount
   *
   * Requirements:
   * - MUST implement `_checkAndSetEntryPoint()`
   */

  function initiateFlashloan(
    address asset,
    uint256 amount,
    address requestor,
    bytes memory requestorCalldata
  )
    external;

  /**
   * @notice Returns the address from which flashloan for `asset` is sourced
   * @param asset intended to be flashloaned
   * @dev Override at flashloan provider implementation as per requirement
   * Some protocol implementations source flashloans from different contracts
   * depending on the asset being flashloaned
   */
  function getFlashloanSourceAddr(address asset) external view returns (address callAddr);

  /**
   * @notice Returns the expected flashloan fee for `amount`
   * of this flashloan provider
   * @param asset to be flashloaned
   * @param amount of flashloan
   */
  function computeFlashloanFee(address asset, uint256 amount) external view returns (uint256 fee);
}
