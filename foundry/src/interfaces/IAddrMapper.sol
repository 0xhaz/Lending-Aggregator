// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IAddrMapper
 * @notice Defines interface for {AddrMapper} mapping operations
 */

interface IAddrMapper {
  /**
   * @notice Log a change in address mapping
   */
  event MappingChanged(address[] keyAddress, address mappedAddress);

  /**
   * @notice Returns the address of the underlying token associated with the `keyAddr`
   * for the providerName protocol
   * @param providerName string name of the provider
   * @param keyAddr address of the token associated with the underlying token
   */
  function getAddressMapping(
    string memory providerName,
    address keyAddr
  )
    external
    view
    returns (address returnedAddr);

  /**
   * @notice Returns the address of the underlying token associated with the `keyAddr1`
   * and `keyAddr2` tokens
   * @param providerName string name of the provider
   * @param keyAddr1 address of the token (provided as collateral) associated with
   * the underlying token
   * @param keyAddr2 address of the token (to be borrowed) associated with the
   * underlying token
   */
  function getAddressNestedMapping(
    string memory providerName,
    address keyAddr1,
    address keyAddr2
  )
    external
    view
    returns (address returnedAddr);

  /**
   * @notice Sets the mapping of the underlying `returnedAddr` token associated with the `providerName` and the token `keyAddr`
   * @param providerName string name of the provider
   * @param keyAddr address of the token associated with the underlying token
   * @param returnedAddr address of the underlying token to be returned by the {IAddrMapper-getAddressMapping} function
   */
  function setMapping(string memory providerName, address keyAddr, address returnedAddr) external;

  /**
   * @notice Sets the mapping associated with the `providerName` and both `keyAddr1` (collateral) and `keyAddr2` (borrowed) tokens
   * @param providerName string name of the provider
   * @param keyAddr1 address of the token (provided as collateral) associated with the underlying token
   * @param keyAddr2 address of the token (to be borrowed) associated with the underlying token
   * @param returnedAddr address of the underlying token to be returned by the {IAddrMapper-getAddressNestedMapping} function
   */
  function setNestedMapping(
    string memory providerName,
    address keyAddr1,
    address keyAddr2,
    address returnedAddr
  )
    external;
}
