// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "@boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
// import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {AtomicSolverV3, AtomicQueue,TellerWithMultiAssetSupport} from "@boring-vault/src/atomic-queue/AtomicSolverV3.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {CustomAccountant} from "../../src/accountant/CustomAccountant.sol";

// Import mocks
import {MockWHype} from "../mocks/MockWHype.sol";
import {MockOverseer, APY} from "../mocks/MockOverseer.sol";
import {MockStHype} from "../mocks/MockStHype.sol";
import {MockWstHype} from "../mocks/MockWstHype.sol";
import {MockMorpho, INTEREST_RATE, SECONDS_PER_YEAR} from "../mocks/MockMorpho.sol";

import {Id, IMorphoStaticTyping} from "../../src/interfaces/IMorpho.sol";
import {IStHYPE} from "../../src/interfaces/IStHYPE.sol";
import {IWHYPE} from "../../src/interfaces/IWHYPE.sol";

contract CustomAccountantTest is Test {
    // Core contracts
    BoringVault public vault;
    AccountantWithRateProviders public accountant;
    CustomAccountant public customAccountant;
    TellerWithMultiAssetSupport public teller;
    AtomicQueue public atomicQueue;
    AtomicSolverV3 public atomicSolverV3;
    RolesAuthority public rolesAuthority;

    // Mocks
    MockWHype public mockWHype;
    MockStHype public mockStHype;
    MockOverseer public mockOverseer;
    MockWstHype public mockWstHype;
    MockMorpho public mockMorpho;

    // Test addresses
    address public owner = address(this);
    address public payoutAddress = address(0x123);
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");
    address public solver = makeAddr("solver");
    address public mock_tester = makeAddr("mock_tester");

    // Constants
    Id public constant MARKET_ID = Id.wrap(0xe9a9bb9ed3cc53f4ee9da4eea0370c2c566873d5de807e16559a99907c9ae227);
    
    // Roles
    uint8 public constant ADMIN_ROLE = 1;
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;
    uint8 public constant UPDATER_ROLE = 12;
    uint8 public constant CUSTOM_TESTING_ROLE = 13;

    function setUp() public {
        // Deploy mocks
        setupMocks();
        
        // Deploy core contracts
        vault = new BoringVault(owner, "Test Vault", "TV", 18);
        
        accountant = new AccountantWithRateProviders(
            owner,
            address(vault),
            payoutAddress,
            1e18, // starting exchange rate
            address(mockWHype), // base asset
            20000, // upper bound (100% increase)
            5000,  // lower bound (50% decrease) => note that these bounds are too loose, but have kept it this way for testing
            1,    // min update delay
            0,    // platform fee
            0     // performance fee
        );
        
        customAccountant = new CustomAccountant(
            owner,
            address(vault),
            address(accountant),
            address(mockStHype),
            address(mockWHype),
            address(mockWstHype),
            address(mockOverseer),
            address(mockMorpho),
            MARKET_ID
        );
        
        teller = new TellerWithMultiAssetSupport(
            owner,
            address(vault),
            address(accountant),
            address(mockWHype)
        );
        
        atomicQueue = new AtomicQueue(owner, Authority(address(0)));
        atomicSolverV3 = new AtomicSolverV3(owner, Authority(address(0)));
        
        // Setup roles and permissions
        setupRoles();
    }

    function setupMocks() internal {
        mockWHype = new MockWHype();
        mockStHype = new MockStHype();
        mockOverseer = new MockOverseer(address(mockStHype));
        deal(address(mockOverseer), 10000 ether);
        mockStHype.setOverseer(address(mockOverseer));
        
        mockWstHype = new MockWstHype(address(mockStHype));
        mockStHype.setWstHype(address(mockWstHype));
        
        mockMorpho = new MockMorpho(address(mockWHype), address(mockWstHype));
        
        // Fund morpho with initial liquidity
        deal(address(mockWHype), address(this), 1000 ether);
        mockWHype.approve(address(mockMorpho), 1000 ether);
        mockWHype.transfer(address(mockMorpho), 1000 ether);
        
        // Increase total supply for withdrawals
        deal(alice, 100000 ether);
        vm.startPrank(alice);
        mockWHype.deposit{value: 100000 ether}();
        vm.stopPrank();
    }

    function setupRoles() internal {
        rolesAuthority = new RolesAuthority(owner, Authority(address(0)));
        
        vault.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);
        atomicQueue.setAuthority(rolesAuthority);
        customAccountant.setAuthority(rolesAuthority);
        atomicSolverV3.setAuthority(rolesAuthority);

        // Set role capabilities
        rolesAuthority.setRoleCapability(MINTER_ROLE, address(vault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(vault), BoringVault.exit.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.updateAssetData.selector, true);
        rolesAuthority.setRoleCapability(ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true);
        rolesAuthority.setRoleCapability(SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true);
        rolesAuthority.setRoleCapability(UPDATER_ROLE, address(accountant), AccountantWithRateProviders.updateExchangeRate.selector, true);
        rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV3), AtomicSolverV3.finishSolve.selector, true);
        rolesAuthority.setRoleCapability(CAN_SOLVE_ROLE, address(atomicSolverV3), AtomicSolverV3.redeemSolve.selector, true);
        // just for testing
        rolesAuthority.setRoleCapability(CUSTOM_TESTING_ROLE, address(vault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(CUSTOM_TESTING_ROLE, address(vault), BoringVault.exit.selector, true);

        // Set public capabilities 
        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.updateAtomicRequest.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.solve.selector, true);

        // Assign roles to users
        rolesAuthority.setUserRole(owner, ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolverV3), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(solver, CAN_SOLVE_ROLE, true);
        rolesAuthority.setUserRole(address(customAccountant), UPDATER_ROLE, true);
        rolesAuthority.setUserRole(mock_tester,CUSTOM_TESTING_ROLE,true);

        // Setup teller 
        teller.updateAssetData(ERC20(address(mockWHype)), true, true, 0);
        vault.setBeforeTransferHook(address(teller));
        teller.setShareLockPeriod(1 days);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Helper to mint vault shares and update totalSupply
     * @dev This bypasses the normal minting process for testing
     */
    function mintVaultShares(address to, uint256 amount) internal {
        // Use vm.store to directly update the totalSupply and balance
        // This is a testing hack to simulate shares being minted
        
        // Get current total supply
        uint256 currentSupply = vault.totalSupply();
        uint256 currentBalance = vault.balanceOf(to);
        
        // Update total supply slot (ERC20 totalSupply is usually slot 3)
        vm.store(address(vault), bytes32(uint256(3)), bytes32(currentSupply + amount));
        
        // Update balance slot for the address
        // ERC20 balances are in a mapping, so we need to compute the slot
        bytes32 balanceSlot = keccak256(abi.encode(to, uint256(0))); // slot 0 for balances mapping
        vm.store(address(vault), balanceSlot, bytes32(currentBalance + amount));
        
        // Verify it worked
        assertEq(vault.totalSupply(), currentSupply + amount);
        assertEq(vault.balanceOf(to), currentBalance + amount);
    }

    /*//////////////////////////////////////////////////////////////
                            UNIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetWHypeBalance() public {
        uint256 amount = 100e18;
        deal(address(mockWHype), address(vault), amount);
        
        uint256 balance = customAccountant.getWHypeBalance();
        assertEq(balance, amount);
    }

    function testGetStHypeValueInWHype() public {
        uint256 stHypeAmount = 50e18;
        // deal(address(mockStHype), address(vault), stHypeAmount);
        deal(bob, stHypeAmount);
        vm.startPrank(bob);
        mockOverseer.mint{value : stHypeAmount}(bob,"");
        mockStHype.approve(address(vault), stHypeAmount);
        mockStHype.transfer(address(vault), stHypeAmount);
        vm.stopPrank();
        
        uint256 value = customAccountant.getStHypeValueInWHype();
        assertEq(value, stHypeAmount); // 1:1 initially
    }

    function testGetStHypeValueAfterRebase() public {
        uint256 stHypeAmount = 50e18;
        // deal(address(mockStHype), address(vault), stHypeAmount);
        deal(bob, stHypeAmount);
        vm.startPrank(bob);
        mockOverseer.mint{value : stHypeAmount}(bob,"");
        mockStHype.approve(address(vault), stHypeAmount);
        mockStHype.transfer(address(vault), stHypeAmount);
        vm.stopPrank();
        
        // Fast forward and rebase
        vm.warp(block.timestamp + 365 days);
        mockOverseer.rebase();
        
        uint256 value = customAccountant.getStHypeValueInWHype();
        uint256 expectedValue = stHypeAmount + (stHypeAmount * APY) / 10000; // 2% APY -> and APY is in basis points
        assertApproxEqAbs(value, expectedValue, 1e15);
    }

    function testConvertWstHypeToWHype() public {
        uint256 wstHypeAmount = 100e18;
        deal(bob, wstHypeAmount);
        vm.startPrank(bob);
        mockOverseer.mint{value : wstHypeAmount}(bob,"");
        mockStHype.approve(address(vault), wstHypeAmount);
        mockStHype.transfer(address(vault), wstHypeAmount);
        vm.stopPrank();
        
        uint256 result = customAccountant.convertWstHypeToWHype(wstHypeAmount);
        assertEq(result, wstHypeAmount); // Should be 1:1 in mock setup
    }

    function testGetMorphoNetPositionEmpty() public view {
        uint256 netValue = customAccountant.getMorphoNetPositionInWHype();
        assertEq(netValue, 0);
    }

    function testGetMorphoNetPositionWithCollateral() public {
        uint256 collateralAmount = 80e18;
        
        mockMorpho.setPosition(
            MARKET_ID,
            address(vault),
            0, // supplyShares
            0, // borrowShares
            uint128(collateralAmount) // collateral
        );
        
        uint256 netValue = customAccountant.getMorphoNetPositionInWHype();
        assertEq(netValue, collateralAmount);
    }

    function testGetMorphoNetPositionWithCollateralAndDebt() public {
        uint256 collateralAmount = 100e18;
        uint256 borrowShares = 50e18 * 1e6; // Mock conversion
        uint256 borrowAssets = 50e18;
        
        mockMorpho.setMarket(
            MARKET_ID,
            0, 
            0,
            uint128(borrowAssets),
            uint128(borrowShares),
            uint128(block.timestamp),
            0
        );
        
        mockMorpho.setPosition(
            MARKET_ID,
            address(vault),
            0,
            uint128(borrowShares),
            uint128(collateralAmount)
        );
        
        uint256 netValue = customAccountant.getMorphoNetPositionInWHype();
        assertEq(netValue, collateralAmount - borrowAssets);
    }

    function testCalculateTotalVaultValue() public {
        uint256 wHypeAmount = 20e18;
        uint256 stHypeAmount = 30e18;
        uint256 collateralAmount = 80e18;
        uint256 borrowAssets = 40e18;
        
        // Set up all positions
        deal(address(mockWHype), address(vault), wHypeAmount);
        // deal(address(mockStHype), address(vault), stHypeAmount);
        deal(bob, stHypeAmount);
        vm.startPrank(bob);
        mockOverseer.mint{value : stHypeAmount}(bob,"");
        mockStHype.approve(address(vault), stHypeAmount);
        mockStHype.transfer(address(vault), stHypeAmount);
        vm.stopPrank();
        
        mockMorpho.setMarket(
            MARKET_ID,
            0, 0,
            uint128(borrowAssets),
            uint128(borrowAssets * 1e6),
            uint128(block.timestamp),
            0
        );
        
        mockMorpho.setPosition(
            MARKET_ID,
            address(vault),
            0,
            uint128(borrowAssets * 1e6),
            uint128(collateralAmount)
        );
        
        uint256 totalValue = customAccountant.calculateTotalVaultValue();
        uint256 expectedValue = wHypeAmount + stHypeAmount + (collateralAmount - borrowAssets);
        assertEq(totalValue, expectedValue);
    }

    function testPreviewExchangeRate() public {
        uint256 extraAmount = 10e18;
        uint256 depositAmount = 100e18;
        uint256 totalValue = depositAmount + extraAmount;
        
        // Setup vault value
        deal(address(mockWHype), address(vault), extraAmount); // this gives 10 wHype to vault, increasing its TVL
        deal(address(mockWHype), address(this), depositAmount);
        mockWHype.approve(address(vault), depositAmount);
        
        // Mock total supply
        // deal(address(vault), address(this), shares);
        // mintVaultShares(address(this), shares);
        vm.prank(mock_tester);
        vault.enter(
            address(this),
            ERC20(address(mockWHype)),
            depositAmount,
            address(this),
            depositAmount*10**6
        ); // this gives the vault 100 wHype,and mints 100 shares in return
        
        (uint96 rate, uint256 value) = customAccountant.previewExchangeRate();
        assertEq(value, totalValue);
        assertEq(rate, 1.1e18); // 110e18 / 100e18 = 1.1
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testUserDepositAndBasicExchangeRateUpdate() public {
        uint256 depositAmount = 10e18;
        
        // Bob deposits
        deal(bob, depositAmount);
        vm.startPrank(bob);
        mockWHype.deposit{value: depositAmount}();
        mockWHype.approve(address(vault), depositAmount);
        uint256 shares = teller.deposit(ERC20(address(mockWHype)), depositAmount, 9e18);
        vm.stopPrank();
        
        assertEq(shares, depositAmount); // 1:1 initially
        assertEq(vault.balanceOf(bob), shares);
        
        // Update exchange rate (no value change yet)
        customAccountant.updateExchangeRate();
        
        uint256 rate = accountant.getRate();
        assertEq(rate, 1e18); // Should still be 1:1
    }

    function testShareAppreciationWithStHypeYield() public {
        uint256 depositAmount = 10e18;
        
        // Bob deposits
        deal(bob, depositAmount);
        vm.startPrank(bob);
        mockWHype.deposit{value: depositAmount}();
        mockWHype.approve(address(vault), depositAmount);
        uint256 shares = teller.deposit(ERC20(address(mockWHype)), depositAmount, 9e18);
        vm.stopPrank();
        
        // Simulate vault getting stHYPE (from strategy) => send some more stHype to the vault
        uint256 stHypeAmount = 8e18;
        // deal(address(mockStHype), address(vault), stHypeAmount);
        deal(alice, stHypeAmount);
        vm.startPrank(alice);
        mockOverseer.mint{value : stHypeAmount}(alice,"");
        mockStHype.approve(address(vault), stHypeAmount);
        mockStHype.transfer(address(vault), stHypeAmount);
        vm.stopPrank();
        
        // Fast forward time and generate yield
        vm.warp(block.timestamp + 365 days);
        mockOverseer.rebase();
        
        // Update exchange rate
        customAccountant.updateExchangeRate();
        
        uint256 newRate = accountant.getRate();
        assertGt(newRate, 1e18); // Rate should have increased 
        assertEq(newRate , 1.816e18); // since that 8e18 stHype will earn 2% APY 
        
        // Bob's shares are now worth more
        uint256 bobShareValue = (shares * newRate) / 1e18;
        assertGt(bobShareValue, depositAmount);
        assertEq(bobShareValue, 18.16e18);
        
        // console.log("Initial deposit:", depositAmount);
        // console.log("Final share value:", bobShareValue);
        // console.log("Yield generated:", bobShareValue - depositAmount);
    }

    function testShareAppreciationWithMorphoPositions() public {
        uint256 depositAmount = 10e18;
        
        // Bob deposits
        deal(bob, depositAmount);
        vm.startPrank(bob);
        mockWHype.deposit{value: depositAmount}();
        mockWHype.approve(address(vault), depositAmount);
        uint256 shares = teller.deposit(ERC20(address(mockWHype)), depositAmount, 9e18);
        vm.stopPrank();
        
        // Simulate vault has morpho positions (profitable)
        uint256 collateralAmount = 15e18;
        uint256 borrowAssets = 5e18;
        
        mockMorpho.setMarket(
            MARKET_ID,
            0, 0,
            uint128(borrowAssets),
            uint128(borrowAssets * 1e6),
            uint128(block.timestamp),
            0
        );
        
        mockMorpho.setPosition(
            MARKET_ID,
            address(vault),
            0,
            uint128(borrowAssets * 1e6),
            uint128(collateralAmount)
        );
        
        // Update exchange rate
        customAccountant.updateExchangeRate();
        
        uint256 newRate = accountant.getRate();
        uint256 expectedTotalValue = depositAmount + (collateralAmount - borrowAssets);
        uint256 expectedRate = (expectedTotalValue * 1e18) / shares;
        
        assertEq(newRate, expectedRate);
        assertGt(newRate, 1e18);
        
        // console.log("Morpho net position value:", collateralAmount - borrowAssets);
        // console.log("New exchange rate:", newRate);
    }

    function testComplexYieldScenario() public {
        uint256 depositAmount = 10e18;
        
        // Bob deposits
        deal(bob, depositAmount);
        vm.startPrank(bob);
        mockWHype.deposit{value: depositAmount}();
        mockWHype.approve(address(vault), depositAmount);
        uint256 shares = teller.deposit(ERC20(address(mockWHype)), depositAmount, 9e18);
        vm.stopPrank();

        // uint256 wHypeBalance = customAccountant.getWHypeBalance();
        // console.log("wHypeBalance : ", wHypeBalance);
        
        // Simulate complex vault state:
        // 1. Some wHYPE left
        // 2. Some stHYPE earning yield
        // 3. Morpho positions
        
        uint256 remainingWHype = 2e18;
        uint256 stHypeAmount = 6e18;
        uint256 collateralAmount = 12e18;
        uint256 borrowAssets = 4e18;
        
        // Remove some wHYPE (simulating strategy deployment)
        deal(address(mockWHype), address(vault), mockWHype.balanceOf(address(vault)) + remainingWHype);
        
        // Add stHYPE
        // deal(address(mockStHype), address(vault), stHypeAmount);
        deal(alice, stHypeAmount);
        vm.startPrank(alice);
        mockOverseer.mint{value : stHypeAmount}(alice,"");
        mockStHype.approve(address(vault), stHypeAmount);
        mockStHype.transfer(address(vault), stHypeAmount);
        vm.stopPrank();
        
        // Add Morpho positions 
        mockMorpho.setMarket(
            MARKET_ID,
            0, 0,
            uint128(borrowAssets),
            uint128(borrowAssets * 1e6),
            uint128(block.timestamp),
            0
        );
        
        mockMorpho.setPosition(
            MARKET_ID,
            address(vault),
            0,
            uint128(borrowAssets * 1e6),
            uint128(collateralAmount)
        );
        
        // Fast forward and generate yield
        vm.warp(block.timestamp + 365 days);
        mockOverseer.rebase();
        mockMorpho.accrueInterest(MARKET_ID);
        
        // Update exchange rate
        customAccountant.updateExchangeRate();
        
        uint256 newRate = accountant.getRate();
        uint256 bobShareValue = (shares * newRate) / 1e18;
        
        assertGt(newRate, 1e18);
        assertGt(bobShareValue, depositAmount);
        
        // Check position breakdown
        (
            uint256 wHypeBalance,
            uint256 stHypeValue,
            uint256 morphoCollateralValue,
            uint256 morphoBorrowValue,
            uint256 morphoNetValue,
            uint256 totalValue
        ) = customAccountant.getPositionBreakdown();
        
        console.log("=== Position Breakdown ==="); 
        console.log("wHYPE balance:", wHypeBalance);                // 12000000000000000000 = 12e18
        console.log("stHYPE value:", stHypeValue);                  // 6120000000000000000 = 6.12e18
        console.log("Morpho collateral:", morphoCollateralValue);   // 12240000000000000000 = 12.24e18 
        console.log("Morpho debt:", morphoBorrowValue);             // 4040000000000000000 = 4.04e18
        console.log("Morpho net:", morphoNetValue);                 // 8200000000000000000 = 8.2e18
        console.log("Total value:", totalValue);                    // 26320000000000000000 = 26.32e18
        console.log("Bob's final value:", bobShareValue);           // 26320000000000000000 = 26.32e18
        console.log("Yield earned:", bobShareValue > depositAmount ? bobShareValue - depositAmount : 0); // 16320000000000000000 = 16.32e18 
    }

    // function testUserWithdrawAfterYield() public {
    //     uint256 depositAmount = 10e18;
        
    //     // Bob deposits
    //     deal(bob, depositAmount);
    //     vm.startPrank(bob);
    //     mockWHype.deposit{value: depositAmount}();
    //     mockWHype.approve(address(vault), depositAmount);
    //     uint256 shares = teller.deposit(ERC20(address(mockWHype)), depositAmount, 9e18);
    //     vm.stopPrank();
        
    //     // Generate yield
    //     uint256 stHypeAmount = 8e18;
    //     // deal(address(mockStHype), address(vault), stHypeAmount);
    //     deal(alice, stHypeAmount);
    //     vm.startPrank(alice);
    //     mockOverseer.mint{value : stHypeAmount}(alice,"");
    //     mockStHype.approve(address(vault), stHypeAmount);
    //     mockStHype.transfer(address(vault), stHypeAmount);
    //     vm.stopPrank();


    //     vm.warp(block.timestamp + 365 days);
    //     mockOverseer.rebase();
    //     customAccountant.updateExchangeRate();
    //     // 18.16e18 -> tvl 
        
    //     // Bob wants to withdraw
    //     vm.startPrank(bob);
    //     vault.approve(address(atomicQueue), shares);
        
    //     AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest(
    //         uint64(block.timestamp + 4 days),
    //         uint88(1.5e18), // Asking for 1.5 wHYPE per share (expecting profit)
    //         uint96(shares),
    //         false
    //     );
        
    //     atomicQueue.updateAtomicRequest(vault, ERC20(address(mockWHype)), req);
    //     vm.stopPrank();
        
    //     // Fast forward past share lock period
    //     vm.warp(block.timestamp + 2 days);
        
    //     // Solver provides liquidity 
    //     uint256 solverAmount = 15e18;
    //     deal(address(mockWHype), solver, solverAmount);
        
    //     vm.startPrank(solver);
    //     mockWHype.approve(address(atomicSolverV3), solverAmount);
        
    //     address[] memory users = new address[](1);
    //     users[0] = bob;
        
    //     uint256 bobBalanceBefore = mockWHype.balanceOf(bob);
        
    //     atomicSolverV3.redeemSolve(
    //         atomicQueue,
    //         vault,
    //         ERC20(address(mockWHype)),
    //         users,
    //         shares,
    //         solverAmount,
    //         TellerWithMultiAssetSupport(address(teller))
    //     );
    //     vm.stopPrank();
        
    //     uint256 bobBalanceAfter = mockWHype.balanceOf(bob);
    //     assertGt(bobBalanceAfter - bobBalanceBefore, depositAmount);
        
    //     console.log("Bob withdrew:", bobBalanceAfter - bobBalanceBefore);
    //     console.log("Profit:", (bobBalanceAfter - bobBalanceBefore) - depositAmount);
    // }

    // function testMultipleUsersWithDifferentDepositTimes() public {
    //     // Alice deposits early
    //     uint256 aliceDeposit = 10e18;
    //     deal(alice, aliceDeposit);
    //     vm.startPrank(alice);
    //     mockWHype.deposit{value: aliceDeposit}();
    //     mockWHype.approve(address(vault), aliceDeposit);
    //     uint256 aliceShares = teller.deposit(ERC20(address(mockWHype)), aliceDeposit, 9e18);
    //     vm.stopPrank();
        
    //     // Generate some yield
    //     uint256 stHypeAmount = 8e18;
    //     deal(address(mockStHype), address(vault), stHypeAmount);
    //     vm.warp(block.timestamp + 180 days); // 6 months
    //     mockOverseer.rebase();
    //     customAccountant.updateExchangeRate();
        
    //     uint256 midRate = accountant.getRate();
        
    //     // Bob deposits later at higher rate
    //     uint256 bobDeposit = 10e18;
    //     deal(bob, bobDeposit);
    //     vm.startPrank(bob);
    //     mockWHype.deposit{value: bobDeposit}();
    //     mockWHype.approve(address(vault), bobDeposit);
    //     uint256 bobShares = teller.deposit(ERC20(address(mockWHype)), bobDeposit, 8e18);
    //     vm.stopPrank();
        
    //     // Bob should get fewer shares since rate is higher
    //     assertLt(bobShares, aliceShares);
    //     assertEq(bobShares, (bobDeposit * 1e18) / midRate);
        
    //     // Generate more yield
    //     vm.warp(block.timestamp + 180 days); // Another 6 months
    //     mockOverseer.rebase();
    //     customAccountant.updateExchangeRate();
        
    //     uint256 finalRate = accountant.getRate();
        
    //     // Both should benefit from final rate
    //     uint256 aliceValue = (aliceShares * finalRate) / 1e18;
    //     uint256 bobValue = (bobShares * finalRate) / 1e18;
        
    //     assertGt(aliceValue, aliceDeposit);
    //     assertGt(bobValue, bobDeposit);
        
    //     // Alice should have more total value (earlier entry + more shares)
    //     assertGt(aliceValue, bobValue);
        
    //     console.log("Alice deposit:", aliceDeposit, "shares:", aliceShares, "final value:", aliceValue);
    //     console.log("Bob deposit:", bobDeposit, "shares:", bobShares, "final value:", bobValue);
    //     console.log("Mid rate:", midRate, "Final rate:", finalRate);
    // }
}