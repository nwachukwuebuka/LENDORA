// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import{LendingSetUp} from "test/helpers/LendingSetUp.sol";
import{Lending} from "src/Lending.sol";
import{console2} from "forge-std/Test.sol";
import{Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import{IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";


contract LendingTest is LendingSetUp{

    ///////////////////////////////////////////////////////
    ///    VARIABLES
    ///////////////////////////////////////////////////////
    uint256 lendAmount = 2 ether;

    
    ///////////////////////////////////////////////////////
    ///    UNIT
    ///////////////////////////////////////////////////////

    function testOracleIsZeroAddress() public{

        vm.expectRevert(
            Lending.Lending__OracleIsZeroAddress.selector
        );
        lend = new Lending(address(0));
    }


    function testOracleHasNoCode() public{
        vm.expectRevert(
            Lending.Lending__OracleContractHasNoCode.selector
        );
        lend = new Lending(address(0x1234));
    }

    function testLendAmountIsZero() public{
       

        vm.expectRevert(
            Lending.Lending__AmountCantBeZero.selector
        );

        lend.lend(0, address(wethToken));
    }

    function testLendWorks() public{
        aliceLendWeth(lendAmount);
        uint256 protocolBalance = IERC20(address(wethToken)).balanceOf(address(lend));
        assertEq(protocolBalance, lendAmount);
    }

    function testLendUnsupportedToken() public{
        
        vm.expectRevert(
            Lending.Lending__TokenNotSupported.selector
        );
        vm.prank(alice);
        lend.lend(lendAmount, address(0x1234));
    }

    function testDepositLessThanMinAmount() public{
        uint256 amountInUsd = 200e18;

        uint256 wethTokenAmount = oracle.usdWorthToTokenAmount(address(wethToken), amountInUsd);

        console2.log("Weth Token Amount:", wethTokenAmount);
        vm.expectRevert(
            Lending.Lending__LessThanMinimalAmount.selector
        );
        vm.prank(alice);
        lend.lend(wethTokenAmount, address(wethToken));


        uint256 tokenAmount = oracle.usdWorthToTokenAmount(address(usdcToken), amountInUsd);

        console2.log("Usdc Token Amount:", tokenAmount);
        vm.expectRevert(
            Lending.Lending__LessThanMinimalAmount.selector
        );
        vm.prank(alice);
        lend.lend(tokenAmount, address(usdcToken));
    }

    function testLendTimeStamp() public {
        aliceLendWeth(2e18);
        assertEq(
            lend.timeStampHolder(address(wethToken)),
            block.timestamp
        );


        aliceLendUsdc(2000e6);
        assertEq(
            lend.timeStampHolder(address(usdcToken)),
            block.timestamp
        );
    }


    function testCancelPositionWorks() public {
        uint256 amount = 2000e6;
        helperUsdc20deposit();
        address secondLender = address(2);

        // Get Alice's position ID
        (, bytes32 boxId,) = lend.lentPositions(alice, address(usdcToken), 0);

        vm.prank(alice);
        lend.cancelPosition(address(usdcToken), 1);

        // Check that Alice received her withdrawal credit
        uint256 balance = lend.neutralBalance(alice, address(usdcToken));
        assertGt(balance, 0);
        assertLe(balance, amount);

        // Check that Alice's position was removed
        vm.expectRevert();
        lend.lentPositions(alice, address(usdcToken), 0);

        // Check that Alice's entry was removed from the pending box
        (address firstLender,,,,,,) = lend.pendingBoxes(address(usdcToken), boxId, 0);
        assertEq(firstLender, secondLender);
    }

    function testCancelInvalidPosition() public{

        uint256 amount = 2000e18;

        for(uint256 i = 0; i < 20; i++){
            address lender = 
                        i == 0 ? alice : address(uint160(1 + i));
            wethToken.mint(lender, amount);

            vm.startPrank(lender);
            IERC20(wethToken).approve(address(lend), amount);
            lend.lend(amount, address(wethToken));
            vm.stopPrank();
        }

        vm.expectRevert(
            Lending.Lending__PositionDoesNotExist.selector
        );
        vm.prank(alice);
        lend.cancelPosition(address(wethToken), 2);
    }

    function testWithdrawWorks() public{
       
        uint256 amount = 2000e6;

        for(uint256 i = 0; i < 20; i++){
            address lender = 
                        i == 0 ? alice : address(uint160(1 + i));
            usdcToken.mint(lender, amount);

            vm.startPrank(lender);
            IERC20(usdcToken).approve(address(lend), amount);
            lend.lend(amount, address(usdcToken));
            vm.stopPrank();
        }

        uint256 expectedBalance = amount - Math.mulDiv(5, amount, 100);

        vm.prank(alice);
        lend.cancelPosition(address(usdcToken), 1);

        uint256 balance = lend.neutralBalance(alice, address(usdcToken));

        assertEq(balance, expectedBalance);

        uint256 protocolBalance = IERC20(usdcToken).balanceOf(address(lend));

        uint256 withdrawAmount = 5e6;
        vm.prank(alice);
        lend.withdraw(address(usdcToken), withdrawAmount);
        uint256 balanceAfter = lend.neutralBalance(alice, address(usdcToken));

        assertEq(
            balance - withdrawAmount, balanceAfter
        );

        uint256 protocolBalanceAfter = IERC20(usdcToken).balanceOf(address(lend));
        assertEq(protocolBalance - withdrawAmount, protocolBalanceAfter);


    }

    function testWithdrawMoreThanBalance() public{
       
        uint256 amount = 2000e6;

        for(uint256 i = 0; i < 20; i++){
            address lender = 
                        i == 0 ? alice : address(uint160(1 + i));
            usdcToken.mint(lender, amount);

            vm.startPrank(lender);
            IERC20(usdcToken).approve(address(lend), amount);
            lend.lend(amount, address(usdcToken));
            vm.stopPrank();
        }

        uint256 expectedBalance = amount - Math.mulDiv(5, amount, 100);

        vm.prank(alice);
        lend.cancelPosition(address(usdcToken), 1);

        // 1900e6
        uint256 balance = lend.neutralBalance(alice, address(usdcToken));

        assertEq(balance, expectedBalance);

        vm.expectRevert(
            Lending.Lending__InsufficientBalance.selector
        );
        vm.prank(alice);
        lend.withdraw(address(usdcToken), amount);
    }

    function testWIthdrawalMoreThan30percent() public{

        uint256 amount = 2000e6;

        for(uint256 i = 0; i < 20; i++){
            address lender = 
                        i == 0 ? alice : address(uint160(1 + i));
            usdcToken.mint(lender, amount);

            vm.startPrank(lender);
            IERC20(usdcToken).approve(address(lend), amount);
            lend.lend(amount, address(usdcToken));
            vm.stopPrank();
        }

        uint256 expectedBalance = amount - Math.mulDiv(5, amount, 100);

        vm.prank(alice);
        lend.cancelPosition(address(usdcToken), 1);

        uint256 balance = lend.neutralBalance(alice, address(usdcToken));

        assertEq(balance, expectedBalance);

        uint256 protocolBalance = IERC20(usdcToken).balanceOf(address(lend));
        uint256 aliceBalance = IERC20(usdcToken).balanceOf(address(alice));

        vm.prank(alice);
        // more than 30% of balance
        lend.withdraw(address(usdcToken), balance);
        

        // check protocol's accounting
        uint256 balanceAfter = lend.neutralBalance(alice, address(usdcToken));
        assertEq(balanceAfter, 0);

        // check that no money left the protocol
        uint256 protocolBalanceAfter = IERC20(usdcToken).balanceOf(address(lend));
        assertEq(protocolBalance, protocolBalanceAfter);

        // check balance of user
        uint256 aliceBalanceAfter = IERC20(usdcToken).balanceOf(address(alice));
        assertEq(aliceBalance, aliceBalanceAfter);

        // check that it has taken a pending withdrawal position
        uint256 length = lend.getPendWithdrawalLength(alice);
        (, uint256 requestTime,,) =
            lend.pendingWithdrawals(alice, length - 1);

        assertEq(requestTime, block.timestamp);
        
    }

    function testPendingWithdrawalWorks() public{

        uint256 amount = 2000e6;

        for(uint256 i = 0; i < 20; i++){
            address lender = 
                        i == 0 ? alice : address(uint160(1 + i));
            usdcToken.mint(lender, amount);

            vm.startPrank(lender);
            IERC20(usdcToken).approve(address(lend), amount);
            lend.lend(amount, address(usdcToken));
            vm.stopPrank();
        }

        uint256 expectedBalance = amount - Math.mulDiv(5, amount, 100);

        vm.prank(alice);
        lend.cancelPosition(address(usdcToken), 1);

        uint256 balance = lend.neutralBalance(alice, address(usdcToken));

        assertEq(balance, expectedBalance);

        uint256 protocolBalance = IERC20(usdcToken).balanceOf(address(lend));
        uint256 aliceBalance = IERC20(usdcToken).balanceOf(address(alice));

        vm.prank(alice);
        // more than 30% of balance
        lend.withdraw(address(usdcToken), balance);
        

        // check protocol's accounting
        uint256 balanceAfter = lend.neutralBalance(alice, address(usdcToken));
        assertEq(balanceAfter, 0);

        // check that no money left the protocol
        uint256 protocolBalanceAfter = IERC20(usdcToken).balanceOf(address(lend));
        assertEq(protocolBalance, protocolBalanceAfter);

        // check balance of user
        uint256 aliceBalanceAfter = IERC20(usdcToken).balanceOf(address(alice));
        assertEq(aliceBalance, aliceBalanceAfter);

        // check that it has taken a pending withdrawal position
        uint256 length = lend.getPendWithdrawalLength(alice);
        (, uint256 requestTime,,) =
            lend.pendingWithdrawals(alice, length - 1);

        assertEq(requestTime, block.timestamp);

        vm.warp(block.timestamp + 12 hours);

        vm.prank(alice);
        lend.processPendingWithdrawal(length);
        (,,,Lending.WithdrawalStatus status) =
            lend.pendingWithdrawals(alice, length - 1);

        assertTrue(
            status == Lending.WithdrawalStatus.completed
        );
        
    }

    function testCompletedPendingWithdrawal() public{

        uint256 amount = 2000e6;

        for(uint256 i = 0; i < 20; i++){
            address lender = 
                        i == 0 ? alice : address(uint160(1 + i));
            usdcToken.mint(lender, amount);

            vm.startPrank(lender);
            IERC20(usdcToken).approve(address(lend), amount);
            lend.lend(amount, address(usdcToken));
            vm.stopPrank();
        }

        uint256 expectedBalance = amount - Math.mulDiv(5, amount, 100);

        vm.prank(alice);
        lend.cancelPosition(address(usdcToken), 1);

        uint256 balance = lend.neutralBalance(alice, address(usdcToken));

        assertEq(balance, expectedBalance);

        uint256 protocolBalance = IERC20(usdcToken).balanceOf(address(lend));
        uint256 aliceBalance = IERC20(usdcToken).balanceOf(address(alice));

        vm.prank(alice);
        // more than 30% of balance
        lend.withdraw(address(usdcToken), balance);
        

        // check protocol's accounting
        uint256 balanceAfter = lend.neutralBalance(alice, address(usdcToken));
        assertEq(balanceAfter, 0);

        // check that no money left the protocol
        uint256 protocolBalanceAfter = IERC20(usdcToken).balanceOf(address(lend));
        assertEq(protocolBalance, protocolBalanceAfter);

        // check balance of user
        uint256 aliceBalanceAfter = IERC20(usdcToken).balanceOf(address(alice));
        assertEq(aliceBalance, aliceBalanceAfter);

        // check that it has taken a pending withdrawal position
        uint256 length = lend.getPendWithdrawalLength(alice);
        (, uint256 requestTime,,) =
            lend.pendingWithdrawals(alice, length - 1);

        assertEq(requestTime, block.timestamp);

        vm.warp(block.timestamp + 12 hours);
        vm.prank(alice);
        lend.processPendingWithdrawal(length);

        vm.warp(block.timestamp + 12 hours);
        vm.expectRevert(
            Lending.Lending__InvalidTransaction.selector
        );
        vm.prank(alice);
        lend.processPendingWithdrawal(length);
        
    }

    
    function testProcessPendingWithdrawalTimeNotUpto12() public{

        uint256 amount = 2000e6;

        helperUsdc20deposit();

        uint256 expectedBalance = amount - Math.mulDiv(5, amount, 100);

        vm.prank(alice);
        lend.cancelPosition(address(usdcToken), 1);

        uint256 balance = lend.neutralBalance(alice, address(usdcToken));

        assertEq(balance, expectedBalance);

        uint256 protocolBalance = IERC20(usdcToken).balanceOf(address(lend));
        uint256 aliceBalance = IERC20(usdcToken).balanceOf(address(alice));

        vm.prank(alice);
        // more than 30% of balance
        lend.withdraw(address(usdcToken), balance);
        

        // check protocol's accounting
        uint256 balanceAfter = lend.neutralBalance(alice, address(usdcToken));
        assertEq(balanceAfter, 0);

        // check that no money left the protocol
        uint256 protocolBalanceAfter = IERC20(usdcToken).balanceOf(address(lend));
        assertEq(protocolBalance, protocolBalanceAfter);

        // check balance of user
        uint256 aliceBalanceAfter = IERC20(usdcToken).balanceOf(address(alice));
        assertEq(aliceBalance, aliceBalanceAfter);

        // check that it has taken a pending withdrawal position
        uint256 length = lend.getPendWithdrawalLength(alice);
        (, uint256 requestTime,,) =
            lend.pendingWithdrawals(alice, length - 1);

        assertEq(requestTime, block.timestamp);

        vm.expectRevert(
            Lending.Lending__TransactionPending.selector
        );
        vm.prank(alice);
        lend.processPendingWithdrawal(length);
    }
    
    function testReleaseZeroTokens() public{
        helperWeth20deposit();
    
        vm.expectRevert(
            Lending.Lending__AmountCantBeZero.selector
        );
        vm.prank(address(borrow));
        lend.releaseBorrowedTokens(address(wethToken), alice, 0);
    }

    function testOnlyBorrowContractReleaseTokens() public{

        vm.expectRevert(
            Lending.Lending__NotBorrowingContract.selector
        );
        vm.prank(alice);
        lend.releaseBorrowedTokens(address(wethToken), address(1), 2 ether);

    }

    function testNoLendingBox() public{

        uint256 index = lend.borrowBoxIndex(address(wethToken));
        uint256 length = lend.getIDsLength(address(wethToken));

        assertTrue(index >= length);


        vm.expectRevert(
            Lending.Lending__LendingBoxDoesNotExist.selector
        );
        vm.prank(address(borrow));
        lend.releaseBorrowedTokens(address(wethToken), bob, 2 ether);

    }

    function testNextBoxAfterCurrentBox() public{
        
    }

}