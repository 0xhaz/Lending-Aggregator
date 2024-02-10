// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IComptroller
 * @notice Interface for the Compound Comptroller
 */

interface IComptroller {
  function enterMarkets(address[] calldata) external returns (uint256[] memory);

  function exitMarket(address cTokenAddress) external returns (uint256);

  function claimComp(address holder) external;
}
