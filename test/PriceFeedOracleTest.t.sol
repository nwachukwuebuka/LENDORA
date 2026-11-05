// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import{Test} from "forge-std/Test.sol";
import{PriceFeedOracle} from "../src/PriceFeedOracle.sol";
import{ERC20Mock} from "./mocks/ERC20Mock.sol";
import{MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract PriceFeedOracleTest is Test{

    ///////////////////////////////////////////////////////
    ///    VARIABLES
    ///////////////////////////////////////////////////////
    PriceFeedOracle private oracle;
    ERC20Mock private wethToken;
    ERC20Mock private usdcToken;
    MockV3Aggregator private ethPriceFeed;
    MockV3Aggregator private usdcPriceFeed;



    uint8 private constant PRICEFEED_DECIMALS = 8;

    uint256 private constant ETH_DECIMALS = 18;
    int256 private constant ETH_PRICE = 2000e8;

    uint256 private constant USDC_DECIMALS = 6;
    int256 private constant USDC_PRICE = 1e8;

    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////
    function setUp() external{

        wethToken = new ERC20Mock();
        usdcToken = new ERC20Mock();
        ethPriceFeed = new MockV3Aggregator(PRICEFEED_DECIMALS, ETH_PRICE);
        usdcPriceFeed = new MockV3Aggregator(PRICEFEED_DECIMALS, USDC_PRICE);

        oracle = new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(wethToken), address(ethPriceFeed));

    }


    

}