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

    function cancelPosition(address _token, uint256 _position) external;

    ///@notice A user can decide to opt out
    function withdraw(address _token, uint256 _position) external;

     function recordBorrow(address _borrower, bytes32 _positionId, address _debtToken, 
                            address _collateralToken, uint256 _requestedLoan, uint256 _repayAmount, 
                            uint256 _interest) external;

    function updateBorrowRecord(address _user, uint256 _amount, bytes32 _uniqueId) external;

    function receiveRepayment(address borrower, bytes32 uniqueId, uint256 amount) external;             


    function releaseBorrowedTokens(address _token, address _receiver, uint256 _amount) external;

    function getLiquidity(address _token) external view returns (uint256);
}
