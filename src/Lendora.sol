// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import {ILendora} from "./interfaces/ILendora.sol";
import {ILending} from "./interfaces/ILending.sol";
import {IBorrowing} from "./interfaces/IBorrowing.sol";

/**
 ***@author Nwachukwu Chukwuebuka
 ***@title Lendora Defi Protocol
 ***@notice
 ***@dev Manages lending and borrowing of supoorted ERC20 tokens
 */
contract Lendora is ILendora {
    constructor() {}

    // LEND
    function lend(uint256 _amount, address _token) public {}

    function trackLendStatus(address user, address token) external view returns (string memory) {}

    function cancelLend(address _token, uint256 _position) external {}

    function claimInterest(address lender, address token) external {}

    function withdrawAsLender(address _token, uint256 _position, uint256 _amount) external {}

    // BORROW
    function depositCollateral(uint256 _amount, address _token) external {}

    function borrow(address _collateralToken, uint256 _lockCollateralAmount, address _debtToken, uint256 _debtAmount)
        external {}

    function repayDebt(uint256 _positionIndex, uint256 _amount) external {}

    function withdrawCollateral(address _token, uint256 _amount) external {}

    function liquidatePosition(address _user, uint256 _positionIndex, uint256 _amount) external {}

    // INFORMATION
    function getNeutralLenderBalance(address user, address token) external view returns (uint256) {}
    function getPoolLiquidity(address token) external view returns (uint256) {}
    function getLendNeutralBalance(address user, address token) external view returns (uint256) {}
    function getLendPosition(address user, address token) external view returns (LendingPosition[] memory) {}

    function getBorrowPosition(address user) external view returns (BorrowStatus[] memory) {}
    function getInterest(uint256 _amount, address _token) external view returns (uint256) {}
    function getInterestRate(address _token) external view returns (uint256) {}
}
