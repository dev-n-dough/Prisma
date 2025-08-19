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

// import Mocks
import {MockWHype} from "../mocks/MockWHype.sol";
import {MockOverseer} from "../mocks/MockOverseer.sol";
import {MockStHype} from "../mocks/MockStHype.sol";
import {MockWstHype} from "../mocks/MockWstHype.sol";
import {MockMorpho, INTEREST_RATE, SECONDS_PER_YEAR} from "../mocks/MockMorpho.sol";

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {SharesMathLib} from "../../src/libraries/SharesMathLib.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";

import {Id, IMorphoStaticTyping, IMorphoBase, MarketParams, Position, Market, Authorization, Signature} from "../../src/interfaces/IMorpho.sol";

contract StrategyTest is Test, MerkleTreeHelper {

    // Test all the atomic interactions listed in Strategy.sol

    using MathLib for uint256;

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
    Strategy public strategy;
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
        strategy = new Strategy(
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

        rolesAuthority.setUserRole(address(strategy), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(
            address(manager),
            MANGER_INTERNAL_ROLE,
            true
        );
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);
        rolesAuthority.setUserRole(address(vault), BORING_VAULT_ROLE, true);

        rolesAuthority.setPublicCapability(address(vault), bytes4(0), true);

        bytes32 manageRoot = strategy.getManageTreeRoot();
        // for these tests
        manager.setManageRoot(address(strategy), manageRoot);

        ///// SETUP MOCK CONTRACTS
        mockStHype = MockStHype(payable(config.stHype));
        mockOverseer = MockOverseer(payable(config.overseer));
        mockWHype = MockWHype(payable(config.wHype));
        deal(config.overseer, 100000 ether); // since it gives out more money than it receives(2% artificial yield)
        mockWstHype = MockWstHype(payable(config.wstHype));
        mockMorpho = MockMorpho(payable(config.morpho));
    }

    function test_stHype_works_unit() public view {
        uint256 totalSupply = IStHYPE(config.stHype).totalSupply();
        console.log(totalSupply);
    }

    function testStakingWorks_unit() public {
        // 1. dealing the vault some wHype dont work maybe because it is my custom implementation
        // 2. asking the vault to call `deposit` (to get some wHype) would require us to create a full fledged `Manager.manage` call, which would work but is just hectic
        // 3. best : deposit using a dummy account and transfer to the vault!
        uint256 amount = 10e18;
        address bob = makeAddr("bob");
        deal(bob, amount);
        mockWHype.deposit{value: amount}();
        mockWHype.transfer(address(vault), amount);
        assertEq(IWHYPE(config.wHype).balanceOf(address(vault)), amount);

        uint256 initialShares = mockStHype.balanceOf(address(vault));
        uint256 initialAssets = mockOverseer.currentValueOf(address(vault));
        strategy.executeStaking(amount, "");
        uint256 finalShares = mockStHype.balanceOf(address(vault));
        uint256 finalAssets = mockOverseer.currentValueOf(address(vault));

        assert(initialShares == 0);
        assert(initialAssets == 0);
        assert(finalShares == amount);
        assert(finalAssets == amount);

        // no need to check yield accumulation, as we have alr done that in `Mocks.t.sol`, and will do that in `LoopingUnit.t.sol` also
    }

    modifier stake(uint256 amount) {
        address bob = makeAddr("bob");
        deal(bob, amount);
        mockWHype.deposit{value: amount}();
        mockWHype.transfer(address(vault), amount);


        strategy.executeStaking(amount, "");
        _;
    }

    function testUnstaking() public stake(10e18) {
        uint256 stakeAmount = 10e18;
        uint256 amount = 4e18;
        strategy.executeUnstaking(amount, "");
        uint256 shares = mockStHype.balanceOf(address(vault));
        uint256 assets = mockOverseer.currentValueOf(address(vault));
        uint256 wHypeBalance = mockWHype.balanceOf(address(vault));
        assert(shares == stakeAmount - amount);
        assert(assets == stakeAmount - amount);
        assert(wHypeBalance == amount);
        // simple asserts since instant unstaking is taking place so no yield yet
    }

    function testUnstakeAfterSomeTime() public stake(10e18) {
        // uint256 stakeAmount = 10e18;
        uint256 unstakeAmount = 4e18;
        vm.warp(block.timestamp + 365 days / 2);
        mockOverseer.rebase();
        // now assets should be 10.1e18 == 101e17 
        uint256 initialStHype = mockStHype.balanceOf(address(vault));
        uint256 initialAssets = mockOverseer.currentValueOf(address(vault));
        uint256 initialWHypeBalance = mockWHype.balanceOf(address(vault));
        strategy.executeUnstaking(unstakeAmount, "");
        uint256 finalShares = mockStHype.balanceOf(address(vault));
        uint256 finalAssets = mockOverseer.currentValueOf(address(vault));
        uint256 finalWHypeBalance = mockWHype.balanceOf(address(vault));

        uint256 expectedInitialAssets = 101e17;
        uint256 expectedSharesBurn = unstakeAmount;

        // check approx equalities since shares calculation may involve rounding errors
        assertApproxEqAbs(initialStHype , expectedInitialAssets,100);
        assertApproxEqAbs(initialAssets , expectedInitialAssets,100);
        assertEq(initialWHypeBalance , 0);
        assertApproxEqAbs(
            finalShares,
            initialStHype - expectedSharesBurn,
            100
        ); // will be same upto the 2nd decimal, allow mismatch in the 3rd decimal
        assert(finalAssets == expectedInitialAssets - unstakeAmount);
        assert(finalWHypeBalance == unstakeAmount);
    }

    function testWrapUnit() public {
        uint256 hypeAmount = 15e18;
        uint256 wrapAmount = 6e18;
        deal(address(vault), hypeAmount);
        assert(address(vault).balance == hypeAmount);
        strategy.executeWrap(wrapAmount);
        assert(address(vault).balance == hypeAmount - wrapAmount);
        assert(mockWHype.balanceOf(address(vault)) == wrapAmount);
    }

    //////// MORPHO TESTS

    function testMorphoWorks() public view {
        uint256 lastUpdate = mockMorpho.lastUpdateTimestamp();
        console.log("lastUpdate : ", lastUpdate);
    }

    function testSupplyCollateralWorksUnit() public stake(10e18){
        uint256 collatAmount = 10e18;
        // deal(address(mockStHype), address(vault), collatAmount); -> instead of this, make the vault stake some amount 
        uint256 wstInitial = mockWstHype.balanceOf(address(vault));
        uint256 stInitial = mockStHype.balanceOf(address(vault));
        strategy.executeSupplyCollateral(collatAmount);
        uint256 wstFinal = mockWstHype.balanceOf(address(vault));
        uint256 stFinal = mockStHype.balanceOf(address(vault));
        assert(wstInitial - wstFinal == collatAmount);
        assert(stInitial - stFinal == collatAmount); // to prove stHype == wstHype 

        (
            uint256 supplyShares,
            uint128 borrowShares,
            uint128 collateral
        ) = mockMorpho.position(MARKET_ID, address(vault));
        assert(supplyShares == 0);
        assert(borrowShares == 0);
        assert(collateral == collatAmount);
    }

    modifier supplyCollat(uint256 amount) {
        // deal(address(mockStHype), address(vault), amount);
        strategy.executeSupplyCollateral(amount);
        _;
    }

    function testBorrowWorksUnit() public stake(10e18) supplyCollat(10e18) {
        uint256 collatAmount = 10e18;
        uint256 borrowAmount = (collatAmount * 8) / 10;
        uint256 initialBalance = mockWHype.balanceOf(address(vault));
        strategy.executeBorrow(borrowAmount);
        uint256 finalBalance = mockWHype.balanceOf(address(vault));
        assert(finalBalance - initialBalance == borrowAmount);

        (
            uint256 supplyShares,
            uint128 borrowShares,
            uint128 collateral
        ) = mockMorpho.position(MARKET_ID, address(vault));
        assert(supplyShares == 0);
        assert(borrowShares == borrowAmount * 10**6); // can use SharesMathLib to do this but I have checked this in Mocks.t.sol so not repeating here 
        assert(collateral == collatAmount);

        // console.log("borrowShares : ", borrowShares);
        // console.log("borrowAmount : ", borrowAmount);
    }

    modifier borrow(uint256 borrowAmount) {
        strategy.executeBorrow(borrowAmount);
        _;
    }

    function testRepayUsingAssetsWorksUnit() public stake(10e18) supplyCollat(10e18) borrow(8e18){
        // uint256 collatAmount = 10e18;
        uint256 borrowAmount = 8e18;
        strategy.executeRepayUsingAssets(borrowAmount);

        (
            ,
            uint128 borrowShares,
            
        ) = mockMorpho.position(MARKET_ID, address(vault));

        assertApproxEqAbs(borrowShares, 0, 100); // keep a margin of error due to rounding
    }

    function testRepayUsingAssetsAfterSomeTime() public stake(10e18) supplyCollat(10e18) borrow(8e18){
        // uint256 collatAmount = 10e18;
        uint256 borrowAmount = 8e18;
        uint256 elapsed = 5 days;
        vm.warp(block.timestamp + elapsed);

        // uint256 expectedInterest = borrowAmount.wMulDown(INTEREST_RATE.wTaylorCompounded(elapsed)); 
        uint256 interestRate = (INTEREST_RATE * elapsed) / (SECONDS_PER_YEAR);
        uint256 expectedInterest = (borrowAmount * interestRate) / 100;
        // deal(address(wHype), bob, expectedInterest);
        deal(address(mockWHype), address(vault), mockWHype.balanceOf(address(vault)) + expectedInterest);
        uint256 repayAmount = borrowAmount + expectedInterest;
        strategy.executeRepayUsingAssets(repayAmount);
    }

    function testRepayUsingSharesWorks() public stake(10e18) supplyCollat(10e18) borrow(8e18){
        // uint256 collatAmount = 10e18;
        uint256 borrowAmount = 8e18;
        strategy.executeRepayUsingShares(borrowAmount * 10**6);

        (,uint128 borrowShares,) = mockMorpho.position(MARKET_ID, address(vault));
        assert(borrowShares == 0);
    }

    function testRepayUsingSharesAfterSomeTime() public stake(10e18) supplyCollat(10e18) borrow(8e18){
        // uint256 collatAmount = 10e18;
        uint256 borrowAmount = 8e18;
        uint256 elapsed = 5 days;
        vm.warp(block.timestamp + elapsed);

        // uint256 expectedInterest = borrowAmount.wMulDown(INTEREST_RATE.wTaylorCompounded(elapsed)); 
        uint256 interestRate = (INTEREST_RATE * elapsed) / (SECONDS_PER_YEAR);
        uint256 expectedInterest = (borrowAmount * interestRate) / 100;
        // deal(address(wHype), bob, expectedInterest);
        deal(address(mockWHype), address(vault), mockWHype.balanceOf(address(vault)) + expectedInterest);
        // uint256 repayAmount = borrowAmount + expectedInterest;
        strategy.executeRepayUsingShares(borrowAmount * 10**6);
        (,uint128 borrowShares,) = mockMorpho.position(MARKET_ID, address(vault));
        assert(borrowShares == 0);
    }

    function testWithdrawCollateralWorksUnit() public stake(10e18) supplyCollat(10e18){
        uint256 collatAmount = 10e18;
        strategy.executeWithdrawCollateral(collatAmount);

        (
            uint256 supplyShares,
            uint128 borrowShares,
            uint128 collateral
        ) = mockMorpho.position(MARKET_ID, address(vault));
        assert(supplyShares == 0);
        assert(borrowShares == 0);
        assert(collateral == 0);
    }

    function testWithdrawCollatFails_IfNoCollatExists() public{
        vm.expectRevert("Insufficient collateral");
        strategy.executeWithdrawCollateral(1e18);
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
}
