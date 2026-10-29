// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import {ILending} from "./interfaces/ILending.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPriceFeedOracle} from "./interfaces/IPriceFeedOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 ***@author Nwachukwu Chukwuebuka
 ***@title Lendora Lending Contract
 ***@notice Implements the lending functionality of the Lendora DeFi protocol.
 ***         Allocates 60% of penalty fees to lenders and retains the
 ***         remaining 40% as protocol liquidity.
 ***@dev Manages lending positions, withdrawals, lock durations, and early-withdrawal penalties.
 */
abstract contract Lending is ILending, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ///////////////////////////////////////////////////////
    ///    ERRORS
    ///////////////////////////////////////////////////////
    error Lending__LessThanMinimalAmount();
    error Lending__PositionLessThanOne();
    error Lending__PositionDoesNotExist();
    error Lending__PositionAlreadyWithdrawn();
    error Lending__PenaltyRateTooHigh();
    error Lending__PenaltyRateTooLow();
    error Lending__InvalidAddress();
    error Lending__BorrowingAlreadySet();
    error Lending__NotBorrowingContract();
    error Lending__InvalidTransactionId();
    error Lending__IncorrectRepaymentAmount();
    error Lending__AmountCantBeZero();
    error Lending__WithdrawalPending();
    error Lending__InsufficientBalance();
    error  Lending__LiquidationOutOfBound();



    ///////////////////////////////////////////////////////
    ///    VARIABLES
    /////////////////////////////////////////////////////
    uint256 private constant PERCENTAGE_PRECISION = 100;
    uint256 private withdrawTime = 43_200;
    uint256 public lendersRewardPercent = 40;
    uint256 public lockDuration = 7_257_600; //84 days
    uint256 public penaltyRate = 5; // 5%
    uint256 public minimumDeposit = 1000e18; //$1000
    mapping(address token => uint256 fees) private penaltyReward;
    mapping(address user => mapping(address token => uint256 depositedAmount)) private depositRecord;

    struct LendingPosition {
        uint256 amount;
        uint256 startTime;
    }

    struct PendingWithdrawal {
        uint256 amount;
        uint256 positionId;
        uint256 requestime;
        bool stillPending;
    }

    struct BorrowRecord {
        bytes32 uniqueId;
        address debtToken;
        address collateralToken;
        uint256 principal;
        uint256 totalAmount;
        uint256 interest;
    }
    mapping(address user => mapping(address token => LendingPosition[])) private position;
    mapping(address user => mapping(address token => PendingWithdrawal[])) private pendingWithdrawals;
    mapping(address user => mapping(address token => uint256 amount)) private withdrawalBalance;
    IPriceFeedOracle private priceOracle;
    address public borrowingContract;
    mapping(address _user => BorrowRecord[]) private borrowRecords;
    mapping(address _token => uint256 _amount) private interests;

    ///////////////////////////////////////////////////////
    ///    MODIFIERS
    ///////////////////////////////////////////////////////
    modifier onlyBorrowingContract() {
        if (msg.sender != borrowingContract) {
            revert Lending__NotBorrowingContract();
        }
        _;
    }
    modifier zeroCheck(uint256 _amount) {
    if (_amount == 0) {
        revert Lending__AmountCantBeZero();
    }
    _;
}


    ///////////////////////////////////////////////////////
    ///    FUNCTIONS
    ///////////////////////////////////////////////////////

    /// @notice Initializes the lending contract.
    /// @dev Sets the initial owner and price oracle.
    /// @param _priceFeedOracle The address of the price oracle contract.
    constructor(address _priceFeedOracle) Ownable(msg.sender) {
        priceOracle = IPriceFeedOracle(_priceFeedOracle);
    }

    /// @notice Deposits tokens into the lending protocol.
    /// @dev Records the lending position and its start timestamp, also
    ///      records the total amount of a particular that a user owns.
    /// @param _token The address of the token to lend.
    /// @param _amount The amount of tokens to deposit.
    function lend(uint256 _amount, address _token) external override nonReentrant {
        bool supportedToken = priceOracle.isTokenSupported(_token);
        uint256 worth = priceOracle.calculateTokenWorthInUsd(_token, _amount);

        if (!supportedToken || (worth < minimumDeposit)) {
            revert Lending__LessThanMinimalAmount();
        }
        position[msg.sender][_token].push(LendingPosition({amount: _amount, startTime: block.timestamp}));
        depositRecord[msg.sender][_token] += _amount;

        // totalLent[_token] += _amount;
        // if (!isPoolLender[_token][msg.sender]) {
        //     poolLenders[_token].push(msg.sender);
        //     isPoolLender[_token][msg.sender] = true;
        // }
        // if (lastInterestDistribution[_token] == 0) {
        //     lastInterestDistribution[_token] = block.timestamp;
        // }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(address _token, uint256 _position, uint256 _amount) external nonReentrant zeroCheck(_amount) {
    
        PendingWithdrawal[] storage pend = pendingWithdrawals[msg.sender][_token];

        for (uint256 i = 0; i < pend.length; i++) {
            if (pend[i].positionId == _position && pend[i].stillPending) {
                revert Lending__WithdrawalPending();
            }
        }

        uint256 withdrawable = withdrawalBalance[msg.sender][_token];

        uint256 percentWith = (withdrawable * 30) / PERCENTAGE_PRECISION;

        //INTERACTIONS
        if (percentWith >= _amount) {
            withdrawalBalance[msg.sender][_token] -= _amount;
            IERC20(_token).safeTransfer(msg.sender, _amount);
        } else {
            pendingWithdrawals[msg.sender][_token].push(
                PendingWithdrawal({
                    amount: _amount, positionId: _position, requestime: block.timestamp, stillPending: true
                })
            );
        }
    }

    /// @notice Withdraws tokens from an existing lending position.
    /// @dev Calculates any early-withdrawal penalty, updates the user's
    ///      records, and transfers the remaining amount to the user.
    /// @param _token The address of the token associated with the position.
    /// @param _position The 1-based index of the lending position to withdraw.
    function cancelPosition(address _token, uint256 _position) external override {
        //CHECKS
        if (_position < 1) {
            revert Lending__PositionLessThanOne();
        }
        uint256 positionId = _position - 1;

        if (positionId >= position[msg.sender][_token].length) {
            revert Lending__PositionDoesNotExist();
        }

        LendingPosition storage queriedPos = position[msg.sender][_token][positionId];

        if (queriedPos.amount == 0) {
            revert Lending__PositionAlreadyWithdrawn();
        }

        uint256 lendAmount = queriedPos.amount;
        uint256 penalty = _penalty(queriedPos);
        uint256 withdrawal = lendAmount - penalty;

        // for protocol
        uint256 totalPenalty = lendAmount - withdrawal;

        uint256 penaltyFees = (totalPenalty * lendersRewardPercent) / PERCENTAGE_PRECISION;

        //EFFECTS
        //update the position
        delete position[msg.sender][_token][positionId];
        //update total deposit
        depositRecord[msg.sender][_token] -= lendAmount;
        //record penalty fee
        penaltyReward[_token] += penaltyFees;

        // SUB INTERACTION
        withdrawalBalance[msg.sender][_token] += withdrawal;
    }

    function releaseBorrowedTokens(address _token, address _receiver, uint256 _amount)
        external
        nonReentrant
        onlyBorrowingContract
    {
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function receiveRepayment(address borrower, bytes32 uniqueId, uint256 amount)
        external
        nonReentrant
        onlyBorrowingContract
    {
        BorrowRecord[] storage record = borrowRecords[borrower];
        uint256 index;
        bool found;

        for (uint256 i = 0; i < record.length; i++) {
            if (record[i].uniqueId == uniqueId) {
                index = i;
                found = true;
                break;
            }
        }

        if (!found) revert Lending__InvalidTransactionId();

        uint256 repayment = record[index].totalAmount;
        address debtToken = record[index].debtToken;

        if (repayment != amount) revert Lending__IncorrectRepaymentAmount();

        interests[record[index].debtToken] += record[index].interest;

        for (uint256 i = index; i < record.length - 1; i++) {
            record[i] = record[i + 1];
        }
        record.pop();

        IERC20(debtToken).safeTransferFrom(borrower, address(this), amount);
    }

    function updateBorrowRecord(address _user, uint256 _amount, bytes32 _uniqueId) external onlyBorrowingContract {
        BorrowRecord[] storage debtRecords = borrowRecords[_user];
        uint256 index;
        bool found;
        for (uint256 i = 0; i < debtRecords.length; i++) {
            if (debtRecords[i].uniqueId == _uniqueId) {
                index = i;
                found = true;
                break;
            }
        }

        if (!found) revert Lending__InvalidTransactionId();

        BorrowRecord storage record = borrowRecords[_user][index];
        uint256 debt = record.totalAmount;
        if (_amount > record.totalAmount) {
            revert Lending__LiquidationOutOfBound();
        }

        if (debt == _amount) {
            for (uint256 i = index; i < debtRecords.length - 1; i++) {
                debtRecords[i] = debtRecords[i + 1];
            }
            debtRecords.pop();
        } else {
            record.totalAmount -= _amount;
        }
    }

    function recordBorrow(
        address _borrower,
        bytes32 _positionId,
        address _debtToken,
        address _collateralToken,
        uint256 _requestedLoan,
        uint256 _repayAmount,
        uint256 _interest
    ) external  onlyBorrowingContract {
        borrowRecords[_borrower].push(
            BorrowRecord({
                uniqueId: _positionId,
                debtToken: _debtToken,
                collateralToken: _collateralToken,
                principal: _requestedLoan,
                totalAmount: _repayAmount,
                interest: _interest
            })
        );
    }

    ///////////////////////////////////////////////////////
    ///    HELPERS
    ///////////////////////////////////////////////////////

    /// @notice Calculates the penalty for withdrawing before the lock expires.
    /// @dev Returns zero if the lock duration has elapsed. Otherwise,
    ///      calculates the penalty based on the remaining lock duration.
    /// @param queriedPos The lending position being evaluated.
    /// @return penalty The calculated early-withdrawal penalty in token units.
    function _penalty(LendingPosition memory queriedPos) internal view returns (uint256) {
        uint256 totalTime = queriedPos.startTime;
        uint256 initialLend = queriedPos.amount;

        uint256 hoursSpent = block.timestamp - totalTime;
        uint256 hoursLeft = lockDuration - hoursSpent;

        // Penalty = (InitialLend × PenaltyRate × HoursLeft) / TotalHours
        uint256 Penalty = (initialLend * penaltyRate * hoursLeft) / lockDuration * 100;

        return Penalty;
    }

    ///////////////////////////////////////////////////////
    ///    UPDATERS
    ///////////////////////////////////////////////////////

    /// @notice Updates the lock duration for new lending positions.
    /// @dev Only the contract owner can change the lock duration.
    /// @param _newDuration The new lock duration in seconds.
    function setLockDuration(uint256 _newDuration) external onlyOwner {
        lockDuration = _newDuration;
    }

    ///@notice Updates the penalty rate for early withdrawals.
    /// @dev Only the contract owner can change the penalty rate.
    ///      The rate uses 1e18 precision, where 5e16 represents 5%.
    /// @param _newRate The new penalty rate, capped at 10% (1e17).
    function setPenaltyRate(uint256 _newRate) external onlyOwner {
        if (_newRate > 10) {
            revert Lending__PenaltyRateTooHigh();
        }
        if (_newRate < 3) {
            revert Lending__PenaltyRateTooLow();
        }

        penaltyRate = _newRate;
    }

    function setBorrowingContract(address _borrowingContract) external onlyOwner {
        if (_borrowingContract == address(0)) {
            revert Lending__InvalidAddress();
        }

        if (borrowingContract != address(0)) {
            revert Lending__BorrowingAlreadySet();
        }

        borrowingContract = _borrowingContract;
    }

    ///////////////////////////////////////////////////////
    ///    GETTERS
    ///////////////////////////////////////////////////////

    function getLiquidity(address _token) public view returns (uint256) {
        return (IERC20(_token).balanceOf(address(this)) - penaltyReward[_token]);
    }
}
