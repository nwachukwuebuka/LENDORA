// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private immutable decimalsValue;
    int256 private answer;
    uint256 updatedAt = block.timestamp;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimalsValue = _decimals;
        answer = _initialAnswer;
    }

    function decimals() external view override returns (uint8) {
        return decimalsValue;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, block.timestamp, updatedAt, 1);
    }

    function updateAnswer(int256 newAnswer) external {
        answer = newAnswer;
        updatedAt = block.timestamp;
    }

    function updateTimestamp(uint256 newTimestamp) external {
        updatedAt = newTimestamp;
    }
}
