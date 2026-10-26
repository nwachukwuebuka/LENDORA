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

/**
 ***@author Nwachukwu Chukwuebuka
 ***@title Lendora Borrowing System
 *
 */
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract Borrowing is IBorrowing, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///////////////////////////////////////////////////////
    ///    ERRORS
    ///////////////////////////////////////////////////////
    error Borrowing__AmountCantBeZero();
    error Borrowing__NotSupportedToken();
    error Borrowing__LessThanMinimumDeposit();
    error Borrowing__CantBeSameToken();
    error Borrowing__LessThanMinimumCollateralWorth();
    error Borrowing__CantBorrowMoreThanLimit();
    error Borrowing__InvalidInterestRate();
    error Borrowing__LoanPositionCleared();
    error Borrowing__NotEnoughWithdrawableBalance();
    error Borrowing__UnavaliablenBalance();
    error Borrowing__NoDebtForToken();
    error Borrowing__NoCurrentCollateral();

    ///////////////////////////////////////////////////////
    ///    VARAIBLES
    ///////////////////////////////////////////////////////
    uint256 private constant PRECISION = 1e18;
    uint256 private constant PERCENTAGE_PRECISION = 100;
    uint256 private percentage = 70;
    uint256 private minDeposit = 100e18; // $100
    uint256 public firstInterestRate = 2;
    uint256 public secondInterestRate = 5;
    uint256 public thirdInterestRate = 10;
    uint256 private firstQuotaPercent = 30;
    uint256 private secondQuotaPercent = 75;
    uint256 private interests;

    struct BorrowStatus {
        uint256 amount;
        uint256 borrow_time;
        uint256 interest_rate;
        uint256 interest;
        address collateralToken;
    }

    struct Against {
        uint256 amount;
        address tokenAgainst;
    }
    // collateral
    mapping(address _user => mapping(address _token => uint256 _amount)) private collateral;
    mapping(address _user => address[] tokens) private userCollateralTokens;
    mapping(address => mapping(address => bool)) private hasCollateralToken;

    // debt
    mapping(address _user => mapping(address _token => BorrowStatus[])) private debtPosition;
    mapping(address _user => mapping(address _token => uint256 _amount)) private userDebt;
    mapping(address _token => uint256 _amount) private protocolDebt;
    mapping(address _user => address[]) userBorrowedTokens;
    mapping(address _user => mapping(address _token => bool)) public hasBorrowedToken;
    mapping(address _user => mapping(address _collateralToken => Against[])) private debtAssociate;

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

    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////

    constructor(address _lendingContract, address _priceOracle) {
        lend = ILending(_lendingContract);
        oracle = IPriceFeedOracle(_priceOracle);

        supportedTokens = oracle.getAllSupportedTokens();
    }

    function depositCollateral(uint256 _amount, address _token) external override nonReentrant zeroCheck(_amount) {
        // checks
        bool supported;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (_token == supportedTokens[i]) {
                supported = true;
            }
        }
        if (!supported) {
            revert Borrowing__NotSupportedToken();
        }
        uint256 worth = oracle.calculateTokenWorthInUsd(_token, _amount);
        if (worth < minDeposit) {
            revert Borrowing__LessThanMinimumDeposit();
        }

        // effects
        if (!hasCollateralToken[msg.sender][_token]) {
            userCollateralTokens[msg.sender].push(_token);
            hasCollateralToken[msg.sender][_token] = true;
        }
        collateral[msg.sender][_token] += _amount;

        // interactions
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function borrow(uint256 _amount, address _borrowToken, address _collateral)
        external
        override
        nonReentrant
        zeroCheck(_amount)
    {
        // checks
        if (_borrowToken == _collateral) {
            revert Borrowing__CantBeSameToken();
        }
        uint256 userCollateral = collateral[msg.sender][_collateral];
        uint256 worth = oracle.calculateTokenWorthInUsd(_collateral, userCollateral);
        if (worth < minDeposit) {
            revert Borrowing__LessThanMinimumCollateralWorth();
        }

        uint256 borrowLimit = (worth * percentage) / PERCENTAGE_PRECISION;

        address[] storage tokens = userBorrowedTokens[msg.sender];
        uint256 currentDebt;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenAmount = userDebt[msg.sender][tokens[i]];
            currentDebt += oracle.calculateTokenWorthInUsd(tokens[i], tokenAmount);
        }
        uint256 interest = _interest(_amount, _borrowToken);
        uint256 totalLoan = interest + _amount;
        uint256 _amountInUsd = oracle.calculateTokenWorthInUsd(_borrowToken, totalLoan);
        if (currentDebt + _amountInUsd > borrowLimit) {
            revert Borrowing__CantBorrowMoreThanLimit();
        }

        // effects
        debtPosition[msg.sender][_borrowToken].push(
            BorrowStatus({
                amount: totalLoan,
                borrow_time: block.timestamp,
                interest_rate: _interestRate(_borrowToken),
                interest: interest,
                collateralToken: _collateral
            })
        );
        interests += interest;
        userDebt[msg.sender][_borrowToken] += totalLoan;

        Against[] storage debts = debtAssociate[msg.sender][_collateral];

        bool found;

        for (uint256 i = 0; i < debts.length; i++) {
            if (debts[i].tokenAgainst == _borrowToken) {
                debts[i].amount += totalLoan;
                found = true;
                break;
            }
        }

        if (!found) {
            debts.push(Against({amount: totalLoan, tokenAgainst: _borrowToken}));
        }

        protocolDebt[_borrowToken] += _amount;

        if (!hasBorrowedToken[msg.sender][_borrowToken]) {
            userBorrowedTokens[msg.sender].push(_borrowToken);
            hasBorrowedToken[msg.sender][_borrowToken] = true;
        }

        // interactions
        lend.releaseBorrowedTokens(_borrowToken, msg.sender, _amount);
    }

    function repay(address _token, uint256 _positionId, uint256 _amount)
        external
        override
        nonReentrant
        zeroCheck(_amount)
    {
        BorrowStatus storage position = debtPosition[msg.sender][_token][_positionId];

        // CHECKS
        if (userDebt[msg.sender][_token] == 0) {
            revert Borrowing__NoDebtForToken();
        }

        if (position.amount == 0) {
            revert Borrowing__LoanPositionCleared();
        }

        if (_amount > position.amount) {
            revert Borrowing__NotEnoughWithdrawableBalance();
        }

        // EFFECTS
        position.amount -= _amount;
        userDebt[msg.sender][_token] -= _amount;
        if (position.amount == 0) {
            delete debtPosition[msg.sender][_token][_positionId];
        }

        // INTERACTIONS
        IERC20(_token).safeTransferFrom(msg.sender, address(lend), _amount);
    }

    function withdraw(address _token, uint256 _amount) external override nonReentrant zeroCheck(_amount) {
        (uint256 amount, uint256 amountInUsd) = getWithdrawableBalance(_token);
        if (collateral[msg.sender][_token] == 0) {
            revert Borrowing__NoCurrentCollateral();
        }
        if (_amount > amount) {
            revert Borrowing__NotEnoughWithdrawableBalance();
        }

        collateral[msg.sender][_token] -= _amount;

        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function liquidate(address _user, uint256 _amount) external {}

    ///////////////////////////////////////////////////////
    ///    HELPERS
    ///////////////////////////////////////////////////////
    function getWithdrawableBalance(address _token) public view override returns (uint256 amount, uint256 amountInUsd) {
        uint256 _collateral = collateral[msg.sender][_token];
        uint256 worth = oracle.calculateTokenWorthInUsd(_token, _collateral);
        uint256 debtInUsd;

        Against[] storage debts = debtAssociate[msg.sender][_token];

        for (uint256 i = 0; i < debts.length; i++) {
            debtInUsd += oracle.calculateTokenWorthInUsd(debts[i].tokenAgainst, debts[i].amount);
        }

        // debt/LTV
        uint256 minimumCollateralUsd = Math.mulDiv(debtInUsd, PERCENTAGE_PRECISION, percentage, Math.Rounding.Ceil);

        if (minimumCollateralUsd >= worth) {
            return (0, 0);
        }
        amountInUsd = worth - minimumCollateralUsd;
        amount = oracle.usdWorthToTokenAmount(_token, amountInUsd);
    }

    function _interest(uint256 _amount, address _token) public view override returns (uint256) {
        uint256 amountInUsd = oracle.calculateTokenWorthInUsd(_token, _amount);

        uint256 rate = _interestRate(_token);

        if (rate != firstInterestRate && rate != secondInterestRate && rate != thirdInterestRate) {
            revert Borrowing__InvalidInterestRate();
        }

        uint256 interestInUsd = Math.mulDiv(amountInUsd, rate, PERCENTAGE_PRECISION);
        uint8 tokenDecimals = IERC20Metadata(_token).decimals();
        uint256 tokenPrecision = 10 ** uint256(tokenDecimals);
        uint256 tokenPrice = oracle.getPriceInUsd(_token);

        return Math.mulDiv(interestInUsd, tokenPrecision, tokenPrice);
    }

    function _interestRate(address _token) public view override returns (uint256) {
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

    ///////////////////////////////////////////////////////
    ///    GETTERS
    ///////////////////////////////////////////////////////
}
