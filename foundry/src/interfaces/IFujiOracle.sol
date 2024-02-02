// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title IFujiOracle
 * @notice Defines the interface of the {FujiOracle} contract
 */

interface IFujiOracle {
  /**
   * @dev Emitted when a change in price address is done for an `asset`
   * @param asset address of the asset
   * @param newPriceFeedAddress that returns USD price from Chainlink
   */
  event AssetPriceFeedChanged(address asset, address newPriceFeedAddress);

  /**
   * @notice Returns the exchange rate between two assets, with oracle price given in specified `decimals`
   * @param currencyAsset to be used, zero address for USD
   * @param commodityAsset to be used, zero address for USD
   * @param decimals of the desired price output
   * @dev price format is defined as: (amount of currencyAsset per unit of commodityAsset Exchange Rate)
   * Requirements:
   * - Must check that both `currencyAsset` and `commodityAsset` are set in
   * usdPriceFeeds, otherwise return 0
   */
  function getPriceOf(
    address currencyAsset,
    address commodityAsset,
    uint8 decimals
  )
    external
    view
    returns (uint256);
}
