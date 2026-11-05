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
 * @title Lendora Lending Contract
 * @author Nwachukwu Chukwuebuka
 * @notice Manages the lending operations of the Lendora DeFi protocol.
 * @dev Handles lender deposits, lending positions, lending boxes,
 *      withdrawals, early-withdrawal penalties, interest distribution,
 *      and communication with the Borrowing contract.
 *
 *      Deposits are organized into boxes containing up to 20 lenders.
 *      Only completed boxes are intended to be available for borrowing.
 *
 *      The contract also maintains borrower repayment records and
 *      distributes eligible interest and penalty rewards to lenders.
 */
contract Lending is Ownable, ReentrancyGuard {
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
    error Lending__InvalidTransaction();
    error Lending__TransactionPending();

    ///////////////////////////////////////////////////////
    ///    CUSTOM TYPES
    ///////////////////////////////////////////////////////
    enum WithdrawalStatus {
        pending,
        completed,
        cancelled
    }

    /**
     * @notice Represents an individual lender's deposit position.
     * @param amount The amount of tokens deposited by the lender.
     * @param id The unique identifier of the lending box.
     * @param startTime The timestamp when the lending position started.
     */
    struct LendingPosition {
        uint256 amount;
        bytes32 id;
        uint256 startTime;
    }

    /**
     * @notice Represents an individual lender's contribution to a lending box.
     * @param lender The address of the lender.
     * @param amount The amount of tokens contributed.
     * @param id The identifier shared by lenders in the same box.
     * @param pending Indicates whether the box contribution is still pending.
     * @param interestAvailable Indicates whether interest is available for distribution.
     * @param interestClaimed Indicates whether the lender has claimed interest.
     * @param startTime The timestamp associated with the contribution.
     */
    struct PendingBox {
        address lender;
        uint256 amount;
        bytes32 id;
        bool pending;
        bool interestAvailable;
        bool interestClaimed;
        uint256 startTime;
    }

    /**
     * @notice Stores a lender's pending withdrawal request.
     * @param amount The requested withdrawal amount.
     * @param positionId The identifier of the associated lending position.
     * @param requestime The timestamp when the withdrawal was requested.
     * @param stillPending Indicates whether the request is still pending.
     */
    struct PendingWithdrawal {
        uint256 amount;
        uint256 requestime;
        address token;
        WithdrawalStatus status;
    }

    /**
     * @notice Stores the repayment information associated with a borrowing position.
     * @param uniqueId The unique identifier of the borrowing position.
     * @param debtToken The token borrowed by the borrower.
     * @param collateralToken The token deposited as collateral.
     * @param principal The original borrowed amount.
     * @param totalAmount The total repayment amount, including interest.
     * @param interest The interest component of the repayment.
     */
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
    uint256 public box20percent = 80;
    uint256 private constant POOL_AVAILABILITY = 80;
    uint256 private withdrawTime = 12 hours;
    uint256 public lockDuration = 84 days;
    uint256 public penaltyRate = 5; // 5%
    uint256 public minimumDeposit = 1000e18; //$1000
    mapping(address token => uint256 amount) private pendedBox;
    uint256 private constant MAX_IN_BOX = 20;
    mapping(address _token => mapping(bytes32 _id => PendingBox[])) private pendingBoxes;
    mapping(address _token => uint256 _amount) public poolBalance;
    mapping(address _token => address[] _lender) private poolLenders;
    mapping(address user => mapping(address token => LendingPosition[])) private lentPositions;
    mapping(address user => mapping(address token => LendingPosition[])) private lendHistory;
    mapping(address user => PendingWithdrawal[]) private pendingWithdrawals;
    mapping(address token => mapping(bytes32 id => uint256 amount)) private remainsOfCurrentBox;
    mapping(address token => bytes32[] id) private IDs;
    mapping(address token => mapping(bytes32 id => uint256 amount)) private boxPenaltyReward;
    mapping(address lender => mapping(address token => uint256 amount)) private interestShare;
    mapping(address token => uint256 time) private timeStampHolder;
    mapping(address token => uint256 number) private borrowBoxIndex;

    // BORROWERS COPY
    mapping(address user => mapping(address token => uint256 amount)) private neutralBalance;
    IPriceFeedOracle private priceOracle;
    address public borrowingContract;
    mapping(address _user => BorrowRecord[]) private borrowRecords;
    mapping(address _token => uint256 _amount) private interestHistory;
    mapping(address token => mapping(bytes32 id => uint256 amount)) private boxInterest;

    ///////////////////////////////////////////////////////
    ///    MODIFIERS
    ///////////////////////////////////////////////////////
    /**
     * @notice Restricts function execution to the configured Borrowing contract.
     * @dev Reverts if the caller is not the authorized Borrowing contract.
     */
    modifier onlyBorrowingContract() {
        if (msg.sender != borrowingContract) {
            revert Lending__NotBorrowingContract();
        }
        _;
    }

    /**
     * @notice Prevents execution when the supplied amount is zero.
     * @param _amount The amount to validate.
     */
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
    function lend(uint256 _amount, address _token) external nonReentrant {
        if (timeStampHolder[_token] == 0) {
            timeStampHolder[_token] = block.timestamp;
        }
        uint256 timestampHolder = timeStampHolder[_token];
        uint256 boxNumber = pendedBox[_token];

        bytes32 _id = keccak256(abi.encode(timestampHolder, boxNumber));

        if (!priceOracle.isTokenSupported(_token)) {
            revert Lending__LessThanMinimalAmountOrTokenNotSupported();
        }

        uint256 worth = priceOracle.calculateTokenWorthInUsd(_token, _amount);

        if (worth < minimumDeposit) {
            revert Lending__LessThanMinimalAmountOrTokenNotSupported();
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        pendingBoxes[_token][_id].push(
            PendingBox({
                lender: msg.sender,
                amount: _amount,
                id: _id,
                pending: true,
                interestAvailable: false,
                interestClaimed: false,
                startTime: 0
            })
        );
        PendingBox[] storage box = pendingBoxes[_token][_id];

        if (box.length == MAX_IN_BOX) {
            IDs[_token].push(_id);

            for (uint256 i = 0; i < box.length; i++) {
                box[i].startTime = timeStampHolder[_token];
                lentPositions[box[i].lender][_token].push(
                    LendingPosition({amount: box[i].amount, id: box[i].id, startTime: block.timestamp})
                );
                lendHistory[box[i].lender][_token].push(
                    LendingPosition({amount: box[i].amount, id: box[i].id, startTime: block.timestamp})
                );
                box[i].pending = false;
            }

            timeStampHolder[_token] = 0;
            pendedBox[_token]++;
        }

        poolBalance[_token] += _amount;
    }

    /**
     * @notice Requests or processes a withdrawal from the lender's available balance.
     * @dev Allows an immediate withdrawal when the requested amount is within
     *      the configured immediate withdrawal limit. Otherwise, records
     *      a pending withdrawal request.
     * @param _token The token to withdraw.
     * @param _amount The amount of tokens requested for withdrawal.
     */
    function withdraw(address _token, uint256 _amount) external nonReentrant zeroCheck(_amount) {
        uint256 withdrawable = neutralBalance[msg.sender][_token];

        if (_amount > withdrawable) revert Lending__InsufficientBalance();

        uint256 percentWith = (withdrawable * 30) / PERCENTAGE_PRECISION;

        //INTERACTIONS
        if (percentWith >= _amount) {
            neutralBalance[msg.sender][_token] -= _amount;
            IERC20(_token).safeTransfer(msg.sender, _amount);
        } else {
            neutralBalance[msg.sender][_token] -= _amount;
            pendingWithdrawals[msg.sender].push(
                PendingWithdrawal({
                    amount: _amount, requestime: block.timestamp, token: _token, status: WithdrawalStatus.pending
                })
            );
        }
    }

    /**
     * @notice Cancels an existing lending position.
     * @dev Calculates any applicable early-withdrawal penalty, removes the
     *      position from the lender's active records, and credits the
     *      withdrawable amount to the lender's neutral balance.
     * @param index The 1-based index of the lending position.
     */
    function processPendingWithdrawal(uint256 index) external zeroCheck(index) nonReentrant {
        --index;
        PendingWithdrawal[] storage pend = pendingWithdrawals[msg.sender];

        if (pend[index].amount == 0) revert Lending__InvalidTransaction();

        if (pend[index].status != WithdrawalStatus.pending) revert Lending__InvalidTransaction();

        if (pend[index].requestime + withdrawTime > block.timestamp) revert Lending__TransactionPending();

        pend[index].status = WithdrawalStatus.completed;
        IERC20(pend[index].token).safeTransfer(msg.sender, pend[index].amount);
    }

    /// @notice Withdraws tokens from an existing lending position.
    /// @dev Calculates any early-withdrawal penalty, updates the user's
    ///      records, and transfers the remaining amount to the user.
    /// @param _token The address of the token associated with the position.
    /// @param _position The 1-based index of the lending position to withdraw.
    function cancelPosition(address _token, uint256 _position) external zeroCheck(_position) {
        // checks
        uint256 positionIndex = _position - 1;
        LendingPosition[] storage positions = lentPositions[msg.sender][_token];
        if (positionIndex >= positions.length) {
            revert Lending__PositionDoesNotExist();
        }

        LendingPosition storage position = lentPositions[msg.sender][_token][positionIndex];

        bytes32 boxId = position.id;
        PendingBox[] storage boxes = pendingBoxes[_token][boxId];
        uint256 lentAmount = position.amount;

        uint256 penalty = _penalty(position);
        uint256 index;

        if (lentAmount == 0) {
            revert Lending__PositionAlreadyWithdrawn();
        }

        uint256 withdrawal = lentAmount - penalty;

        uint256 Box20Reward = (penalty * box20percent) / PERCENTAGE_PRECISION;

        bool found;
        for (uint256 i = 0; i < boxes.length; i++) {
            if (msg.sender == boxes[i].lender && boxes[i].id == boxId) {
                found = true;
                index = i;
                break;
            }
        }

        if (!found) revert Lending__PositionDoesNotExist();

        boxPenaltyReward[_token][boxId] = Box20Reward;

        //EFFECTS
        //update the position
        for (uint256 i = 0; i < positions.length - 1; i++) {
            positions[i] = positions[i + 1];
        }
        positions.pop();

        for (uint256 i = 0; i < boxes.length - 1; i++) {
            boxes[i] = boxes[i + 1];
        }
        boxes.pop();

        // SUB INTERACTION
        neutralBalance[msg.sender][_token] += withdrawal;
    }

    /**
     * @notice Releases lending liquidity to an approved borrower.
     * @dev Can only be called by the configured Borrowing contract.
     *      Enforces the protocol lending limit and checks available
     *      liquidity across the relevant lending boxes.
     * @param _token The token being released.
     * @param _receiver The address receiving the borrowed tokens.
     * @param _amount The amount of tokens to release.
     */
    function releaseBorrowedTokens(address _token, address _receiver, uint256 _amount)
        external
        nonReentrant
        onlyBorrowingContract
        zeroCheck(_amount)
    {
        uint256 poolAmount = poolBalance[_token];
        uint256 pool20 = (20 * poolAmount) / PERCENTAGE_PRECISION;
        uint256 index = borrowBoxIndex[_token];
        if (index >= IDs[_token].length) {
            revert Lending__LendingBoxesExceeded();
        }
        bytes32 currentId = IDs[_token][index];
        bytes32 nextId = IDs[_token][index + 1];
        // bytes32 nextId = IDs[_token][++index];

        if (pool20 <= _amount) revert Lending__ProtocolLendingLimit();

        PendingBox[] storage pend = pendingBoxes[_token][currentId];
        PendingBox[] storage pend2 = pendingBoxes[_token][nextId];

        uint256 boxAmount;
        uint256 box2Amount;

        if (remainsOfCurrentBox[_token][currentId] != 0) {
            boxAmount = remainsOfCurrentBox[_token][currentId];
        } else {
            for (uint256 i = 0; i < pend.length; i++) {
                boxAmount += pend[i].amount;
            }
        }

        if (index + 1 < IDs[_token].length) {
            for (uint256 i = 0; i < pend2.length; i++) {
                box2Amount += pend2[i].amount;
            }
        }

        for (uint256 i = 0; i < pend.length; i++) {
            box2Amount += pend2[i].amount;
        }

        if (_amount > boxAmount + box2Amount) {
            revert Lending__LendingBoxesExceeded();
        }

        if (_amount == boxAmount) {
            ++borrowBoxIndex[_token];
        }

        if (_amount < boxAmount) {
            remainsOfCurrentBox[_token][currentId] = boxAmount - _amount;
        }

        if (_amount > boxAmount) {
            // entering box 2
            if (_amount > boxAmount + box2Amount) revert Lending__LendingBoxesExceeded();

            if (_amount == boxAmount + box2Amount) {
                ++borrowBoxIndex[_token];
            } else {
                remainsOfCurrentBox[_token][currentId] = (boxAmount + box2Amount) - _amount;
            }
        }
        poolBalance[_token] -= _amount;

        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    /**
     * @notice Receives repayment for an existing borrowing position.
     * @dev Validates the borrowing record and repayment amount,
     *      transfers the repayment tokens into the Lending contract,
     *      updates interest availability, and removes the settled record.
     * @param borrower The address of the borrower whose debt is being repaid.
     * @param uniqueId The unique identifier of the borrowing position.
     * @param amount The total repayment amount.
     */
    function receiveRepayment(address borrower, address payer, bytes32 uniqueId, uint256 amount)
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

        // interaction
        IERC20(debtToken).safeTransferFrom(payer, address(this), amount);

        for (uint256 i = 0; i < box.length; i++) {
            box[i].interestAvailable = true;
        }

        interestHistory[record[index].debtToken] += record[index].interest;
        uint256 interest = Math.mulDiv(box20percent, record[index].interest, PERCENTAGE_PRECISION);
        boxInterest[record[index].debtToken][uniqueId] += interest;

        for (uint256 i = index; i < record.length - 1; i++) {
            record[i] = record[i + 1];
        }
        record.pop();

        poolBalance[debtToken] += repayment;
    }

    /**
     * @notice Updates or removes a borrower's repayment record.
     * @dev Restricted to the Borrowing contract.
     *      Removes the record when the supplied amount equals the
     *      recorded total repayment amount.
     * @param _user The address of the borrower.
     * @param _amount The amount being applied against the debt record.
     * @param _uniqueId The unique identifier of the borrowing position.
     */
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

    /**
     * @notice Records a newly created borrowing position.
     * @dev Stores the principal, total repayment amount, interest,
     *      debt token, and collateral token for future repayment processing.
     *      Restricted to the Borrowing contract.
     * @param _borrower The address of the borrower.
     * @param _positionId The unique identifier of the borrowing position.
     * @param _debtToken The token borrowed.
     * @param _collateralToken The token deposited as collateral.
     * @param _requestedLoan The original principal amount borrowed.
     * @param _repayAmount The total amount due, including interest.
     * @param _interest The interest charged on the borrowing position.
     */
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

    /**
     * @notice Distributes available interest and penalty rewards among lenders.
     * @dev Checks interest availability and the lending lock duration
     *      before calculating each lender's reward share.
     * @param token The token in which interest was generated.
     * @param boxIndex The 1-based index of the lending box.
     */
    function _distributeInterest(address token, uint256 boxIndex) internal zeroCheck(boxIndex) {
        uint256 index = boxIndex - 1;

        bytes32 id = IDs[token][index];
        uint256 Box20Reward = boxPenaltyReward[token][id];
        uint256 boxinterest = boxInterest[token][id];
        uint256 amount;
        uint256 totalInterest = Box20Reward + boxinterest;
        PendingBox[] storage pend = pendingBoxes[token][id];
        address[] memory lenders = new address[](20);

        if (!pend[0].interestAvailable) {
            revert Lending__NoAvailableInterest();
        }

        if (block.timestamp - pend[0].startTime < lockDuration) {
            revert Lending__NoAvailableInterest();
        }

        for (uint256 i = 0; i < pend.length; i++) {
            amount += pend[i].amount;
        }

        for (uint256 i = 0; i < pend.length; i++) {
            lenders[i] = pend[i].lender;
            interestShare[lenders[i]][token] += Math.mulDiv(pend[i].amount, totalInterest, amount);
            pend[i].interestAvailable = false;
        }
    }

    /**
     * @notice Claims the interest allocated to a lender.
     * @dev Credits the lender's available balance with their recorded
     *      interest share.
     * @param lender The address of the lender whose interest is being claimed.
     * @param token The token in which the interest is denominated.
     */
    function claimInterest(address lender, address token) external {
        uint256 amount = interestShare[lender][token];

        if (amount == 0) {
            revert Lending__NoInterestToClaim();
        }

        interestShare[lender][token] = 0;
        neutralBalance[lender][token] += amount;
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
        uint256 Penalty = (queriedPos.amount * penaltyRate * timeLeft) / (lockDuration * PERCENTAGE_PRECISION);

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

    /**
     * @notice Configures the authorized Borrowing contract.
     * @dev Can only be configured once and rejects the zero address.
     *      Restricted to the contract owner.
     * @param _borrowingContract The address of the Borrowing contract.
     */
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
        return Math.mulDiv(poolBalance[_token], POOL_AVAILABILITY, PERCENTAGE_PRECISION);
    }

    /**
     * @notice Returns the identifier of a completed lending box.
     * @dev Accepts a 1-based box number and converts it to a zero-based
     *      array index before retrieving the identifier.
     * @param token The token associated with the lending box.
     * @param number The 1-based box number.
     * @return The unique identifier of the requested lending box.
     */
    function getBoxId(address token, uint256 number) public view zeroCheck(number) returns (bytes32) {
        --number;
        // uint256 _number = number - 1;

        return IDs[token][number];
    }

    /**
     * @notice Returns the current status of a lender's box contribution.
     * @dev Checks the pending status recorded for the specified box.
     * @param _id The identifier of the lending box.
     * @param _token The token associated with the lending box.
     * @return The status string of the lending contribution.
     */
    function getLendStatus(bytes32 _id, address _token) public view returns (string memory) {
        PendingBox[] storage box = pendingBoxes[_token][_id];

        uint256 index;
        for (uint256 i = 0; i < box.length; i++) {
            if (box[i].id == _id) {
                index = i;
                break;
            }
        }

        if (pendingBoxes[_token][_id][index].pending == false) {
            return "In Position";
        }
        return "Pending";
    }
}
