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

/**
 ***@author Nwachukwu Chukwuebuka
 ***@title Lendora Lending Contract
 ***@notice Implements the lending functionality of the Lendora DeFi protocol.
 ***         Allocates 60% of penalty fees to lenders and retains the
 ***         remaining 40% as protocol liquidity.
 ***@dev Manages lending positions, withdrawals, lock durations, and early-withdrawal penalties.
 */
contract Lending is ILending, Ownable, ReentrancyGuard {
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

    ///////////////////////////////////////////////////////
    ///    VARIABLES
    /////////////////////////////////////////////////////
    uint256 private constant PERCENTAGE_PRECSION = 100;
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
    mapping(address user => mapping(address token => LendingPosition[])) private position;
    IPriceFeedOracle private priceOracle;
    address public borrowingContract;

    ///////////////////////////////////////////////////////
    ///    MODIFIERS
    ///////////////////////////////////////////////////////
    modifier onlyBorrowingContract() {
        if (msg.sender != borrowingContract) {
            revert Lending__NotBorrowingContract();
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

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Withdraws tokens from an existing lending position.
    /// @dev Calculates any early-withdrawal penalty, updates the user's
    ///      records, and transfers the remaining amount to the user.
    /// @param _token The address of the token associated with the position.
    /// @param _position The 1-based index of the lending position to withdraw.
    function withdraw(address _token, uint256 _position) external override nonReentrant {
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

        uint256 totalPenalty = lendAmount - withdrawal;

        uint256 penaltyFees = (totalPenalty * lendersRewardPercent) / PERCENTAGE_PRECSION;

        //EFFECTS
        //update the position
        delete position[msg.sender][_token][positionId];
        //update total deposit
        depositRecord[msg.sender][_token] -= lendAmount;
        //record penalty fee
        penaltyReward[_token] += penaltyFees;

        //INTERACTIONS
        IERC20(_token).safeTransfer(msg.sender, withdrawal);
    }

    function releaseBorrowedTokens(address _token, address _receiver, uint256 _amount) external onlyBorrowingContract {
        IERC20(_token).safeTransfer(_receiver, _amount);
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
