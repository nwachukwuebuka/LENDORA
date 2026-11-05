// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import {Script} from "forge-std/Script.sol";
import {PriceFeedOracle} from "../src/PriceFeedOracle.sol";
import {console2} from "forge-std/console2.sol";

contract DeployPriceFeedOracle is Script {
    function run() external {

        address usdcToken = vm.envAddress("USDC_TOKEN");
        address usdcPriceFeed = vm.envAddress("USDC_PRICE_FEED");

        address wethToken = vm.envAddress("WETH_TOKEN");
        address wethPriceFeed = vm.envAddress("WETH_PRICE_FEED");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        PriceFeedOracle oracle = new PriceFeedOracle(usdcToken, usdcPriceFeed, wethToken, wethPriceFeed);
        console2.log("PriceFeedOracle contract address: ", address(oracle));
        vm.stopBroadcast();
    }
}
