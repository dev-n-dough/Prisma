// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {MockStHype} from "../mocks/MockStHype.sol";
import {MockOverseer} from "../mocks/MockOverseer.sol";
import {MockWstHype} from "../mocks/MockWstHype.sol";

contract Mocks_stHype_wstHype_overseer_Tests is Test {
    MockStHype public stHype;
    MockOverseer public overseer;
    MockWstHype public wstHype;
    
    address public alice;
    address public bob;
    address public charlie;
    
    function setUp() external {
        stHype = new MockStHype();
        overseer = new MockOverseer(address(stHype));
        wstHype = new MockWstHype(address(stHype));
        
        stHype.setOverseer(address(overseer));
        stHype.setWstHype(address(wstHype));
        
        deal(address(overseer), 100000 ether);
        
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
    }
    
    function test1_BasicStaking() public {
        console.log("\n=== Test 1: Basic Staking ===");
        
        deal(alice, 10 ether);
        vm.prank(alice);
        overseer.mint{value: 10 ether}(alice, "");
        
        // Check balances
        assertEq(stHype.balanceOf(alice), 10e18);
        assertEq(wstHype.balanceOf(alice), 10e18);
        
        // Check shares (stHYPE uses 24 decimals internally)
        assertEq(stHype.sharesOf(alice), 10e18 * 1e6); // 24 decimals
        assertEq(wstHype.sharesOf(alice), 10e18 * 1e6); // Same shares
        
        console.log("Initial staking successful");
        console.log("stHYPE balance:", stHype.balanceOf(alice));
        console.log("wstHYPE balance:", wstHype.balanceOf(alice));
        console.log("Shares:", stHype.sharesOf(alice));
    }
    
    function test2_RebasingMakesStHypeBalanceGrow() public {
        console.log("\n=== Test 2: Rebasing Makes stHYPE Balance Grow ===");
        
        // Alice stakes
        deal(alice, 20 ether);
        vm.prank(alice);
        overseer.mint{value: 20 ether}(alice, "");
        
        uint256 stHypeBalanceBefore = stHype.balanceOf(alice);
        uint256 wstHypeBalanceBefore = wstHype.balanceOf(alice);
        uint256 sharesBefore = stHype.sharesOf(alice);
        
        console.log("Before rebase:");
        console.log("  stHYPE balance:", stHypeBalanceBefore);
        console.log("  wstHYPE balance:", wstHypeBalanceBefore);
        console.log("  Shares:", sharesBefore);
        
        // Manually trigger rebase with 1 ETH rewards
        stHype.rebase(1 ether);
        
        uint256 stHypeBalanceAfter = stHype.balanceOf(alice);
        uint256 wstHypeBalanceAfter = wstHype.balanceOf(alice);
        uint256 sharesAfter = stHype.sharesOf(alice);
        
        console.log("After 1 ETH rebase:");
        console.log("  stHYPE balance:", stHypeBalanceAfter);
        console.log("  wstHYPE balance:", wstHypeBalanceAfter);
        console.log("  Shares:", sharesAfter);
        
        // stHYPE balance should increase
        assertGt(stHypeBalanceAfter, stHypeBalanceBefore);
        assertEq(stHypeBalanceAfter, 21e18); // 20 + 1 ETH reward
        
        // wstHYPE balance should stay the same
        assertEq(wstHypeBalanceAfter, wstHypeBalanceBefore);
        assertEq(wstHypeBalanceAfter, 20e18); // Unchanged
        
        // Shares should stay the same for both
        assertEq(sharesAfter, sharesBefore);
        
        console.log("Rebasing works correctly");
    }
    
    function test3_AutomaticRebasingOnInteraction() public {
        console.log("\n=== Test 3: Automatic Rebasing on Interaction ===");
        
        deal(alice, 15 ether);
        vm.prank(alice);
        overseer.mint{value: 15 ether}(alice, "");
        
        // Wait some time (simulate rewards accumulating)
        vm.warp(block.timestamp + 30 days);
        
        uint256 balanceBefore = stHype.balanceOf(alice);
        console.log("Balance before interaction:", balanceBefore);
        
        // Any interaction should trigger rebase 
        deal(bob, 5 ether);
        vm.prank(bob);
        overseer.mint{value: 5 ether}(bob, "");
        
        uint256 aliceBalanceAfter = stHype.balanceOf(alice);
        uint256 bobBalance = stHype.balanceOf(bob);
        
        console.log("Alice balance after auto-rebase:", aliceBalanceAfter);
        console.log("Bob balance:", bobBalance);
        
        // Alice's balance should have increased due to automatic rebase
        assertGt(aliceBalanceAfter, balanceBefore);
        assertApproxEqAbs(bobBalance, 5e18, 100); // rounding issues
        
        console.log("Automatic rebasing on interaction works");
    }
    
    function test4_ExchangeRateGrowth() public {
        console.log("\n=== Test 4: Exchange Rate Growth ===");
        
        deal(alice, 10 ether);
        vm.prank(alice);
        overseer.mint{value: 10 ether}(alice, "");
        
        uint256 initialRate = wstHype.stHypePerToken();
        console.log("Initial exchange rate (stHYPE per wstHYPE):", initialRate);
        
        // Add 2 ETH rewards via rebase
        stHype.rebase(2 ether);
        
        uint256 newRate = wstHype.stHypePerToken();
        console.log("Rate after rebase:", newRate);
        
        // Exchange rate should increase
        assertGt(newRate, initialRate);
        assertEq(newRate, 1.2e18); // 12 stHYPE / 10 wstHYPE = 1.2 
        
        // Check conversion functions
        uint256 stHypeFor1Wst = wstHype.getStHypeByWstHype(1e18);
        uint256 wstFor1StHype = wstHype.getWstHypeByStHype(1e18);
        
        console.log("1 wstHYPE equals", stHypeFor1Wst, "stHYPE");
        console.log("1 stHYPE equals", wstFor1StHype, "wstHYPE");
        
        assertEq(stHypeFor1Wst, 1.2e18);
        assertApproxEqRel(wstFor1StHype, 0.833333333333333333e18, 0.01e18); // 1/1.2
        
        console.log("Exchange rate growth works correctly");
    }
    
    function test5_MultipleUsersRebasingFairness() public {
        console.log("\n=== Test 5: Multiple Users Rebasing Fairness ===");
        
        // Alice stakes first
        deal(alice, 30 ether);
        vm.prank(alice);
        overseer.mint{value: 30 ether}(alice, "");
        
        // Bob stakes later
        deal(bob, 20 ether);
        vm.prank(bob);
        overseer.mint{value: 20 ether}(bob, "");
        
        console.log("Before rebase:");
        console.log("  Alice stHYPE:", stHype.balanceOf(alice));
        console.log("  Bob stHYPE:", stHype.balanceOf(bob));
        console.log("  Total supply:", stHype.totalSupply());
        
        // Add 5 ETH rewards
        stHype.rebase(5 ether);
        
        console.log("After 5 ETH rebase:");
        console.log("  Alice stHYPE:", stHype.balanceOf(alice));
        console.log("  Bob stHYPE:", stHype.balanceOf(bob));
        console.log("  Total supply:", stHype.totalSupply());
        
        // Check proportional rewards
        uint256 aliceBalance = stHype.balanceOf(alice);
        uint256 bobBalance = stHype.balanceOf(bob);
        uint256 totalBalance = stHype.totalSupply();
        
        // Alice should get 30/50 of rewards, Bob should get 20/50
        uint256 expectedAlice = 30e18 + (5e18 * 30) / 50; // 30 + 3 = 33
        uint256 expectedBob = 20e18 + (5e18 * 20) / 50;   // 20 + 2 = 22
        
        assertEq(aliceBalance, expectedAlice);
        assertEq(bobBalance, expectedBob);
        assertEq(totalBalance, 55e18); // 50 + 5
        
        console.log("Proportional rewards distribution works");
    }
    
    function test6_TransferMaintainsRebasing() public {
        console.log("\n=== Test 6: Transfer Maintains Rebasing ===");
        
        deal(alice, 20 ether);
        vm.prank(alice);
        overseer.mint{value: 20 ether}(alice, "");
        
        // Add rewards first
        stHype.rebase(4 ether); // Alice now has 24 stHYPE
        
        uint256 aliceBalanceBefore = stHype.balanceOf(alice);
        assertApproxEqAbs(aliceBalanceBefore, 24e18, 100);
        
        // Alice transfers 10 stHYPE to Bob
        vm.prank(alice);
        stHype.transfer(bob, 10e18);
        
        console.log("After transfer:");
        console.log("  Alice stHYPE:", stHype.balanceOf(alice));
        console.log("  Bob stHYPE:", stHype.balanceOf(bob));
        
        assertApproxEqAbs(stHype.balanceOf(alice), 14e18, 100);
        assertApproxEqAbs(stHype.balanceOf(bob), 10e18, 100);
        
        // Add more rewards - both should benefit proportionally
        stHype.rebase(2.4 ether); // 10% more
        
        console.log("After second rebase:");
        console.log("  Alice stHYPE:", stHype.balanceOf(alice));
        console.log("  Bob stHYPE:", stHype.balanceOf(bob));
        
        // Both should have 10% more
        assertApproxEqAbs(stHype.balanceOf(alice), 15.4e18, 0.01e18);
        assertApproxEqAbs(stHype.balanceOf(bob), 11e18, 0.01e18);
        
        console.log("Transfer maintains rebasing correctly");
    }
    
    function test7_WstHypeTransferDoesNotAffectBalance() public {
        console.log("\n=== Test 7: wstHYPE Transfer Does Not Affect Balance ===");
        
        deal(alice, 25 ether);
        vm.prank(alice);
        overseer.mint{value: 25 ether}(alice, "");
        
        // Add rewards to increase exchange rate
        stHype.rebase(5 ether);
        
        uint256 wstBalanceBefore = wstHype.balanceOf(alice);
        uint256 stHypeBalanceBefore = stHype.balanceOf(alice);
        
        console.log("Before wstHYPE transfer:");
        console.log("  Alice wstHYPE:", wstBalanceBefore);
        console.log("  Alice stHYPE:", stHypeBalanceBefore);
        console.log("  Exchange rate:", wstHype.stHypePerToken());
        
        // Alice transfers 10 wstHYPE to Bob
        vm.prank(alice);
        wstHype.transfer(bob, 10e18);
        
        console.log("After wstHYPE transfer:");
        console.log("  Alice wstHYPE:", wstHype.balanceOf(alice));
        console.log("  Bob wstHYPE:", wstHype.balanceOf(bob));
        console.log("  Alice stHYPE:", stHype.balanceOf(alice));
        console.log("  Bob stHYPE:", stHype.balanceOf(bob));
        
        // wstHYPE balances should change as expected
        assertEq(wstHype.balanceOf(alice), 15e18);
        assertEq(wstHype.balanceOf(bob), 10e18);
        
        // But they should still benefit from rebasing equally
        stHype.rebase(3 ether); // 10% more rewards
        
        console.log("After rebase:");
        console.log("  Alice stHYPE:", stHype.balanceOf(alice));
        console.log("  Bob stHYPE:", stHype.balanceOf(bob));
        
        console.log("wstHYPE transfers work correctly");
    }
    
    function test8_UnstakingWithRewards() public {
        // Note : local testing involves native transfers of eth rather than hype lol

        console.log("\n=== Test 8: Unstaking with Rewards ===");
        
        deal(alice, 30 ether);
        vm.prank(alice);
        overseer.mint{value: 30 ether}(alice, "");
        
        // Simulate time passing with automatic rebase
        vm.warp(block.timestamp + 365 days);
        
        // Stake someone else to trigger rebase
        deal(bob, 1 ether);
        vm.prank(bob);
        overseer.mint{value: 1 ether}(bob, "");
        
        uint256 aliceBalance = stHype.balanceOf(alice);
        uint256 ethBalanceBefore = alice.balance;
        
        console.log("Alice stHYPE balance before unstake:", aliceBalance);
        console.log("Alice ETH balance before unstake:", ethBalanceBefore);
        
        // Unstake half
        uint256 unstakeAmount = aliceBalance / 2;
        vm.startPrank(alice);
        stHype.approve(address(overseer), unstakeAmount);
        overseer.burnAndRedeemIfPossible(alice, unstakeAmount, "");
        vm.stopPrank();
        
        uint256 ethBalanceAfter = alice.balance;
        uint256 stHypeBalanceAfter = stHype.balanceOf(alice);
        
        console.log("Alice ETH received:", ethBalanceAfter - ethBalanceBefore);
        console.log("Alice remaining stHYPE:", stHypeBalanceAfter);
        
        // Should receive ETH equal to unstaked amount (including rewards)
        assertEq(ethBalanceAfter - ethBalanceBefore, unstakeAmount);
        assertApproxEqAbs(stHypeBalanceAfter, aliceBalance - unstakeAmount, 0.01e18);
        
        // Alice should have earned rewards
        assertGt(ethBalanceAfter - ethBalanceBefore, 15e18); // More than half original stake
        
        console.log("Unstaking with rewards works correctly");
    }
    
    function test9_SharesVsBalanceConsistency() public {
        console.log("\n=== Test 9: Shares vs Balance Consistency ===");
        
        deal(alice, 40 ether);
        vm.prank(alice);
        overseer.mint{value: 40 ether}(alice, "");
        
        uint256 initialShares = stHype.sharesOf(alice);
        uint256 initialBalance = stHype.balanceOf(alice);
        
        console.log("Initial state:");
        console.log("  Shares:", initialShares);
        console.log("  Balance:", initialBalance);
        
        // Multiple rebases
        stHype.rebase(2 ether);
        stHype.rebase(3 ether);
        stHype.rebase(1 ether);
        
        uint256 finalShares = stHype.sharesOf(alice);
        uint256 finalBalance = stHype.balanceOf(alice);
        uint256 expectedBalance = 46e18; // 40 + 2 + 3 + 1
        
        console.log("After multiple rebases:");
        console.log("  Shares:", finalShares);
        console.log("  Balance:", finalBalance);
        
        // Shares should never change
        assertEq(finalShares, initialShares);
        
        // Balance should reflect all rewards
        assertEq(finalBalance, expectedBalance);
        
        // Test conversion functions
        uint256 calculatedBalance = stHype.sharesToBalance(finalShares);
        uint256 calculatedShares = stHype.balanceToShares(finalBalance);
        
        assertEq(calculatedBalance, finalBalance);
        assertEq(calculatedShares, finalShares);
        
        console.log("Shares vs balance consistency maintained");
    }
    
    function test10_WstHypeConversionAccuracy() public {
        console.log("\n=== Test 10: wstHYPE Conversion Accuracy ===");
        
        deal(alice, 50 ether);
        vm.prank(alice);
        overseer.mint{value: 50 ether}(alice, "");
        
        // Add significant rewards
        stHype.rebase(25 ether); // 50% increase
        
        uint256 stHypeBalance = stHype.balanceOf(alice);
        uint256 wstHypeBalance = wstHype.balanceOf(alice);
        
        console.log("After 50% rewards:");
        console.log("  stHYPE balance:", stHypeBalance);
        console.log("  wstHYPE balance:", wstHypeBalance);
        console.log("  Exchange rate:", wstHype.stHypePerToken());
        
        // Test conversion accuracy
        uint256 wstToStHype = wstHype.getStHypeByWstHype(wstHypeBalance);
        uint256 stToWstHype = wstHype.getWstHypeByStHype(stHypeBalance);
        
        console.log("Conversion check:");
        console.log("  wstHYPE -> stHYPE:", wstToStHype);
        console.log("  stHYPE -> wstHYPE:", stToWstHype);
        
        assertApproxEqAbs(wstToStHype, stHypeBalance, 100); // Should convert exactly
        assertApproxEqAbs(stToWstHype, wstHypeBalance, 100); // Should convert exactly
        
        // Exchange rate should be 1.5 (75 stHYPE / 50 wstHYPE)
        assertApproxEqAbs(wstHype.stHypePerToken(), 1.5e18, 100);
        
        console.log("Conversion accuracy verified");
    }
    
    function test11_EdgeCaseZeroShares() public view{
        console.log("\n=== Test 11: Edge Case - Zero Shares ===");
        
        // Test behavior when no one has staked yet
        assertEq(stHype.totalSupply(), 0);
        assertEq(stHype.balanceOf(alice), 0);
        assertEq(wstHype.totalSupply(), 0);
        assertEq(wstHype.balanceOf(alice), 0);
        
        // Exchange rate should default to 1:1 when no shares
        assertEq(wstHype.stHypePerToken(), 1e18);
        
        console.log("Zero shares edge case handled correctly");
    }
    
    function test12_LargeNumbersHandling() public {
        console.log("\n=== Test 12: Large Numbers Handling ===");
        
        // Test with very large amounts
        uint256 largeAmount = 1000000 ether;
        deal(alice, largeAmount);
        
        vm.prank(alice);
        overseer.mint{value: largeAmount}(alice, "");
        
        // Large rebase
        uint256 largeReward = 500000 ether;
        stHype.rebase(largeReward);
        
        uint256 expectedBalance = largeAmount + largeReward;
        assertEq(stHype.balanceOf(alice), expectedBalance);
        assertEq(wstHype.balanceOf(alice), largeAmount); // wstHYPE unchanged
        
        // Exchange rate should be 1.5
        assertEq(wstHype.stHypePerToken(), 1.5e18);
        
        console.log("Large numbers handled correctly");
    }
    
    function test13_MultipleRebasesCompounding() public {
        console.log("\n=== Test 13: Multiple Rebases Compounding ===");
        
        deal(alice, 100 ether);
        vm.prank(alice);
        overseer.mint{value: 100 ether}(alice, "");
        
        console.log("Initial balance:", stHype.balanceOf(alice));
        
        uint256 balance = 100e18;
        
        // Apply 10% rewards 5 times
        for (uint i = 0; i < 5; i++) {
            uint256 reward = balance / 10; // 10% of current total supply
            stHype.rebase(reward);
            balance += reward;
            
            console.log("After rebase", i + 1, "balance:", stHype.balanceOf(alice));
            assertEq(stHype.balanceOf(alice), balance);
        }
        
        assertEq(stHype.balanceOf(alice), 161.051 ether);
        assertEq(wstHype.balanceOf(alice), 100e18); // wstHYPE unchanged
        assertEq(wstHype.stHypePerToken(), 1.61051e18);
        
        console.log("Multiple rebases compound correctly");
    }
    
    function test14_TransferFromAndApprovals() public {
        console.log("\n=== Test 14: TransferFrom and Approvals ===");
        
        deal(alice, 30 ether);
        vm.prank(alice);
        overseer.mint{value: 30 ether}(alice, "");
        
        // Add some rewards
        stHype.rebase(6 ether); // Alice now has 36 stHYPE
        
        // Test stHYPE approvals
        vm.prank(alice);
        stHype.approve(bob, 20e18);
        
        assertEq(stHype.allowance(alice, bob), 20e18);
        
        vm.prank(bob);
        stHype.transferFrom(alice, charlie, 15e18);
        
        assertEq(stHype.balanceOf(alice), 21e18);
        assertEq(stHype.balanceOf(charlie), 15e18);
        assertEq(stHype.allowance(alice, bob), 5e18);

        console.log("Approvals and transferFrom work correctly");
    }
    
    function test15_ConsistencyAfterComplexOperations() public {
        console.log("\n=== Test 15: Consistency After Complex Operations ===");
        
        // Multiple users, multiple operations
        deal(alice, 50 ether);
        deal(bob, 30 ether);
        deal(charlie, 20 ether);
        
        // Everyone stakes
        vm.prank(alice);
        overseer.mint{value: 50 ether}(alice, "");
        
        vm.prank(bob);
        overseer.mint{value: 30 ether}(bob, "");
        
        vm.prank(charlie);
        overseer.mint{value: 20 ether}(charlie, "");
        
        // Multiple rebases and transfers
        stHype.rebase(10 ether); // +10% total
        
        vm.prank(alice);
        stHype.transfer(bob, 20e18);
        
        stHype.rebase(11 ether); // +10% more
        
        vm.prank(charlie);
        wstHype.transfer(alice, 10e18);
        
        // Final verification
        uint256 totalStHype = stHype.balanceOf(alice) + stHype.balanceOf(bob) + stHype.balanceOf(charlie);
        uint256 totalWstHype = wstHype.balanceOf(alice) + wstHype.balanceOf(bob) + wstHype.balanceOf(charlie);
        
        console.log("Final balances:");
        console.log("  Total stHYPE:", totalStHype);
        console.log("  Total wstHYPE:", totalWstHype);
        // console.log("  Expected total:", 121e18); // 100 + 21 rewards
        uint256 expectedTotal = 121e18;
        console.log("Expected Total : ", expectedTotal);
        
        assertApproxEqAbs(totalStHype, 121e18, 10);
        assertApproxEqAbs(totalWstHype, 100e18, 10); // Original stakes
        assertApproxEqAbs(stHype.totalSupply(), 121e18, 10);
        assertApproxEqAbs(wstHype.totalSupply(), 100e18, 10);
        
        // Exchange rate verification
        uint256 exchangeRate = wstHype.stHypePerToken();
        assertApproxEqAbs(exchangeRate, 1.21e18, 10); // 121/100 = 1.21
        
        console.log("All operations maintain consistency");
    }
}