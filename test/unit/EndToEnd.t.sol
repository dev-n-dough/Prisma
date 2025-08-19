// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "@boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {Strategy} from "../../src/strategy/Strategy.sol";
import {StHYPEDecoderAndSanitizer} from "../../src/decoders/StHYPEDecoderAndSanitizer.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "@boring-vault/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {IOverseer} from "../../src/interfaces/IOverseer.sol";
import {IStHYPE} from "../../src/interfaces/IStHYPE.sol";
import {IWHYPE} from "../../src/interfaces/IWHYPE.sol";
import {IWstHype} from "../../src/interfaces/IWstHype.sol";
import {Looping} from "../../src/strategy/Looping.sol";
import {AtomicSolverV3, AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicSolverV3.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";


// import Mocks
import {MockWHype} from "../mocks/MockWHype.sol";
import {MockOverseer, APY} from "../mocks/MockOverseer.sol";
import {MockStHype} from "../mocks/MockStHype.sol";
import {MockWstHype} from "../mocks/MockWstHype.sol";
import {MockMorpho, INTEREST_RATE, SECONDS_PER_YEAR} from "../mocks/MockMorpho.sol";

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {SharesMathLib} from "../../src/libraries/SharesMathLib.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";

import {Id, IMorphoStaticTyping, IMorphoBase, MarketParams, Position, Market, Authorization, Signature} from "../../src/interfaces/IMorpho.sol";

contract LoopingUnit is Test {
    Id public constant MARKET_ID =
        Id.wrap(
            0xe9a9bb9ed3cc53f4ee9da4eea0370c2c566873d5de807e16559a99907c9ae227
        );

    struct NetworkConfig {
        uint256 chainId;
        address wHype;
        address stHype;
        address overseer;
        address wstHype;
        address morpho;
    }

    ManagerWithMerkleVerification public manager;
    BoringVault public vault;
    StHYPEDecoderAndSanitizer public decoder;
    // Strategy public strategy;
    Looping public looping;
    RolesAuthority public rolesAuthority;
    TellerWithMultiAssetSupport public teller;
    AccountantWithRateProviders public accountant;
    address public payout_address = vm.addr(7777777);
    AtomicQueue public atomicQueue;
    AtomicSolverV3 public atomicSolverV3;
    address public solver = vm.addr(54);

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant BORING_VAULT_ROLE = 5;
    // uint8 public constant BALANCER_VAULT_ROLE = 6;  
    uint8 public constant MINTER_ROLE = 7;
    uint8 public constant BURNER_ROLE = 8;
    uint8 public constant SOLVER_ROLE = 9;
    uint8 public constant QUEUE_ROLE = 10;
    uint8 public constant CAN_SOLVE_ROLE = 11;

    NetworkConfig config;

    MockStHype public mockStHype;
    MockOverseer public mockOverseer;
    MockWHype public mockWHype;
    MockWstHype public mockWstHype;
    MockMorpho public mockMorpho;

    address bob = makeAddr("bob");

    function setUp() external {
        config = getNetworkInfo();

        vault = new BoringVault(address(this), "Boring Vault", "BV", 18);
        manager = new ManagerWithMerkleVerification(
            address(this),
            address(vault),
            address(vault)
        ); // e considering I wont need the flash loan function, keeping the last argument as boring vault only
        decoder = new StHYPEDecoderAndSanitizer(
            address(vault),
            config.overseer,
            config.stHype,
            config.wHype
        );
        looping = new Looping(
            address(manager),
            address(vault),
            config.wHype,
            config.stHype,
            config.overseer,
            address(decoder),
            address(this),
            config.wstHype,
            config.morpho
        );

        accountant = new AccountantWithRateProviders(
            address(this), address(vault), payout_address, 1e18, config.wHype, 1.001e4, 0.999e4, 1, 0, 0
        );

        teller =
            new TellerWithMultiAssetSupport(address(this), address(vault), address(accountant), config.wHype);

        atomicQueue = new AtomicQueue(address(this), Authority(address(0)));
        atomicSolverV3 = new AtomicSolverV3(address(this), rolesAuthority);

        rolesAuthority = new RolesAuthority(
            address(this),
            Authority(address(0))
        );
        vault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);
        accountant.setAuthority(rolesAuthority);
        teller.setAuthority(rolesAuthority);
        atomicQueue.setAuthority(rolesAuthority);

        // ROLES! Important

        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(vault),
            bytes4(
                keccak256(abi.encodePacked("manage(address,bytes,uint256)"))
            ),
            true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification
                .manageVaultWithMerkleVerification
                .selector,
            true
        );
        rolesAuthority.setRoleCapability(
            MANGER_INTERNAL_ROLE,
            address(manager),
            ManagerWithMerkleVerification
                .manageVaultWithMerkleVerification
                .selector,
            true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(manager),
            ManagerWithMerkleVerification.setManageRoot.selector,
            true
        );

        rolesAuthority.setRoleCapability(MINTER_ROLE, address(vault), BoringVault.enter.selector, true);
        rolesAuthority.setRoleCapability(BURNER_ROLE, address(vault), BoringVault.exit.selector, true);
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.updateAssetData.selector, true
        );
        // e we are setting the following role because this is a unit test, else this would be called by SOLVER_ROLE only 
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE, address(teller), TellerWithMultiAssetSupport.refundDeposit.selector, true
        );
        rolesAuthority.setRoleCapability(
            SOLVER_ROLE, address(teller), TellerWithMultiAssetSupport.bulkWithdraw.selector, true
        );
        rolesAuthority.setRoleCapability(QUEUE_ROLE, address(atomicSolverV3), AtomicSolverV3.finishSolve.selector, true);
        rolesAuthority.setRoleCapability(
            CAN_SOLVE_ROLE, address(atomicSolverV3), AtomicSolverV3.redeemSolve.selector, true
        );

        rolesAuthority.setUserRole(address(looping), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(
            address(manager),
            MANGER_INTERNAL_ROLE,
            true
        );
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(vault), BORING_VAULT_ROLE, true);
        // rolesAuthority.setUserRole(vault, BALANCER_VAULT_ROLE, true);

        rolesAuthority.setPublicCapability(address(teller), TellerWithMultiAssetSupport.deposit.selector, true);
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.updateAtomicRequest.selector, true); // users who wanna withdraw
        rolesAuthority.setPublicCapability(address(atomicQueue), AtomicQueue.solve.selector, true); // users who wanna solve(here, `solver`)

        rolesAuthority.setUserRole(address(teller), MINTER_ROLE, true);
        rolesAuthority.setUserRole(address(teller), BURNER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicSolverV3), SOLVER_ROLE, true);
        rolesAuthority.setUserRole(address(atomicQueue), QUEUE_ROLE, true);
        rolesAuthority.setUserRole(solver, CAN_SOLVE_ROLE, true);

        rolesAuthority.setPublicCapability(address(vault), bytes4(0), true);

        bytes32 manageRoot = looping.getManageTreeRoot();
        manager.setManageRoot(address(looping), manageRoot); // since looping inherits from strategy, setting `looping`(instead of `strategy`) as the admin for that root would work perfectly

        teller.updateAssetData(ERC20(config.wHype), true, true, 0); // wHype being the `token of the vault` essentially 

        vault.setBeforeTransferHook(address(teller));
        teller.setShareLockPeriod(1 days);

        ///// SETUP MOCK CONTRACTS
        mockStHype = MockStHype(payable(config.stHype));
        mockOverseer = MockOverseer(payable(config.overseer));
        mockWHype = MockWHype(payable(config.wHype));
        deal(config.overseer, 100000 ether); // since it gives out more money than it receives(2% artificial yield)
        mockWstHype = MockWstHype(payable(config.wstHype));
        mockMorpho = MockMorpho(payable(config.morpho));

        // I am doing the following just to increase the `totalSupply` variable in MockWHype, so `withdraw` doesnt revert on underflow
        address alice = makeAddr("alice");
        vm.startPrank(alice);
        deal(alice, 100000 ether);
        mockWHype.deposit{value : 100000 ether}();
        vm.stopPrank();
    }

    function test_UserDepositsAndLoopStarts_OneLoop() public{
        uint256 n = 1;
        uint256 amount = 10e18;
        deal(bob,amount);
        // IWHYPE(config.wHype).approve(address(looping),amount);
        vm.startPrank(bob);
        mockWHype.deposit{value : amount}();
        uint256 userBalanceInitial = IWHYPE(config.wHype).balanceOf(bob);
        uint256 vaultBalanceInitial = IWHYPE(config.wHype).balanceOf(address(vault));
        IWHYPE(config.wHype).approve(address(vault),amount);
        teller.deposit(ERC20(config.wHype), amount, 9.9e18);
        vm.stopPrank();

        uint256 expectedShares = amount; // since initial exchange rate was 1:1 
        uint256 actualShares = vault.balanceOf(bob);
        uint256 userBalanceFinal = IWHYPE(config.wHype).balanceOf(bob);
        uint256 vaultBalanceFinal = IWHYPE(config.wHype).balanceOf(address(vault));
        assertEq(expectedShares, actualShares);
        assertEq(userBalanceInitial - userBalanceFinal, amount);
        assertEq(vaultBalanceFinal - vaultBalanceInitial, amount);

        // start the strategy
        (uint256 totalStaked,uint256 totalBorrowed,uint256 initialVaultBalance) = looping.executeLoop(n);
        assert(totalStaked == 18.6 ether);
        assert(totalBorrowed == 8.6 ether);
        assert(initialVaultBalance == 10 ether);
    }

    function test_UserDepositsAndLoopStarts_MultipleLoops() public{
        uint256 n = 3;
        uint256 amount = 10e18;
        deal(bob,amount);
        vm.startPrank(bob);
        mockWHype.deposit{value : amount}();
        IWHYPE(config.wHype).approve(address(vault),amount);
        teller.deposit(ERC20(config.wHype), amount, 9.9e18);
        vm.stopPrank();

        // start the strategy
        (uint256 totalStaked,uint256 totalBorrowed,uint256 initialVaultBalance) = looping.executeLoop(n);
        console.log("totalStaked : ", totalStaked); 
        // n=2 => 25996000000000000000
        // n=3 => 32356560000000000000
        // n=4 => 37826641600000000000

        console.log("totalBorrowed : ", totalBorrowed);
        console.log("initialVaultBalance : ", initialVaultBalance);
        // assert(totalStaked == 18.6 ether);
        // assert(totalBorrowed == 8.6 ether);
        // assert(initialVaultBalance == 10 ether);
    }

    modifier bobDeposits(uint256 amount){
        deal(bob,amount);
        vm.startPrank(bob);
        mockWHype.deposit{value : amount}();
        IWHYPE(config.wHype).approve(address(vault),amount);
        teller.deposit(ERC20(config.wHype), amount, 9.9e18);
        vm.stopPrank();
        _;
    } 

    function testExitLoopAndUserWithdraws_OneLoop() public bobDeposits(10e18){
        uint256 n = 1;
        (uint256 totalStaked,uint256 totalBorrowed,uint256 initialVaultBalance) = looping.executeLoop(n);

        vm.warp(block.timestamp + 365 days);

        looping.executeExitLoop(n,initialVaultBalance);
    }

    function getNetworkInfo()
        public
        returns (NetworkConfig memory networkConfig)
    {
        uint256 chainId = block.chainid;

        // deploy mocks
        MockWHype wHype = new MockWHype();
        MockStHype stHype = new MockStHype();
        MockOverseer overseer = new MockOverseer(address(stHype));
        deal(address(overseer), 10000 ether);
        stHype.setOverseer(address(overseer));

        MockWstHype wstHype = new MockWstHype(address(stHype));
        stHype.setWstHype(address(wstHype));

        MockMorpho morpho = new MockMorpho(address(wHype), address(wstHype));
        // add initial liquidity to morpho
        uint256 fundAmount = 1000 ether;
        deal(address(wHype), address(this), fundAmount);
        wHype.approve(address(morpho), fundAmount);
        wHype.transfer(address(morpho), fundAmount);
        deal(address(wHype), 1000 ether);

        networkConfig = NetworkConfig({
            chainId: chainId,
            wHype: address(wHype),
            stHype: address(stHype),
            overseer: address(overseer),
            wstHype: address(wstHype),
            morpho: address(morpho)
        });
    }
}

// 2105779789937698301 = 2.1 