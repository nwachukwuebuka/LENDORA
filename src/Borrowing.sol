// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ILending} from "./interfaces/ILending.sol";
import {IPriceFeedOracle} from "./interfaces/IPriceFeedOracle.sol";
import {IBorrowing} from "./interfaces/IBorrowing.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 ***@author Nwachukwu Chukwuebuka
 ***@title Lendora Borrowing System
 *
 */

contract Borrowing is ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///////////////////////////////////////////////////////
    ///    ERRORS
    ///////////////////////////////////////////////////////
    error Borrowing__AmountCantBeZero();
    error Borrowing__NotSupportedToken();
    error Borrowing__LessThanMinimumDeposit();
    error Borrowing__CantBeSameToken();
    error Borrowing__LessThanMinimumCollateralWorth();
    error Borrowing__CollateralMustBeTwiceAsDebt();
    error Borrowing__CantBorrowMoreThanLimit();
    error Borrowing__PositionCleared();
    error Borrowing__LessThanDebtAmount();
    error Borrowing__NoCurrentCollateral();
    error Borrowing__InvalidPosition();
    error Borrowing__LiquidationOutOfBound();
    error Borrowing__IncorrectRepaymentAmount();
    error Borrowing__NotEnoughWithdrawableBalance();
    error Borrowing__UserNotLiquidatable();
    error Borrowing__InvalidInterestRate();
    error Borrowing__MinimumCollateralNotMet();
    error Lending__InsufficientBalance();
    error Lending__InvalidAddressInput();

    ///////////////////////////////////////////////////////
    ///    CUSTOM VARIABLES
    ///////////////////////////////////////////////////////
    struct BorrowStatus {
        bytes32 uniqueId;
        address collateralToken;
        uint256 lockedCollateralAmount;
        address debtToken;
        uint256 debtAmount;
        uint256 totalDebt;
        uint256 interestAmount;
        uint256 startTime;
        bool active;
    }

    ///////////////////////////////////////////////////////
    ///    VARAIBLES
    ///////////////////////////////////////////////////////
    uint256 private constant PRECISION = 1e18;
    uint256 private constant PERCENTAGE_PRECISION = 100;
    uint256 private constant LTV_PERCENTAGE = 50;
    uint256 private LIQUIDATION_THRESHOLD = 80;
    uint256 private constant LIQUIDATION_BONUS = 5;
    uint256 private minDeposit = 100e18; // $100
    uint256 public firstInterestRate = 2;
    uint256 public secondInterestRate = 5;
    uint256 public thirdInterestRate = 10;
    uint256 private firstQuotaPercent = 30;
    uint256 private secondQuotaPercent = 75;
    uint256 private idPosition;
    mapping(address _token => uint256 _amount) private interestHistory;

    // collateral
    mapping(address _user => mapping(address _token => uint256 _amount)) private collateral;

    // debt
    mapping(address _user => BorrowStatus[]) public debtPosition;
    mapping(address _user => BorrowStatus[]) public debtHistory;
    mapping(address _token => uint256 _amount) public protocolDebt;
    mapping(address token => uint256 number) private boxCounter;

    address[] private supportedTokens;

    ILending private lend;
    IPriceFeedOracle private oracle;

    ///////////////////////////////////////////////////////
    ///    MODIFIERS
    ///////////////////////////////////////////////////////
    modifier zeroCheck(uint256 _amount) {
        if (_amount == 0) {
            revert Borrowing__AmountCantBeZero();
        }
        _;
    }

    modifier oneTokenSupport(address _tokenOne) {
        bool supported;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (_tokenOne == supportedTokens[i]) {
                supported = true;
                break;
            }
        }
        if (!supported) {
            revert Borrowing__NotSupportedToken();
        }
        _;
    }

    modifier twoTokensSupport(address _tokenOne, address _tokenSupportTwo) {
        bool supportedOne;
        bool supportedTwo;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (_tokenOne == supportedTokens[i]) {
                supportedOne = true;
            }

            if (_tokenSupportTwo == supportedTokens[i]) {
                supportedTwo = true;
            }

            if (supportedOne && supportedTwo) {
                break;
            }
        }

        if (!supportedOne || !supportedTwo) {
            revert Borrowing__NotSupportedToken();
        }

        _;
    }

    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////

    constructor(address _lendingContract, address _priceOracle) {
        if (_lendingContract == address(0) || _priceOracle == address(0)) {
            revert Lending__InvalidAddressInput();
        }
        lend = ILending(_lendingContract);
        oracle = IPriceFeedOracle(_priceOracle);

        supportedTokens = oracle.getAllSupportedTokens();
    }

    function depositCollateral(uint256 _amount, address _token)
        external
        nonReentrant
        zeroCheck(_amount)
        oneTokenSupport(_token)
    {
        // checks
        uint256 collateralUsdWorth = oracle.calculateTokenWorthInUsd(_token, _amount);
        if (collateralUsdWorth < minDeposit) {
            revert Borrowing__LessThanMinimumDeposit();
        }

        // effects
        collateral[msg.sender][_token] += _amount;

        // interactions
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function borrow(address _collateralToken, uint256 _lockCollateralAmount, address _debtToken, uint256 _debtAmount)
        external
        nonReentrant
        zeroCheck(_debtAmount)
        twoTokensSupport(_collateralToken, _debtToken)
    {
        uint256 userCollateralViaSingleToken = collateral[msg.sender][_collateralToken];
        uint256 lockCollateralUsdWorth = oracle.calculateTokenWorthInUsd(_collateralToken, _lockCollateralAmount);
        uint256 borrowLimit = (lockCollateralUsdWorth * LTV_PERCENTAGE) / PERCENTAGE_PRECISION;
        uint256 interest = _interest(_debtAmount, _debtToken);
        uint256 totalLoan = interest + _debtAmount;
        uint256 boxNumber = ++boxCounter[_debtToken];
        bytes32 hashedId = lend.getBoxId(_debtToken, boxNumber);
        uint256 totalLoanUsdWorth = oracle.calculateTokenWorthInUsd(_debtToken, totalLoan);
        uint256 collateralUsdWorth = oracle.calculateTokenWorthInUsd(_collateralToken, userCollateralViaSingleToken);
        uint256 debtUsdWorth = oracle.calculateTokenWorthInUsd(_debtToken, _debtAmount);

        // checks
        if (_lockCollateralAmount > collateral[msg.sender][_collateralToken]) {
            revert Borrowing__NoCurrentCollateral();
        }

        if (lockCollateralUsdWorth < minDeposit) {
            revert Borrowing__MinimumCollateralNotMet();
        }

        if (_debtToken == _collateralToken) {
            revert Borrowing__CantBeSameToken();
        }
        if (collateralUsdWorth < minDeposit) {
            revert Borrowing__LessThanMinimumCollateralWorth();
        }

        if (!(debtUsdWorth * 2 <= lockCollateralUsdWorth)) {
            revert Borrowing__CollateralMustBeTwiceAsDebt();
        }

        if (totalLoanUsdWorth > borrowLimit) {
            revert Borrowing__CantBorrowMoreThanLimit();
        }

        debtPosition[msg.sender].push(
            BorrowStatus({
                uniqueId: hashedId,
                collateralToken: _collateralToken,
                lockedCollateralAmount: _lockCollateralAmount,
                debtToken: _debtToken,
                debtAmount: _debtAmount,
                totalDebt: totalLoan,
                interestAmount: interest,
                startTime: block.timestamp,
                active: true
            })
        );
        debtHistory[msg.sender].push(
            BorrowStatus({
                uniqueId: hashedId,
                collateralToken: _collateralToken,
                lockedCollateralAmount: _lockCollateralAmount,
                debtToken: _debtToken,
                debtAmount: _debtAmount,
                totalDebt: totalLoan,
                interestAmount: interest,
                startTime: block.timestamp,
                active: true
            })
        );

        // effects
        lend.recordBorrow(msg.sender, hashedId, _debtToken, _collateralToken, _debtAmount, totalLoan, interest);

        collateral[msg.sender][_collateralToken] -= _lockCollateralAmount;
        protocolDebt[_debtToken] += _debtAmount;

        // interactions
        lend.releaseBorrowedTokens(_debtToken, msg.sender, _debtAmount);
    }

    function clearPosition(uint256 _positionIndex, uint256 _amount) external nonReentrant zeroCheck(_amount) {
        BorrowStatus[] storage position = debtPosition[msg.sender];

        if (_positionIndex >= position.length) {
            revert Borrowing__InvalidPosition();
        }

        // checks

        if (position[_positionIndex].debtAmount == 0) {
            revert Borrowing__PositionCleared();
        }

        if (_amount != position[_positionIndex].debtAmount) {
            revert Borrowing__IncorrectRepaymentAmount();
        }

        // effects
        address collateralToken = position[_positionIndex].collateralToken;
        uint256 lockedCollateral = position[_positionIndex].lockedCollateralAmount;
        bytes32 uniqueId = position[_positionIndex].uniqueId;
        uint256 repaymentAmount = position[_positionIndex].totalDebt;

        collateral[msg.sender][collateralToken] += lockedCollateral;
        position[_positionIndex].debtAmount -= _amount;

        if (position[_positionIndex].debtAmount == 0) {
            for (uint256 i = _positionIndex; i < position.length - 1; i++) {
                position[i] = position[i + 1];
            }
            position.pop();
        }
        debtHistory[msg.sender][_positionIndex].active = false;

        // interactions
        lend.receiveRepayment(msg.sender, msg.sender, uniqueId, repaymentAmount);
    }

    function withdraw(address _token, uint256 _amount)
        external
        nonReentrant
        zeroCheck(_amount)
        oneTokenSupport(_token)
    {
        // checks
        if (collateral[msg.sender][_token] == 0) {
            revert Borrowing__NoCurrentCollateral();
        }
        if (_amount > collateral[msg.sender][_token]) {
            revert Borrowing__NotEnoughWithdrawableBalance();
        }

        // effects
        collateral[msg.sender][_token] -= _amount;

        // interaction
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function _isSafe(address _user, uint256 _positionIndex) internal view returns (bool) {
        // checks if user is safe
        BorrowStatus storage position = debtPosition[_user][_positionIndex];
        uint256 lockedCollateralAmount = position.lockedCollateralAmount;
        uint256 collateralInUsd = oracle.calculateTokenWorthInUsd(position.collateralToken, lockedCollateralAmount);
        uint256 debtInUsd = oracle.calculateTokenWorthInUsd(position.debtToken, position.debtAmount);
        uint256 threshold = (collateralInUsd * LIQUIDATION_THRESHOLD) / PERCENTAGE_PRECISION;

        return threshold > debtInUsd;
    }

    ///////////////////////////////////////////////////////
    ///    HELPERS
    ///////////////////////////////////////////////////////

    function _interest(uint256 _amount, address _token) public view returns (uint256) {
        uint256 amountInUsd = oracle.calculateTokenWorthInUsd(_token, _amount);

        uint256 rate = _interestRate(_token);

        if (rate != firstInterestRate && rate != secondInterestRate && rate != thirdInterestRate) {
            revert Borrowing__InvalidInterestRate();
        }

        uint256 interestInUsd = Math.mulDiv(amountInUsd, rate, PERCENTAGE_PRECISION);
        return oracle.usdWorthToTokenAmount(_token, interestInUsd);
    }

    function _interestRate(address _token) public view returns (uint256) {
        //checks the liquidity of a token in lending protocol
        uint256 liquidity = lend.getLiquidity(_token);
        uint256 firstQuota = (liquidity * firstQuotaPercent) / PERCENTAGE_PRECISION;
        uint256 secondQuota = (liquidity * secondQuotaPercent) / PERCENTAGE_PRECISION;
        if (protocolDebt[_token] < firstQuota) {
            return firstInterestRate;
        } else if (protocolDebt[_token] < secondQuota) {
            return secondInterestRate;
        } else {
            return thirdInterestRate;
        }
    }
}
