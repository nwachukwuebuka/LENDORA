// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


///////////////////////////////////////////////////////
///    IMPORTS
///////////////////////////////////////////////////////
import{Test} from "forge-std/Test.sol";
import{Lending} from "src/Lending.sol";
import{PriceFeedOracle} from "src/PriceFeedOracle.sol";
import{ERC20Mock} from "test/mocks/ERC20Mock.sol";
import{MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import{IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import{Borrowing} from "src/Borrowing.sol";

abstract contract LendingSetUp is Test{

    ///////////////////////////////////////////////////////
    ///    VARIABLES
    ///////////////////////////////////////////////////////
    Lending lend;
    Borrowing borrow;
    PriceFeedOracle oracle;
    ERC20Mock wethToken;
    ERC20Mock usdcToken;
    MockV3Aggregator ethPriceFeed;
    MockV3Aggregator usdcPriceFeed;

    address alice;
    address bob;


    function setUp() public virtual{

        wethToken = new ERC20Mock("WethToken", "WETH", 18);
        usdcToken = new ERC20Mock("UsdcToken", "USDC", 6);

        ethPriceFeed = new MockV3Aggregator(8, 2000e8);
        usdcPriceFeed = new MockV3Aggregator(8, 1e8);

        oracle = new PriceFeedOracle(address(usdcToken), address(usdcPriceFeed), address(wethToken), address(ethPriceFeed));

        lend = new Lending(address(oracle));
        borrow = new Borrowing(address(lend), address(oracle));
        lend.setBorrowingContract(address(borrow));

        alice = makeAddr("alice");
        bob = makeAddr("bob");
    }

    ///////////////////////////////////////////////////////
    ///    HELPERS
    ///////////////////////////////////////////////////////


    function helperUsdc20deposit() internal{
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
    }
    function helperWeth20deposit() internal{
        uint256 amount = 20e18;

        for(uint256 i = 0; i < 20; i++){
            address lender = 
                        i == 0 ? alice : address(uint160(1 + i));
            wethToken.mint(lender, amount);

            vm.startPrank(lender);
            IERC20(wethToken).approve(address(lend), amount);
            lend.lend(amount, address(wethToken));
            vm.stopPrank();
        }
    }

    function aliceLendWeth(uint256 amount) internal{
        wethToken.mint(alice, amount);

        vm.startPrank(alice);
        IERC20(address(wethToken)).approve(address(lend), amount);
        lend.lend(amount, address(wethToken));
        vm.stopPrank();

    }

    function aliceLendUsdc(uint256 amount) internal {
        usdcToken.mint(alice, amount);

        vm.startPrank(alice);
        IERC20(address(usdcToken)).approve(address(lend), amount);
        lend.lend(amount, address(usdcToken));
        vm.stopPrank();

    }
}