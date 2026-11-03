// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


interface ILendora{

    struct LendingPosition {
        uint256 amount;
        bytes32 id;
        uint256 startTime;
    }

    struct BorrowStatus {
        bytes32 uniqueId;
        address collateralToken;
        uint256 lockedCollateralAmount;
        address debtToken;
        uint256 debtAmount;
        uint256 interestAmount;
        uint256 startTime;
        bool active;
    }


    // LEND
    function lend(uint256 _amount, address _token) external;

    function trackLendStatus(address user, address token) external view returns(string memory);

    function cancelLend(address _token, uint256 _position) external;

    function claimInterest(address lender, address token) external;
 
    function withdrawAsLender(address _token, uint256 _position, uint256 _amount) external;



    // BORROW
    function depositCollateral(uint256 _amount, address _token) external;

    function borrow(address _collateralToken, uint256 _lockCollateralAmount, address _debtToken, uint256 _debtAmount) external;

    function repayDebt(uint256 _positionIndex, uint256 _amount) external;

    function withdrawCollateral(address _token, uint256 _amount) external;


    function  liquidatePosition(address _user, uint256 _positionIndex, uint256 _amount) external;



    // INFORMATION
    function getNeutralLenderBalance(address user, address token) external view returns(uint256);
    function getPoolLiquidity(address token) external view returns(uint256);
    function getLendNeutralBalance(address user, address token) external view returns(uint256);
    function getLendPosition(address user, address token) external view returns(LendingPosition[] memory);


    function getBorrowPosition(address user) external view returns (BorrowStatus[] memory);
    function getInterest(uint256 _amount, address _token) external view returns(uint256);
    function getInterestRate(address _token) external view returns (uint256) ;


}