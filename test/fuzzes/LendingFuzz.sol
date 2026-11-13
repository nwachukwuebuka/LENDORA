// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import{console2} from "forge-std/Test.sol";
import{LendingSetUp} from "test/helpers/LendingSetUp.sol";
import{Lending} from "src/Lending.sol";
import{IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import{Math} from "@openzeppelin/contracts/utils/math/Math.sol";


contract LendingFuzz is LendingSetUp{

    ///////////////////////////////////////////////////////
    ///    FUZZ
    ///////////////////////////////////////////////////////

    function testFuzzOracleHasNoCode(address _fakeOracle) public {
        vm.assume(_fakeOracle != address(0));
        vm.assume(_fakeOracle.code.length == 0);

        vm.expectRevert(
            Lending.Lending__OracleContractHasNoCode.selector
        );

        new Lending(_fakeOracle);
    }

    function testFuzzLendWorks(uint256 amount) public{
        vm.assume(amount > 1000e18 && amount < 100_000e18);

        aliceLendWeth(amount);
        uint256 protocolBalance = IERC20(address(wethToken)).balanceOf(address(lend));
        assertEq(protocolBalance, amount);
    }

    function testFuzzLendUnsupportedToken(address token) public{
        uint256 lendAmount = 2 ether;
        vm.assume(token != address(0) &&
                    token != address(wethToken) &&
                    token != address(usdcToken)
        );
        
        vm.expectRevert(
            Lending.Lending__TokenNotSupported.selector
        );
        vm.prank(alice);
        lend.lend(lendAmount, token);
    }

    function testFuzzDepositLessThanMinAmount(uint256 amountInUsd) public{
        amountInUsd = bound(amountInUsd, 1e18, 999e18);
        
        uint256 wethTokenAmount = oracle.usdWorthToTokenAmount(address(wethToken), amountInUsd);
        wethToken.mint(alice, wethTokenAmount);
        vm.prank(alice);
        IERC20(address(wethToken)).approve(address(lend), wethTokenAmount);


        console2.log("Weth Token Amount:", wethTokenAmount);
        vm.expectRevert(
            Lending.Lending__LessThanMinimalAmount.selector
        );
        vm.prank(alice);
        lend.lend(wethTokenAmount, address(wethToken));


        //USDC
        uint256 usdcAmountToMint = oracle.usdWorthToTokenAmount(address(usdcToken), amountInUsd);
        usdcToken.mint(alice, usdcAmountToMint);
        vm.prank(alice);
        IERC20(address(usdcToken)).approve(address(lend), usdcAmountToMint);

        console2.log("Usdc Token Amount:", usdcAmountToMint);
        vm.expectRevert(
            Lending.Lending__LessThanMinimalAmount.selector
        );
        vm.prank(alice);
        lend.lend(usdcAmountToMint, address(usdcToken));
    }
    function testFuzzCancelPositionWorks(uint256 amount) public {
        vm.assume(amount >= 1000e18 && amount < 100_000e18);
        address secondLender = address(101);

        // Fill the box with 20 lenders
        for (uint256 i = 0; i < 20; i++) {
            address lender = i == 0
                ? alice
                : address(uint160(100 + i));

            usdcToken.mint(lender, amount);

            vm.startPrank(lender);
            usdcToken.approve(address(lend), amount);
            lend.lend(amount, address(usdcToken));
            vm.stopPrank();
        }

        // Get Alice's position ID
        (, bytes32 boxId,) = lend.lentPositions(
            alice,
            address(usdcToken),
            0
        );

        // Alice cancels position 1
        vm.prank(alice);
        lend.cancelPosition(address(usdcToken), 1);

        // Check that Alice received her withdrawal credit
        uint256 balance = lend.neutralBalance(
            alice,
            address(usdcToken)
        );

        assertGt(balance, 0);
        assertLe(balance, amount);

        // Check that Alice's position was removed
        vm.expectRevert();
        lend.lentPositions(alice, address(usdcToken), 0);

        // Check that Alice's entry was removed from the pending box
        (address firstLender,,,,,,) = lend.pendingBoxes(
            address(usdcToken),
            boxId,
            0
        );

        assertEq(firstLender, secondLender);
    }
    function testFuzzCancelInvalidPosition(uint256 position) public{
        position = bound(position, 2, 255);

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
        lend.cancelPosition(address(wethToken), uint256(position));
    }
    function testFuzzWithdrawMoreThanBalance(uint256 amount) public{
        amount = bound(amount, 1000e6, 100_000e6);

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

        // 1900e18
        uint256 balance = lend.neutralBalance(alice, address(usdcToken));

        assertEq(balance, expectedBalance);

        vm.expectRevert(
            Lending.Lending__InsufficientBalance.selector
        );
        vm.prank(alice);
        lend.withdraw(address(usdcToken), amount);

    }
    function testFuzzProcessPendingWithdrawalTimeNotUpto12(uint256 time) public{
        vm.assume(time < 12 hours);

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

        vm.warp(time);

        vm.expectRevert(
            Lending.Lending__TransactionPending.selector
        );
        vm.prank(alice);
        lend.processPendingWithdrawal(length);
    }
}