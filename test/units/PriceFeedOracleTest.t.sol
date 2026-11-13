// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import {Test, console2} from "forge-std/Test.sol";
import {PriceFeedOracle} from "src/PriceFeedOracle.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract PriceFeedOracleTest is Test {
    ///////////////////////////////////////////////////////
    ///    VARIABLES
    ///////////////////////////////////////////////////////
    PriceFeedOracle private oracle;
    ERC20Mock private wethToken;
    ERC20Mock private usdcToken;
    MockV3Aggregator private ethPriceFeed;
    MockV3Aggregator private usdcPriceFeed;

    uint8 private constant PRICEFEED_DECIMALS = 8;
    int256 private constant ETH_PRICE = 2000e8;
    int256 private constant USDC_PRICE = 1e8;

    uint256 private constant ETH_DECIMALS = 18;
    uint256 private USER_TOKEN_USD_WORTH = 2000e18;

    uint256 private constant USDC_DECIMALS = 6;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant TEST_TOKEN = 2e18;

    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////
    function setUp() public {
        wethToken = new ERC20Mock("WethToken", "WETH", 18);
        usdcToken = new ERC20Mock("UsdcToken", "USDC", 6);

        ethPriceFeed = new MockV3Aggregator(PRICEFEED_DECIMALS, ETH_PRICE);
        usdcPriceFeed = new MockV3Aggregator(PRICEFEED_DECIMALS, USDC_PRICE);

        oracle =
            new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(wethToken), address(ethPriceFeed));
    }

    function testIfUsdcTokenIsZero() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);

        new PriceFeedOracle(address(0), address(usdcPriceFeed), address(wethToken), address(ethPriceFeed));
    }

    function testIfUsdcPriceFeedIsZero() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);

        new PriceFeedOracle(address(usdcToken), address(0), address(wethToken), address(ethPriceFeed));
    }

    function testIfWethTokenIsZero() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);

        new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(0), address(ethPriceFeed));
    }

    function testIfWethFeedAddressesIsZero() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);
        oracle = new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(wethToken), address(0));
    }

    function testIfTokenAddressesAreSame() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);

        new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(usdcToken), address(ethPriceFeed));
    }

    function testIfTokenSupported() public {
        bool supported = oracle.isTokenSupported(address(wethToken));

        assertTrue(supported);
    }

    function testIfTokenIsNotSupported() public {
        assertFalse(oracle.isTokenSupported(address(0x1234)));
    }

    function testWethFeedHasNoCode() public {
        address feedAddress = address(0x1234);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);
        oracle = new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(wethToken), feedAddress);
    }

    function testIfUsdcTokenHasNoCode() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);

        new PriceFeedOracle(address(0x1234), address(usdcPriceFeed), address(wethToken), address(ethPriceFeed));
    }

    function testIfUsdcFeedHasNoCode() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);

        new PriceFeedOracle(address(usdcToken), address(0x1234), address(wethToken), address(ethPriceFeed));
    }

    function testIfWethTokenHasNoCode() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector);

        new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(0x1234), address(ethPriceFeed));
    }

    function testGetTokenUsdValue() public {
        uint256 round = TEST_TOKEN * uint256(ETH_PRICE) * 10 ** (ETH_DECIMALS - PRICEFEED_DECIMALS);
        uint256 expect = 4000e18;
        uint256 expectedResult = Math.mulDiv(TEST_TOKEN, round, PRECISION);

        uint256 amount = oracle.calculateTokenWorthInUsd(address(wethToken), TEST_TOKEN);

        // assertEq(expect, expectedResult);
        assertEq(amount, expect);
    }

    function testTokenIsSupportedForPrice() public {
        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__TokenNotSupported.selector);
        oracle.getPriceInUsd(address(0));
    }

    function testWhenFeedDecimalIsGreaterThan18() public {
        MockV3Aggregator newFeed = new MockV3Aggregator(20, 2000e20);

        PriceFeedOracle newOracle =
            new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(wethToken), address(newFeed));

        uint256 amount = newOracle.getPriceInUsd(address(wethToken));

        assertEq(amount, 2000e18);
    }

    function testWhenFeedDecimalIs18() public {
        MockV3Aggregator newFeed = new MockV3Aggregator(18, 2000e18);

        PriceFeedOracle newOracle =
            new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(wethToken), address(newFeed));

        uint256 amount = newOracle.getPriceInUsd(address(wethToken));

        assertEq(amount, 2000e18);
    }

    function testIfPriceIsZero() public {
        ethPriceFeed.updateAnswer(0);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidPriceFeed.selector);

        oracle.calculateTokenWorthInUsd(address(wethToken), TEST_TOKEN);
    }

    function testIfPriceIsNegative() public {
        ethPriceFeed.updateAnswer(-3000);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidPriceFeed.selector);
        oracle.getPriceInUsd(address(wethToken));
    }

    function testPriceUpdateRate() public {
        ethPriceFeed.updateTimestamp(block.timestamp + 1 hours);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidTimestamp.selector);
        oracle.calculateTokenWorthInUsd(address(wethToken), TEST_TOKEN);

        ethPriceFeed.updateTimestamp(0);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidTimestamp.selector);
        oracle.calculateTokenWorthInUsd(address(wethToken), TEST_TOKEN);
    }

    function testPriceMaxAge() public {
        vm.warp(2 hours);
        console2.log("Blockstamp: ", block.timestamp);
        ethPriceFeed.updateTimestamp(30 minutes);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__StalePrice.selector);
        oracle.calculateTokenWorthInUsd(address(wethToken), TEST_TOKEN);
    }

    function testGetTokenAmount() public {
        ethPriceFeed = new MockV3Aggregator(PRICEFEED_DECIMALS, ETH_PRICE);
        uint256 expected = 1e18;

        uint256 amount = oracle.usdWorthToTokenAmount(address(wethToken), uint256(USER_TOKEN_USD_WORTH));

        assertEq(amount, expected);
    }

    function testGetSupportedToken() public {
        address[] memory tokens = oracle.getAllSupportedTokens();

        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(usdcToken));
        assertEq(tokens[1], address(wethToken));
    }




    ///////////////////////////////////////////////////////
    ///    FUZZ TESTS
    ///////////////////////////////////////////////////////

    function testFuzzGetTokenUsdValue(uint256 tokenAmount) public {
        vm.assume(tokenAmount <= 1000e18);
    
        uint256 expected = Math.mulDiv(
            tokenAmount,
            2000e18,
            1e18
        );
        

        uint256 amount = oracle.calculateTokenWorthInUsd(address(wethToken), tokenAmount);
        console2.log("tokenAmount:", tokenAmount);   
        assertEq(expected, amount);
    }

    function testFuzzGetTokenAmount(uint256 usdAmount) public {
        vm.assume(usdAmount > 0 && usdAmount <= 1000e18);
        
        uint256 expected = (usdAmount * 1e18) / 2000e18;

        uint256 amount = oracle.usdWorthToTokenAmount(address(wethToken), usdAmount);

        assertEq(amount, expected);
    }

    function testFuzzPriceUpdateRate(uint256 time) public {
        vm.assume(time > 0 && time <= type(uint256).max - 1);
        ethPriceFeed.updateTimestamp(block.timestamp + time);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidTimestamp.selector);
        oracle.calculateTokenWorthInUsd(address(wethToken), TEST_TOKEN);

        ethPriceFeed.updateTimestamp(0);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidTimestamp.selector);
        oracle.calculateTokenWorthInUsd(address(wethToken), TEST_TOKEN);
    }

    function testFuzzUnsupportedToken(address token) public {
        vm.assume(token != address(wethToken));
        vm.assume(token != address(usdcToken));

        vm.expectRevert(
            PriceFeedOracle.PriceFeedOracle__TokenNotSupported.selector
        );

        oracle.calculateTokenWorthInUsd(token, 1 ether);
    }
    
    function testFuzzIfPriceIsNegative(int256 value) public {
        vm.assume(value < 0);
        ethPriceFeed.updateAnswer(value);

        vm.expectRevert(PriceFeedOracle.PriceFeedOracle__InvalidPriceFeed.selector);
        oracle.getPriceInUsd(address(wethToken));
    }
    function testFuzzWhenFeedDecimalIsGreaterThan18(uint8 decimal) public {
        vm.assume(decimal > 18 && decimal <= 73);
        MockV3Aggregator newFeed = new MockV3Aggregator(decimal, int256(2000 * 10**decimal));

        PriceFeedOracle newOracle =
            new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(wethToken), address(newFeed));

        uint256 amount = newOracle.getPriceInUsd(address(wethToken));

        assertEq(amount, 2000e18);
    }

    function testFuzzTokenAddressHasNoCode(address token) public {
        vm.assume(token.code.length == 0);
        vm.assume(token != address(0));

        vm.expectRevert(
            PriceFeedOracle.PriceFeedOracle__InvalidAddress.selector
        );

        new PriceFeedOracle(
            token,
            address(usdcPriceFeed),
            address(wethToken),
            address(ethPriceFeed)
        );
    }
}
