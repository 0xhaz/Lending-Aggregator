// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.15;

/**
 * @title FujiOracle
 * @notice Contract that returns and computes prices for Fuji
 * using Chainlink as a standard oracle to view latest price
 */

import {IFujiOracle} from "./interfaces/IFujiOracle.sol";
import {IAggregatorV3} from "./interfaces/chainlink/IAggregatorV3.sol";
import {SystemAccessControl} from "./access/SystemAccessControl.sol";

contract FujiOracle is IFujiOracle, SystemAccessControl {
  ////////////////// CUSTOM ERRORS //////////////////
  error FujiOracle__lengthMismatch();
  error FujiOracle__noZeroAddress();
  error FujiOracle__noPriceFeed();
  error FujiOracle__invalidPriceFeedDecimals(address priceFeed);

  /// @notice Mapping from asset address to its Chainlink price feed address
  mapping(address => address) public usdPriceFeeds;

  ////////////////// CONSTRUCTOR //////////////////
  /**
   * @notice Constructor of a new {FujiOracle}
   * Requirements:
   * - Must provide some initial assets and price feed information
   * - Must check `assets` and `priceFeeds` array match in length
   * - Must ensure `priceFeeds` addresses return feed un USD formatted to 8 decimals
   * @param assets array of assets to be added
   * @param priceFeeds array of price feeds to be added
   */
  constructor(address[] memory assets, address[] memory priceFeeds, address chief_) {
    __SystemAccessControl_init(chief_);

    if (assets.length != priceFeeds.length) {
      revert FujiOracle__lengthMismatch();
    }

    for (uint256 i; i < assets.length; i++) {
      _validatePriceFeedDecimals(priceFeeds[i]);
      usdPriceFeeds[assets[i]] = priceFeeds[i];
    }
  }

  ////////////////// GENERAL FUNCTIONS //////////////////
  /**
   * @notice Sets '_priceFeed' address for an `asset`
   * Requirements:
   * - Must only be called by a timelock
   * - Must emits a {AssetPriceFeedChanged} event
   * - Must ensure `priceFeed` addresses returns feed in USD formatted to 8 decimals
   * @param asset address of the asset
   * @param priceFeed address of the price feed to be set
   */
  function setPriceFeed(address asset, address priceFeed) public onlyTimelock {
    if (priceFeed == address(0)) revert FujiOracle__noZeroAddress();
    _validatePriceFeedDecimals(priceFeed);

    usdPriceFeeds[asset] = priceFeed;

    emit AssetPriceFeedChanged(asset, priceFeed);
  }

  /// @inheritdoc IFujiOracle
  function getPriceOf(
    address currencyAsset,
    address commodityAsset,
    uint8 decimals
  )
    external
    view
    override
    returns (uint256 price)
  {
    price = 10 ** uint256(decimals);

    if (commodityAsset != address(0)) {
      price = price * _getUSDPrice(commodityAsset);
    } else {
      price = price * (10 ** 8);
    }

    if (currencyAsset != address(0)) {
      uint256 currencyAssetPrice = _getUSDPrice(currencyAsset);
      price = currencyAssetPrice == 0 ? 0 : (price / currencyAssetPrice);
    } else {
      price = price / (10 ** 8);
    }
  }

  ////////////////// INTERNAL FUNCTIONS //////////////////

  /**
   * @notice Validates that the price feed returns a value with 8 decimals
   * @param priceFeed address of the price feed to be validated
   *
   * Requirements:
   * - Must check that `priceFeed` returns a value with 8 decimals
   *
   */
  function _validatePriceFeedDecimals(address priceFeed) internal view {
    if (IAggregatorV3(priceFeed).decimals() != 8) {
      revert FujiOracle__invalidPriceFeedDecimals(priceFeed);
    }
  }

  /**
   * @notice Returns the USD price of an `asset`
   * @param asset address of the asset
   * @dev Requirements:
   * - Must check that `asset` is set in usdPriceFeeds, otherwise return 0
   */
  function _getUSDPrice(address asset) internal view returns (uint256 price) {
    if (usdPriceFeeds[asset] == address(0)) revert FujiOracle__noPriceFeed();
    (, int256 latestPrice,,,) = IAggregatorV3(usdPriceFeeds[asset]).latestRoundData();

    price = uint256(latestPrice);
  }
}
