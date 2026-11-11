// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import{MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import{Test} from "forge-std/Test.sol";
import{ERC20Mock} from "../../mocks/ERC20Mock.sol";



contract PriceFeedHandler is Test {

    ///////////////////////////////////////////////////////
    ///    VARIABLES
    ///////////////////////////////////////////////////////
    address private randomToken;
    MockV3Aggregator private ethPriceFeed;
    MockV3Aggregator private usdcPriceFeed;
    
    ERC20Mock private wethToken;
    ERC20Mock private usdcToken;

    
    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////

    constructor(
        MockV3Aggregator _ethPriceFeed,
        MockV3Aggregator _usdcPriceFeed,
        address _wethToken,
        address _usdcToken
    ) {
        ethPriceFeed = _ethPriceFeed;
        usdcPriceFeed = _usdcPriceFeed;
        wethToken = ERC20Mock(_wethToken);
        usdcToken = ERC20Mock(_usdcToken);
    }

    function updateEthPrice(uint96 newPrice) external {
        if (newPrice == 0) return;

        ethPriceFeed.updateAnswer(int256(uint256(newPrice)));
    }

    function updateUsdcPrice(uint96 newPrice) external {
          if (newPrice < 90_000_000 || newPrice > 110_000_000) return;

        usdcPriceFeed.updateAnswer(int256(uint256(newPrice)));
    }



    function setRandomToken(address _token) external {
        if (
            _token == address(0) ||
            _token == address(wethToken) ||
            _token == address(usdcToken)
        ) return;

        randomToken = _token;
    }

    function getRandomToken() external view returns (address) {
        return randomToken;
}
}