// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {MockStHype} from "../mocks/MockStHype.sol";
import {Test,console} from "forge-std/Test.sol";
import {MockOverseer} from "../mocks/MockOverseer.sol";
import {MockWHype} from "../mocks/MockWHype.sol";
import {MockWstHype} from "../mocks/MockWstHype.sol";
import {MockMorpho,INTEREST_RATE,SECONDS_PER_YEAR} from "../mocks/MockMorpho.sol";

uint256 constant WAD = 1e18;

import {MathLib} from "../../src/libraries/MathLib.sol";
import {SharesMathLib} from "../../src/libraries/SharesMathLib.sol";
import {MarketParamsLib} from "../../src/libraries/MarketParamsLib.sol";
import {
    Id,
    IMorphoStaticTyping,
    IMorphoBase,
    MarketParams,
    Position,
    Market,
    Authorization,
    Signature
} from "../../src/interfaces/IMorpho.sol";

contract Mocks_Whype_Morpho_Test is Test{

    using SharesMathLib for uint256;
    using MathLib for uint256;

    MockStHype public stHype;
    MockOverseer public overseer;
    MockWHype public wHype;
    MockWstHype public wstHype;
    MockMorpho public morpho;
    address bob;
    address alice;
    address harry;
    uint256 constant INITIAL_STAKE = 10e18;

    Id public constant MARKET_ID = Id.wrap(0xe9a9bb9ed3cc53f4ee9da4eea0370c2c566873d5de807e16559a99907c9ae227);

    MarketParams public marketParams;

    function setUp() external{
        stHype = new MockStHype();
        overseer = new MockOverseer(address(stHype));
        wHype = new MockWHype();
        deal(address(overseer), 10000 ether);
        stHype.setOverseer(address(overseer));
        wstHype = new MockWstHype(address(stHype));
        stHype.setWstHype(address(wstHype));

        morpho = new MockMorpho(
            address(wHype),
            address(wstHype)
        );
        uint256 fundAmount = 1000 ether;
        deal(address(wHype),address(this), fundAmount);
        wHype.approve(address(morpho), fundAmount);
        wHype.transfer(address(morpho), fundAmount);

        (address loan,address collat ,address oracle ,address irm ,uint256 lltv) = morpho.idToMarketParams(MARKET_ID);
        marketParams = MarketParams(
            loan,
            collat,
            oracle,
            irm,
            lltv
        );

        bob = makeAddr("bob");
        alice = makeAddr("alice");
        harry = makeAddr("harry");
    }

    /*//////////////////////////////////////////////////////////////
                                WHype
    //////////////////////////////////////////////////////////////*/

    function testWrap() public{
        // address bob = makeAddr("bob");
        // address charlie = makeAddr("charlie");
        deal(alice, 10 ether);
        vm.prank(alice);
        wHype.deposit{value : 10 ether}();
        assertEq(wHype.balanceOf(alice), 10 ether);
    }

    function testUnwrap() public{
        deal(bob, 10 ether);
        vm.prank(bob);
        wHype.deposit{value : 10 ether}();
        assertEq(wHype.balanceOf(bob), 10 ether);

        vm.prank(bob);
        wHype.withdraw(6 ether);

        assertEq(wHype.balanceOf(bob), 4 ether);
        assertEq(bob.balance, 6 ether);
    }

    function testTransfer() public {
        uint256 depositAmount = 8 ether;
        uint256 transferAmount = 3 ether;
        deal(alice, depositAmount);
        
        // Alice deposits
        vm.prank(alice);
        wHype.deposit{value: depositAmount}();
        
        // Alice transfers to Bob
        vm.prank(alice);
        bool success = wHype.transfer(bob, transferAmount);
        
        assertTrue(success);
        
        // Check balances
        assertEq(wHype.balanceOf(alice), depositAmount - transferAmount);
        assertEq(wHype.balanceOf(bob), transferAmount);
        
        // Total supply should remain the same
        assertEq(wHype.totalSupply(), depositAmount);
    }

    function testApprovalAndTransferFrom_wHype() public {

        address charlie = makeAddr("charlie");
        uint256 depositAmount = 12 ether;
        uint256 approvalAmount = 5 ether;
        uint256 transferAmount = 3 ether;
        deal(alice, depositAmount);
        
        // Alice deposits
        vm.prank(alice);
        wHype.deposit{value: depositAmount}();
        
        // Alice approves Bob
        vm.prank(alice);
        bool approveSuccess = wHype.approve(bob, approvalAmount);
        assertTrue(approveSuccess);
        
        // Check allowance
        assertEq(wHype.allowance(alice, bob), approvalAmount);
        
        // Bob transfers from Alice to Charlie
        vm.prank(bob);
        bool transferSuccess = wHype.transferFrom(alice, charlie, transferAmount);
        assertTrue(transferSuccess);
        
        // Check balances
        assertEq(wHype.balanceOf(alice), depositAmount - transferAmount);
        assertEq(wHype.balanceOf(charlie), transferAmount);
        
        // Check allowance decreased
        assertEq(wHype.allowance(alice, bob), approvalAmount - transferAmount);
        
        // Test insufficient allowance
        vm.prank(bob);
        vm.expectRevert("ERC20: insufficient allowance");
        wHype.transferFrom(alice, charlie, approvalAmount); // More than remaining allowance
    }
    
    /*//////////////////////////////////////////////////////////////
                                MORPHO
    //////////////////////////////////////////////////////////////*/

    function testBorrowFailsWithoutCollateral() public{
        vm.expectRevert("Unhealthy position");
        morpho.borrow(
            marketParams,
            1e18,
            0,
            address(this),
            address(this)
        );
    }

    function testSupplyCollateralWorks() public {

        // VERY IMP test ❗️❗️❗️❗️❗️❗️❗️❗️ // crucial to understand the approvals

        uint256 supplyAmount = 10e18;
        // deal(address(stHype), bob, supplyAmount);
        deal(bob, supplyAmount);
        vm.startPrank(bob);
        overseer.mint{value : supplyAmount}(bob,"");
        uint256 initialBalance = wstHype.balanceOf(bob);
        wstHype.approve(address(morpho), supplyAmount); // to allow morpho to call wstHype.transfer
        morpho.supplyCollateral(
            marketParams,
            supplyAmount,
            bob,
            ""
        );
        vm.stopPrank();

        uint256 finalBalance = wstHype.balanceOf(bob);

        (uint256 supplyShares, uint128 borrowShares, uint128 collateral) = morpho.position(MARKET_ID, bob);
        assert(supplyShares == 0);
        assert(borrowShares == 0);
        assert(collateral == uint128(supplyAmount));
        assert(initialBalance - finalBalance == supplyAmount);
    }

    modifier bobSupplyCollat(uint256 amount){
        deal(bob, amount);
        vm.startPrank(bob);
        overseer.mint{value : amount}(bob,"");
        wstHype.approve(address(morpho), amount);
        morpho.supplyCollateral(
            marketParams,
            amount,
            bob,
            ""
        );
        vm.stopPrank();
        _;
    }

    modifier bobBorrows(uint256 amount) {
        vm.startPrank(bob);
        morpho.borrow(
            marketParams,
            amount,
            0,
            bob,
            bob
        );   
        vm.stopPrank();
        _;
    }

    function testBorrowWorks() public bobSupplyCollat(10e18){
        uint256 collatAmount = 10e18;
        uint256 borrowAmount = (collatAmount*8)/10; // 80%

        (,
        ,
        uint128 initialtotalBorrowAssets,
        uint128 initialtotalBorrowShares,
        ,
        ) = morpho.market(MARKET_ID);

        uint256 initialBalance = wHype.balanceOf(bob);

        vm.startPrank(bob);
        morpho.borrow(
            marketParams,
            borrowAmount,
            0,
            bob,
            bob
        );   
        vm.stopPrank();

        uint256 finalBalance = wHype.balanceOf(bob);

        // now check 2 state changes - position and market

        (,
        ,
        uint128 finaltotalBorrowAssets,
        uint128 finaltotalBorrowShares,
        ,
        ) = morpho.market(MARKET_ID);

        (uint256 supplyShares, uint128 borrowShares, uint128 collateral) = morpho.position(MARKET_ID, bob);
        assert(supplyShares == 0);
        assert(borrowShares == borrowAmount.toSharesUp(initialtotalBorrowAssets,initialtotalBorrowShares));
        // console.log("borrow shares : ", borrowShares); // 8000000000000000000000000
        assert(collateral == collatAmount);

        assert(initialtotalBorrowAssets == 0);
        assert(initialtotalBorrowShares == 0);
        assert(finaltotalBorrowAssets == borrowAmount);
        assert(finaltotalBorrowShares == borrowShares);
        assert(finalBalance - initialBalance == borrowAmount);
    }

    function testBorrowRevertsForUnhealthy() public bobSupplyCollat(10e18){
        uint256 collatAmount = 10e18;
        uint256 borrowAmount = (collatAmount*9)/10; // 90%
        vm.startPrank(bob);
        vm.expectRevert("Unhealthy position");
        morpho.borrow(
            marketParams,
            borrowAmount,
            0,
            bob,
            bob
        );   
        vm.stopPrank();
    }

    // in the following test I have seen visually(by logging) how borrowAssets gains interest. no other use of this test

    // function testBorrowGainsInterest() public bobSupplyCollat(10e18) bobBorrows(8e18){
    //     uint256 collatAmount = 10e18;
    //     uint256 initialBorrowAmount = 8e18;
    //     vm.warp(block.timestamp + 1 days);
    //     morpho.accrueInterest(MARKET_ID);
    //     (,
    //     ,
    //     uint128 totalBorrowAssets,
    //     uint128 totalBorrowShares,
    //     ,
    //     ) = morpho.market(MARKET_ID);
    //     (, uint128 borrowShares,) = morpho.position(MARKET_ID, bob);
    //     // console.log("totalBorrowAssets : ", totalBorrowAssets);
    //     // assert(totalBorrowAssets == expectedBorrowAssets);
    //     // assert(totalBorrowShares == initialBorrowAmount); // we tested in the last to last test that the borrow shares for the first borrow is the same as borrow amount. this test is to show that shares dont increase
    //     assert(totalBorrowShares == borrowShares);
    //     // uint256 expectedInterestGain = initialBorrowAmount.wTaylorCompounded()
    // }

    function testRepayUsingAssets() public bobSupplyCollat(10e18) bobBorrows(8e18){
        // uint256 collatAmount = 10e18;
        uint256 initialBorrowAmount = 8e18;
        uint256 elapsed = 5 days;
        vm.warp(block.timestamp + elapsed);


        // uint256 expectedInterest = initialBorrowAmount.wMulDown(INTEREST_RATE.wTaylorCompounded(elapsed)); // 2190093115069656 == 2e15 (for 5 days)
        // uint256 expectedInterest = overseer.currentValueOf(bob) - initialBorrowAmount;
        // uint256 expectedInterest = initialBorrowAmount

        uint256 interestRate = (INTEREST_RATE * elapsed) / (SECONDS_PER_YEAR);
        uint256 expectedInterest = (initialBorrowAmount * interestRate) / 100;

        // deal(address(wHype), bob, expectedInterest);
        deal(address(wHype), bob, wHype.balanceOf(bob) + expectedInterest);


        // console.log("expectedInterest : ", expectedInterest); 
        // console.log("Total amount : ", initialBorrowAmount + expectedInterest);
        // console.log("bob wHype balance : ", wHype.balanceOf(bob));


        uint256 repayAmount = initialBorrowAmount + expectedInterest;
        uint256 initialWHypeBalance = wHype.balanceOf(bob);
        vm.startPrank(bob);
        wHype.approve(address(morpho), repayAmount);
        morpho.repay(
            marketParams,
            repayAmount,
            0,
            bob,
            ""
        );
        vm.stopPrank();
        uint256 finalWHypeBalance = wHype.balanceOf(bob);

        (,
        ,
        ,
        uint128 totalBorrowShares,
        ,
        ) = morpho.market(MARKET_ID);
        (, uint128 borrowShares,) = morpho.position(MARKET_ID, bob);

        assertApproxEqAbs(initialWHypeBalance - finalWHypeBalance , repayAmount, 1e5); // some error in rounding can come, here difference was `1` , but I used `1e5` just to be safe 
        // console.log("initialWHypeBalance - finalWHypeBalance : ", initialWHypeBalance - finalWHypeBalance);
        // console.log("repayAmount : ", repayAmount);
        // assert(totalBorrowAssets == 0);
        assert(totalBorrowShares == 0);
        assert(borrowShares == 0);
        // console.log("borrowShares : ", borrowShares);
        // console.log("totalBorrowAssets : ", totalBorrowAssets);

        // HERE, due to rounding issues, `1` borrowAsset is left(since we round down) in the protocol but shares are reduced to zero
    }

    function testRepayUsingShares() public bobSupplyCollat(10e18) bobBorrows(8e18){
        // uint256 collatAmount = 10e18;
        uint256 initialBorrowAmount = 8e18;
        uint256 elapsed = 5 days;
        vm.warp(block.timestamp + elapsed);

        // uint256 expectedInterest = initialBorrowAmount.wMulDown(INTEREST_RATE.wTaylorCompounded(elapsed)); // 2190093115069656 == 2e15 (for 5 days)
        uint256 interestRate = (INTEREST_RATE * elapsed) / (SECONDS_PER_YEAR);
        uint256 expectedInterest = (initialBorrowAmount * interestRate) / 100;
        // deal(address(wHype), bob, expectedInterest);
        deal(address(wHype), bob, wHype.balanceOf(bob) + expectedInterest);

        uint256 repayAmount = initialBorrowAmount + expectedInterest;
        uint256 initialWHypeBalance = wHype.balanceOf(bob);
        vm.startPrank(bob);
        wHype.approve(address(morpho), repayAmount);
        morpho.repay(
            marketParams,
            0,
            initialBorrowAmount * 10**6, // initial borrow shares are mathematically equal to borrow amount , scaled upto 6 more decimals
            // IMP ❗️❗️❗️❗️❗️❗️❗️❗️❗️❗️ - decimals
            bob,
            ""
        );
        vm.stopPrank();
        uint256 finalWHypeBalance = wHype.balanceOf(bob);

        (,
        ,
        uint128 totalBorrowAssets,
        uint128 totalBorrowShares,
        ,
        ) = morpho.market(MARKET_ID);
        (, uint128 borrowShares,) = morpho.position(MARKET_ID, bob);
        assertApproxEqAbs(initialWHypeBalance - finalWHypeBalance , repayAmount, 1e5);
        assert(totalBorrowShares == 0);
        assert(borrowShares == 0);
        assert(totalBorrowAssets == 0);

        // clearly if you wanna withdraw full amount, you should use this `shares` method
    }

    function testWithdrawCollat() public bobSupplyCollat(10e18){
        uint256 collatAmount = 10e18;
        vm.startPrank(bob);
        morpho.withdrawCollateral(
            marketParams,
            collatAmount,
            bob,
            bob
        );
        vm.stopPrank();
    }

    // 3322058826
    // 633620772 

}