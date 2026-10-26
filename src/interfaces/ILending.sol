// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 ***@author Nwachukwu Chkwuebuka
 ***@title Lendora Lending Interface
 */

interface ILending {
    ///@notice Lending to the Lendora token pool
    /// it involves a particular period of time
    function lend(uint256 _amount, address _token) external;

    ///@notice A user can decide to opt out
    function withdraw(address _token, uint256 _position) external;

    function releaseBorrowedTokens(address _token, address _receiver, uint256 _amount) external;

    function getLiquidity(address _token) external view returns (uint256);
}
