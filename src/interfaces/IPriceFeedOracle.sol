// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


/**
***@author Nwachukwu Chukwuebuka
***@notice Version 1 (lendora-v1.0.0)
***@dev these functions are to be strictly implemented in the extending contract(must be inherited).
*/

interface IPriceFeedOracle{

    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////

    ///@notice Confirms if the token to be deposited is acceptable by the protocol
    ///@param _token The token passed
    function isTokenSupported(address _token) external view returns(bool);

    ///@notice Gets realtime prices of assets that the protocol supports
    ///@dev Returns the token's USD price with 18 decimals.
    ///@param _token The token passed
    function getPriceInUsd(address _token) external view returns(uint256);

    ///@notice Gets value of the asset deposited
    ///@dev Returns a value after the amount of asset is mutilpled by the realtime price
    function calculateTokenWorthInUsd(address _token, uint256 _collateral) external view returns(uint256);

    function getAllSupportedTokens() external view returns (address[] memory);

    function usdWorthToTokenAmount(address _token, uint256 _worth) external view returns (address _token, uint256 _worth);


}