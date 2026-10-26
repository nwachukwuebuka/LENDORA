// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import {IPriceFeedOracle} from "./interfaces/IPriceFeedOracle.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 ***@author Nwachukwu Chukwuebuka
 ***@title Lendora Price Feed
 ***@notice Contract implemetation of the price feed interface (IPriceFeedOracle.sol)
 */

contract PriceFeedOracle is IPriceFeedOracle {
    ///////////////////////////////////////////////////////
    ///    ERRORS
    ///////////////////////////////////////////////////////
    error PriceFeedOracle__InvalidAddress();
    error PriceFeedOracle__TokenNotSupported();
    error PriceFeedOracle__InvalidPriceFeed();
    error PriceFeedOracle__InvalidTimestamp();
    error PriceFeedOracle__StalePrice();

    ///////////////////////////////////////////////////////
    ///    VARAIBLES
    ///////////////////////////////////////////////////////
    uint256 private constant PRICE_MAX_AGE = 1 hours;
    mapping(address token => address priceFeed) private tokenPack;
    address[] private supportedTokens;

    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////

    ///@notice Addresses for both the priceFeed and tokenContract must valid
    ///@dev contract addresses must be valid deployed contracts
    ///@dev values are directly set into mapping(tokenPack), tokenAddress => priceFeed
    ///
    constructor(address wbtcToken, address wbtcPriceFeed, address wethToken, address wethPriceFeed) {
        if (
            wbtcToken == address(0) || wbtcPriceFeed == address(0) || wethToken == address(0)
                || wethPriceFeed == address(0) || wbtcToken == wethToken
        ) {
            revert PriceFeedOracle__InvalidAddress();
        }

        if (
            wbtcToken.code.length == 0 || wethToken.code.length == 0 || wbtcPriceFeed.code.length == 0
                || wethPriceFeed.code.length == 0
        ) {
            revert PriceFeedOracle__InvalidAddress();
        }
        tokenPack[wbtcToken] = wbtcPriceFeed;
        tokenPack[wethToken] = wethPriceFeed;
        supportedTokens.push(wbtcToken);
        supportedTokens.push(wethToken);
    }

    ///@notice Checks for token collaterals supported by the protocol
    ///@dev supported token addresses are stored in the mapping: tokenPack
    function isTokenSupported(address _token) public view override returns (bool) {
        return tokenPack[_token] != address(0);
    }

    ///@notice Gets the price of supported token in USD
    ///@dev 3 safety measures regarding the answer(price):
    ///                  1. price can't be less than or equal to zero
    ///                  2. block.timestamp of the oracle must not be zero and also there's no way the upatedAt will be greater than the current time stamp
    ///                  3. check for stale price i.e price should be frequently updated, anything more than 30 minutes is stale

    ///@dev  Chainlink returns prices in 8 decimals by default, but extra steps are taken incase of future code refactor:
    ///                                         checks if decimals is more, less or returns value exactly in 18 decimals
    function getPriceInUsd(address _token) public view override returns (uint256) {
        if (!isTokenSupported(_token)) {
            revert PriceFeedOracle__TokenNotSupported();
        }

        address feedAddress = tokenPack[_token];
        // AggregatorV3Interface priceFeed =  AggregatorV3Interface(feedAddress);

        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(feedAddress).latestRoundData();

        if (answer <= 0) {
            revert PriceFeedOracle__InvalidPriceFeed();
        }
        if (updatedAt == 0 || updatedAt > block.timestamp) {
            revert PriceFeedOracle__InvalidTimestamp();
        }
        if (block.timestamp - updatedAt > PRICE_MAX_AGE) {
            revert PriceFeedOracle__StalePrice();
        }

        uint256 price = uint256(answer);
        uint8 feedDecimals = AggregatorV3Interface(feedAddress).decimals();

        if (feedDecimals < 18) {
            return price * (10 ** (18 - feedDecimals));
        }else if (feedDecimals > 18) {
            return price / (10 ** (feedDecimals - 18));
        }else {
            return price;
        }
    }

    ///@notice Calculates the total worth of the amount of  a particular token
    ///@dev The decimal representation of each token are highly put into consideration
    ///@param _token address to a paricular supported token
    ///@param _amount the amount of the token
    function calculateTokenWorthInUsd(address _token, uint256 _amount) external view override returns (uint256) {
        // worth = (amount * usdvalue) / 1e18
        uint256 price = getPriceInUsd(_token);
        uint8 tokenDecimals = IERC20Metadata(_token).decimals();
        uint256 tokenPrecision = 10 ** uint256(tokenDecimals);

        return Math.mulDiv(price, _amount, tokenPrecision);
    }

    function usdWorthToTokenAmount(address _token, uint256 _worth) external view returns (uint256) {
        // amount = worth / price
        uint8 tokenDecimals = IERC20Metadata(_token).decimals();
        uint256 tokenPrecision = 10 ** uint256(tokenDecimals);
        uint256 amount = (_worth * tokenPrecision) / getPriceInUsd(_token);

        return amount;
    }

    ///////////////////////////////////////////////////////
    ///    GETTERS
    ///////////////////////////////////////////////////////
    function getAllSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }
}
