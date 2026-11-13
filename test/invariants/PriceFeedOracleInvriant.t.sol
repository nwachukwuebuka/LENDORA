// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {PriceFeedOracle} from "../../src/PriceFeedOracle.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import{PriceFeedHandler} from "./handlers/PriceFeedHandler.sol";
import{Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import{IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";


contract PriceFeedOracleInvariants is StdInvariant, Test{

    ///////////////////////////////////////////////////////
    ///    VARIABLES
    ///////////////////////////////////////////////////////
    uint256 private constant PRECISION = 1e18;
    PriceFeedOracle private oracle;

    ERC20Mock private wethToken;
    ERC20Mock private usdcToken;
    MockV3Aggregator private ethPriceFeed;
    MockV3Aggregator private usdcPriceFeed;
    PriceFeedHandler private handler;


    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////

    function setUp() public {
        wethToken = new ERC20Mock("WethToken", "WETH", 18);
        usdcToken = new ERC20Mock("UsdcToken", "USDC", 6);


        ethPriceFeed = new MockV3Aggregator(
            8,
            2000e8
        );

        usdcPriceFeed = new MockV3Aggregator(
            8,
            1e8
        );

        oracle = new PriceFeedOracle(
            address(usdcToken),
            address(usdcPriceFeed),
            address(wethToken),
            address(ethPriceFeed)
        );

        handler = new PriceFeedHandler(ethPriceFeed, usdcPriceFeed, address(wethToken), address(usdcToken));
        targetContract(address(handler));
    }



    function invariant_UnsupportedTokensAreNotSupported() public view {
        address randomToken = handler.getRandomToken();

        if (randomToken != address(0)) {
            assertFalse(oracle.isTokenSupported(randomToken));
        }
    }


    function invariant_EthPriceIsCorrectlyNormalized() public view {
        (, int256 answer,,,) = ethPriceFeed.latestRoundData();

        uint256 expectedPrice = uint256(answer) * 1e10;

        assertEq(
            oracle.getPriceInUsd(address(wethToken)),
            expectedPrice
        );
    }

    function invariant_UsdcPriceIsCorrectlyNormalized() public view {
        (, int256 answer,,,) = usdcPriceFeed.latestRoundData();

        uint256 expectedPrice = uint256(answer) * 1e10;

        assertEq(
            oracle.getPriceInUsd(address(usdcToken)),
            expectedPrice
        );
    }

    function invariant_EthTokenValueIsCorrect() public view {
        (, int256 answer,,,) = ethPriceFeed.latestRoundData();

        uint256 expectedPrice = uint256(answer) * 1e10;

        uint256 amount = 2 ether;

        uint256 expectedValue = (expectedPrice * amount) / 1e18;

        assertEq(
            oracle.calculateTokenWorthInUsd(address(wethToken), amount),
            expectedValue
        );
    }

    function invariant_UsdcTokenValueIsCorrect() public view{
       (,int256 price,,,) =  usdcPriceFeed.latestRoundData();
       console2.log("Price raw: ", price);
       uint256 normalisedPrice = oracle.getPriceInUsd(address(usdcToken));
       uint256 tokenAmount = 3e18;

       uint256 expected = Math.mulDiv(tokenAmount, normalisedPrice, PRECISION);

        assertEq(
            oracle.calculateTokenWorthInUsd(address(usdcToken), tokenAmount),
            expected
        );

    }

    function invariant_UsdValueToUsdc() public view{

        uint256 usdValue = 100e18;
        uint256 price = oracle.getPriceInUsd(address(usdcToken));
        uint256 expected = Math.mulDiv(usdValue, PRECISION, price);


        assertEq(
            oracle.usdWorthToTokenAmount(address(usdcToken), usdValue), 
            expected
        );

    }
    function invariant_UsdValueToEth() public view{

        uint256 usdValue = 100e18;
        uint256 price = oracle.getPriceInUsd(address(wethToken));
        uint256 tokenPrecision = 10 ** uint256(
            IERC20Metadata(address(wethToken)).decimals()
        );

        uint256 expected = Math.mulDiv(
            usdValue,
            tokenPrecision,
            price
        );
    

        assertEq(
            oracle.usdWorthToTokenAmount(address(wethToken), usdValue), 
            expected
        );

    }
}