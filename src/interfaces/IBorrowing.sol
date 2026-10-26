// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 ***@author Nwachukwu Chkwuebuka
 ***@title Lendora Borrowing Interface
 */
interface IBorrowing {
    function depositCollateral(uint256 _amount, address _token) external;

    function borrow(uint256 _amount, address _borrowToken, address _collateral) external;
    function withdraw(address _token, uint256 _amount) external;

    function repay(address _token, uint256 positionId, uint256 amount) external;

    function liquidate(address _user, uint256 _amount) external;

    function _interestRate(address _token) external view returns (uint256);

    function _interest(uint256 _amount, address _token) external view returns (uint256);

    function getWithdrawableBalance(address _token) external view returns (uint256 amount, uint256 amountInUsd);
}
