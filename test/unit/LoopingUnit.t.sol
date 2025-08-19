// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "@boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {Strategy} from "../../src/strategy/Strategy.sol";
import {StHYPEDecoderAndSanitizer} from "../../src/decoders/StHYPEDecoderAndSanitizer.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "@boring-vault/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {IOverseer} from "../../src/interfaces/IOverseer.sol";
import {IStHYPE} from "../../src/interfaces/IStHYPE.sol";
import {IWHYPE} from "../../src/interfaces/IWHYPE.sol";
import {IWstHype} from "../../src/interfaces/IWstHype.sol";
import {Looping} from "../../src/strategy/Looping.sol";

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

    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant MANGER_INTERNAL_ROLE = 3;
    uint8 public constant ADMIN_ROLE = 4;
    uint8 public constant BORING_VAULT_ROLE = 5;
    // uint8 public constant BALANCER_VAULT_ROLE = 6;  

    NetworkConfig config;

    MockStHype public mockStHype;
    MockOverseer public mockOverseer;
    MockWHype public mockWHype;
    MockWstHype public mockWstHype;
    MockMorpho public mockMorpho;

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

        rolesAuthority = new RolesAuthority(
            address(this),
            Authority(address(0))
        );
        vault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);

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

        rolesAuthority.setPublicCapability(address(vault), bytes4(0), true);

        bytes32 manageRoot = looping.getManageTreeRoot();
        manager.setManageRoot(address(looping), manageRoot); // since looping inherits from strategy, setting `looping`(instead of `strategy`) as the admin for that root would work perfectly

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

    function testLooping_OneLoop() public{
        uint256 initialDeposit = 10 ether;
        deal(address(mockWHype), address(vault), initialDeposit);
        (uint256 totalStaked, uint256 totalBorrowed,) = looping.executeLoop(1);
        assert(totalStaked == 18.6 ether);
        assert(totalBorrowed == 8.6 ether); // did this math manually
    }

    function testLooping_MultipleLoops() public{
        uint256 n = 3;
        uint256 initialDeposit = 10 ether;
        deal(address(mockWHype), address(vault), initialDeposit);
        (uint256 totalStaked, uint256 totalBorrowed,) = looping.executeLoop(n);
        console.log("totalStaked : ", totalStaked);     // 32356560000000000000 = 32.35e18 for n = 3
        console.log("totalBorrowed : ", totalBorrowed); // 22356560000000000000 = 22.35e18 for n = 3
    }

    // while looping, I have tested various scenarios reverting by making changes to the actual `executeLoop` function and studying the  error messages 

    modifier fundVault(uint256 amount){
        deal(address(mockWHype), address(vault), amount);
        _;
    }

    function testExitLoopWorks_OneLoop() public fundVault(10e18){
        uint256 n = 1;
        (,,uint256 initialBalance) = looping.executeLoop(n);
        uint256 elapsed = 365 days;
        vm.warp(block.timestamp + elapsed);
        mockMorpho.accrueInterest(MARKET_ID);
        mockOverseer.rebase();
        looping.executeExitLoop(n, initialBalance);

        // run these exit-loop tests using `-vv` for visual clarity
    }

    // note : change the value of `n` and run 
    function testExitLoopWorks_MultipleLoops() public fundVault(10e18){
        uint256 n = 6;
        (,,uint256 initialBalance) = looping.executeLoop(n);
        uint256 elapsed = 365 days;
        vm.warp(block.timestamp + elapsed);
        mockMorpho.accrueInterest(MARKET_ID); // ❗️❗️❗️❗️❗️❗️❗️❗️ have to do this so start of the exit loop(else, `currentTotalBorrow` will remain 8.6e18)
        mockOverseer.rebase(); // just for good measure
        // uint256 expectedWHypeBalance = ((totalStaked*APY * elapsed)/(365 days * 100)) + totalStaked;
        // console.log("expectedWHypeBalance : ", expectedWHypeBalance);

        console.log("starting stHype vault balance(should have increased due to rebasing) : ", mockStHype.balanceOf(address(vault)));

        looping.executeExitLoop(n, initialBalance);
        // console.log("finalHypeBalance : ", finalHypeBalance); // 10000000000000000000 = 10e18 
        // uint256 actualWHypeBalance = mockOverseer.calculateShareValue(address(vault));
        // console.log("actualWHypeBalance : ", actualWHypeBalance);
        // uint256 finalWhype = looping.executeFinishExitLoop(actualWHypeBalance);
        // console.log("finalWhypeBalance of vault: ", finalWhype);
    }

    function testExitLoop_LargeNumberOfLoops() public fundVault(10e18){
        uint256 n = 7;
        (,,uint256 initialBalance) = looping.executeLoop(n);
        uint256 elapsed = 365 days;
        vm.warp(block.timestamp + elapsed);
        mockMorpho.accrueInterest(MARKET_ID); // ❗️❗️❗️❗️❗️❗️❗️❗️ have to do this so start of the exit loop(else, `currentTotalBorrow` will remain 8.6e18)
        mockOverseer.rebase();
        console.log("starting stHype vault balance(should have increased due to rebasing) : ", mockStHype.balanceOf(address(vault)));

        looping.executeExitLoop(n, initialBalance);
    }
    // 3976344086021505376344087

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
        uint256 fundAmount = 1000 ether;
        deal(address(wHype), address(this), fundAmount);
        wHype.approve(address(morpho), fundAmount);
        wHype.transfer(address(morpho), fundAmount);

        networkConfig = NetworkConfig({
            chainId: chainId,
            wHype: address(wHype),
            stHype: address(stHype),
            overseer: address(overseer),
            wstHype: address(wstHype),
            morpho: address(morpho)
        });
    }

    /*//////////////////////////////////////////////////////////////
                              MATHS TESTS
    //////////////////////////////////////////////////////////////*/

    function calculateStartingAmount(uint256 n, uint256 startingVaultBalance, uint256 ltv, uint256 WAD) external pure returns (uint256) {
        return (startingVaultBalance * (ltv**n))/(WAD**n);
    }   

    function test_StartingAmountCalculation_OverflowsForLarge_N() public{
        // for n>=4 , the following calculation overflows(for starting amount = 10e18)
        uint256 n = 4;
        uint256 startingVaultBalance = 10 ether;
        uint256 ltv = 0.86 ether;
        uint256 WAD = 1e18;

        vm.expectRevert();
        uint256 startingAmount = this.calculateStartingAmount(n,startingVaultBalance,ltv,WAD);
        console.log("For n = ", n,", starting amount : ", startingAmount);

        // to check this test was reverting
        // 1. use vm.expectRevert
        // 2. but it works on functions, so have to create a separate function to do the calculation in which I am expecting a revert 
        // 3. also the function must be EXTERNAL
    }

    function test_StartingAmountCalculation_NewMethod() public pure {
        uint256 n = 5;
        uint256 startingVaultBalance = 10 ether;
        uint256 ltv = 0.86 ether;
        uint256 WAD = 1e18;

        // uint256 startingAmount = (startingVaultBalance * (ltv**n))/(WAD**n);
        uint256 startingAmount = startingVaultBalance * ltv/WAD;
        for(uint i = 0;i<n-1;i++){
            startingAmount = (startingAmount * ltv)/1e18;
        }
        console.log("For n = ", n,", starting amount : ", startingAmount);
    }
}

// 2105779789937698301 = 2.1 