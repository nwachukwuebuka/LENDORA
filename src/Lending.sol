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
    error Lending__LiquidationOutOfBound();
    error Lending__ProtocolLendingLimit();
    error Lending__LendingBoxesExceeded();
    error Lending__NoInterestToClaim();
    error Lending__LessThanMinimalAmountOrTokenNotSupported();
    error Lending__NoAvailableInterest();

    ///////////////////////////////////////////////////////
    ///    CUSTOM TYPES
    ///////////////////////////////////////////////////////
    struct LendingPosition {
        uint256 amount;
        bytes32 id;
        uint256 startTime;
    }

    struct PendingBox {
        address lender;
        uint256 amount;
        bytes32 id;
        bool pending;
        bool interestAvailable;
        bool interestClaimed;
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

    ///////////////////////////////////////////////////////
    ///    VARIABLES
    //////////////////////////////////////////////////////

    // LEND
    uint256 private constant PERCENTAGE_PRECISION = 100;
    uint256 private timestampHolder;
    uint256 private withdrawTime = 43_200;
    uint256 public box20percent = 50;
    uint256 private constant POOL_AVAILABILITY = 80;
    uint256 public lockDuration = 84 days;
    uint256 public penaltyRate = 5; // 5%
    uint256 public minimumDeposit = 1000e18; //$1000
    mapping(address user => mapping(address token => uint256 depositedAmount)) private depositRecord;
    uint256 private pendedBox;
    uint256 private constant MAX_IN_BOX = 20;
    mapping(address _token => mapping(bytes32 _id => PendingBox[])) private pendingBoxes;
    mapping(address _token => uint256 _amount) public poolBalance;
    mapping(address _token => address[] _lender) private poolLenders;
    mapping(address user => mapping(address token => LendingPosition[])) private lentPositions;
    mapping(address user => mapping(address token => LendingPosition[])) private lendHistory;
    mapping(address user => mapping(address token => PendingWithdrawal[])) private pendingWithdrawals;
    mapping(address token => mapping(bytes32 id => uint256 amount)) private remainsOfCurrentBox;
    mapping(address token => bytes32[] id) private IDs;
    mapping(address token => mapping(bytes32 id => uint256 amount)) private boxPenaltyReward;
    mapping(address lender => mapping(address token => uint256 amount)) private interestShare;
    bytes32 private currentIdToRelease;
    uint256 idIndex;

    // BORROWERS COPY
    mapping(address user => mapping(address token => uint256 amount)) private neutralBalance;
    IPriceFeedOracle private priceOracle;
    address public borrowingContract;
    mapping(address _user => BorrowRecord[]) private borrowRecords;
    mapping(address _token => uint256 _amount) private interestHistory;

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
        timestampHolder = block.timestamp;
        uint256 boxNumber = pendedBox++;
        bytes32 _id = keccak256(abi.encode(timestampHolder, boxNumber));
        bool supportedToken = priceOracle.isTokenSupported(_token);
        uint256 worth = priceOracle.calculateTokenWorthInUsd(_token, _amount);

        if (!supportedToken || (worth < minimumDeposit)) {
            revert Lending__LessThanMinimalAmountOrTokenNotSupported();
        }

        LendingPosition[] storage positions = lentPositions[msg.sender][_token];

        pendingBoxes[_token][_id].push(PendingBox({lender: msg.sender, amount: _amount, id: _id, pending: true, interestAvailable: false, interestClaimed: false, startTime: timestampHolder}));
        PendingBox[] storage box = pendingBoxes[_token][_id];

        if (box.length == MAX_IN_BOX) {
            for (uint256 i = 0; i < box.length; i++) {
                lentPositions[box[i].lender][_token].push(
                    LendingPosition({amount: box[i].amount, id: box[i].id, startTime: block.timestamp})
                );
                lendHistory[box[i].lender][_token].push(
                    LendingPosition({amount: box[i].amount, id: box[i].id, startTime: block.timestamp})
                );
                box[i].pending = false;
            }

            timestampHolder = 0;
        }
        IDs[_token].push(currentIdToRelease);
        _id = currentIdToRelease;

        depositRecord[msg.sender][_token] += _amount;

        poolBalance[_token] += _amount;

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(address _token, uint256 _position, uint256 _amount) external nonReentrant zeroCheck(_amount) {
        PendingWithdrawal[] storage pend = pendingWithdrawals[msg.sender][_token];

        for (uint256 i = 0; i < pend.length; i++) {
            if (pend[i].positionId == _position && pend[i].stillPending) {
                revert Lending__WithdrawalPending();
            }
        }

        uint256 withdrawable = neutralBalance[msg.sender][_token];

        uint256 percentWith = (withdrawable * 30) / PERCENTAGE_PRECISION;

        //INTERACTIONS
        if (percentWith >= _amount) {
            neutralBalance[msg.sender][_token] -= _amount;
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
    function cancelPosition(address _token, uint256 _position) external override zeroCheck(_position) {
        // checks
        uint256 positionIndex = _position - 1;
        LendingPosition storage position = lentPositions[msg.sender][_token][positionIndex];
        LendingPosition[] storage positions = lentPositions[msg.sender][_token];

        bytes32 boxId = position.id;
        PendingBox[] storage box = pendingBoxes[_token][boxId];
        uint256 lentAmount = position.amount;

        uint256 penalty = _penalty(position);
        uint256 index;

        if (positionIndex >= positions.length) {
            revert Lending__PositionDoesNotExist();
        }

        if (lentAmount == 0) {
            revert Lending__PositionAlreadyWithdrawn();
        }

        uint256 withdrawal = lentAmount - penalty;

        uint256 Box20Reward = (penalty * box20percent) / PERCENTAGE_PRECISION;

        for (uint256 i = 0; i < box.length; i++) {
            if (box[i].id == boxId) {
                index = i;
                break;
            }
        }

        boxPenaltyReward[_token][boxId] = Box20Reward;

        //EFFECTS
        //update the position
        delete lentPositions[msg.sender][_token][positionIndex];
        delete pendingBoxes[_token][boxId][index];
        //update total deposit
        depositRecord[msg.sender][_token] -= lentAmount;

        // SUB INTERACTION
        neutralBalance[msg.sender][_token] += withdrawal;
    }

    function releaseBorrowedTokens(address _token, address _receiver, uint256 _amount)
        external
        nonReentrant
        onlyBorrowingContract
        zeroCheck(_amount)
    {
        uint256 poolAmount = poolBalance[_token];

        uint256 pool20 = (20 * poolAmount) / 100;

        if (pool20 <= _amount) revert Lending__ProtocolLendingLimit();

        uint256 index2 = ++idIndex;

        PendingBox[] storage pend = pendingBoxes[_token][currentIdToRelease];
        PendingBox[] storage pend2 = pendingBoxes[_token][currentIdToRelease];

        uint256 boxAmount;
        uint256 box2Amount;

        for (uint256 i = 0; i < pend.length; i++) {
            boxAmount += pend[i].amount;
            box2Amount += pend2[i].amount;
        }

        if (_amount > boxAmount + box2Amount) {
            revert Lending__LendingBoxesExceeded();
        }

        if (_amount == boxAmount) {
            remainsOfCurrentBox[_token][IDs[_token][idIndex]];
            ++idIndex;
            currentIdToRelease = IDs[_token][idIndex];
        }
        if (_amount > boxAmount) {
            if (_amount == boxAmount + box2Amount) {
                remainsOfCurrentBox[_token][IDs[_token][idIndex]] == 0;
                ++idIndex;
                currentIdToRelease = IDs[_token][idIndex];
            } else {
                remainsOfCurrentBox[_token][IDs[_token][idIndex]] == (boxAmount + box2Amount) - _amount;
            }
        }
        remainsOfCurrentBox[_token][IDs[_token][idIndex]] = boxAmount - _amount;
        poolBalance[_token] -= _amount;

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
        PendingBox[] storage box = pendingBoxes[debtToken][uniqueId];

        if (repayment != amount) revert Lending__IncorrectRepaymentAmount();

        for(uint256 i = 0; i < box.length; i++){
            box[i].interestAvailable = true;

        }

        interestHistory[record[index].debtToken] += record[index].interest;

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
    ) external onlyBorrowingContract {
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

    function _distributeInterest(address token, uint256 boxIndex) internal zeroCheck(boxIndex){
        uint256 index = boxIndex - 1;

        bytes32 id = IDs[token][index];
        uint256 Box20Reward = boxPenaltyReward[token][id];
        uint256 amount;

        PendingBox[] storage pend = pendingBoxes[token][id];
        address[] memory lenders = new address[](20);

        if(!pend[0].interestAvailable){
            revert Lending__NoAvailableInterest();
        }

        if(block.timestamp - pend[0].startTime < lockDuration){
            revert Lending__NoAvailableInterest();
        }

        for (uint256 i = 0; i < pend.length; i++) {
            amount += pend[i].amount;
        }


        for (uint256 i = 0; i < pend.length; i++) {
            lenders[i] = pend[i].lender;
            interestShare[lenders[i]][token] = (pend[i].amount + Box20Reward) / amount;
            pend[i].interestAvailable = false;
        }
    }

    function claimInterest(address lender, address token) external {
        uint256 amount = interestShare[lender][token];

        if (amount == 0) {
            revert Lending__NoInterestToClaim();
        }

        neutralBalance[msg.sender][token] += amount;
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
        uint256 elapsed = block.timestamp - queriedPos.startTime;

        if (elapsed >= lockDuration) {
            return 0;
        }

        uint256 timeLeft = lockDuration - elapsed;

        // Penalty = (InitialLend × PenaltyRate × HoursLeft) / TotalHours
        uint256 Penalty = (queriedPos.amount * penaltyRate * timeLeft) / lockDuration * PERCENTAGE_PRECISION;

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

    function getLiquidity(address _token) public view returns (uint256){
        return Math.mulDiv(poolBalance[_token], POOL_AVAILABILITY, PERCENTAGE_PRECISION);
    }

    function getBoxId(address token, uint256 number) public view zeroCheck(number) returns (bytes32) {
        --number;
        // uint256 _number = number - 1;

        return IDs[token][number];
    }

    function getLendStatus(bytes32 _id, address _token) public view returns(string memory){
        PendingBox[] storage box = pendingBoxes[_token][_id];

        uint256 index;
        for(uint256 i = 0; i < box.length; i++){
            if(box[i].id == _id){
                index = i;
                break;
            }
        }
        
        if(pendingBoxes[_token][_id][index].pending == false){
            return "In Position";
        }
        return "Pending";
    }
}
