// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IOverseer} from "../interfaces/IOverseer.sol";
import {IStHYPE} from "../interfaces/IStHYPE.sol";
import {IWHYPE} from "../interfaces/IWHYPE.sol";
import {IWstHype} from "../interfaces/IWstHype.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "@boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {StHYPEDecoderAndSanitizer} from "../decoders/StHYPEDecoderAndSanitizer.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {MerkleTreeHelper, ChainValues} from "@boring-vault/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {console} from "forge-std/console.sol";
import {
    Id,
    IMorphoStaticTyping,
    IMorphoBase,
    MarketParams,
    Position,
    Market,
    Authorization,
    Signature
} from "../interfaces/IMorpho.sol";
import {AtomicSolverV3, AtomicQueue} from "@boring-vault/src/atomic-queue/AtomicSolverV3.sol";
import {Strategy} from "./Strategy.sol";
import {SharesMathLib} from "../libraries/SharesMathLib.sol";

import {console} from "forge-std/console.sol";

// 1. contain looping logic 
// 2. some other defi helper functions if needed 

contract Looping is Strategy{
    using SharesMathLib for uint256;

    constructor(
        address _manager,
        address _vault,
        address _wHype,
        address _stHype,
        address _overseer,
        address _decoderAndSanitizer,
        address _owner,
        address _wstHype,
        address _morpho
    ) Strategy(_manager,_vault,_wHype,_stHype,_overseer,_decoderAndSanitizer,_owner,_wstHype,_morpho) {} 

    // for now, am only writing for the scenario that all the wHype has been deposited into vault. I will execute my full strategy, then after some time I will unwind everything and will allow users to withdraw 
    function executeLoop(uint256 n) public returns(uint256 totalStaked, uint256 totalBorrowed, uint256 initialVaultBalance){

        // 1. assume that before this function is called, user has already deposited some money
        // 2. stake that money
        // 3. run the following loop `n` times - supply collat,borrow,stake
        
        uint256 amount = IWHYPE(wHype).balanceOf(address(vault));
        initialVaultBalance = amount;
        executeStaking(amount, "");
        totalStaked+=amount;
        uint256 wstBalance = IWstHype(wstHype).balanceOf(address(vault));
        (,,,, uint256 ltv) = IMorphoStaticTyping(morpho).idToMarketParams(MARKET_ID_MAINNET);
        // uint256 stakingMultFactor = 1e18/IStHYPE(stHype).balancePerShare(); // I am unsure of this part // TODO 
        // now begin the loop 
        uint256 borrowAmount = 0; 
        for(uint256 i=0;i<n;i++){
            executeSupplyCollateral(wstBalance);
            // wHypeAmount = IWHYPE(wHype).balanceOf(address(vault)); 
            borrowAmount = wstBalance * ltv/1e18;
            executeBorrow(borrowAmount);
            // I will get back `borrowAmount` of stHype
            executeStaking(borrowAmount,"");
            totalStaked+=borrowAmount;
            wstBalance = borrowAmount;
        }
        // totalStaked = IStHYPE(stHype).balanceOf(address(vault));
        (, uint128 borrowShares, ) = IMorphoStaticTyping(morpho).position(MARKET_ID_MAINNET, address(vault));
        (
            ,
            ,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            ,
            
        ) = IMorphoStaticTyping(morpho).market(MARKET_ID_MAINNET);
        totalBorrowed = uint256(borrowShares).toAssetsDown(totalBorrowAssets,totalBorrowShares);
        // initialVaultBalance = amount;
    }

    function executeExitLoop(uint256 n, uint256 initialVaultBalance) public{ 

        console.log("Starting to exit the loop!\n");
        
        // i am 95% sure that this `stakingMultFactor` is wrong, but I will go forward with this until I test with actual contracts 
        (,,,, uint256 ltv) = IMorphoStaticTyping(morpho).idToMarketParams(MARKET_ID_MAINNET);
        // uint256 stakingMultFactor = 1e18/IStHYPE(stHype).balancePerShare(); // 1 for now. 
        // uint256 stakingMultFactor = 1; // 1 for now. 

        // uint256 startingAmount = initialVaultBalance * (ltv**n) * (stakingMultFactor**(n+1))/(1e18**n);
        // uint256 startingAmount = initialVaultBalance * (ltv**n)/(1e18**n);
        uint256 startingAmount = calculateStartingAmount(n,initialVaultBalance,ltv);
        // uint256 startingAmount = 0;
        console.log("startingAmount : ", startingAmount);

        uint256 sharesRepay = 0;
        // uint256 assetsAmount = 0;
        uint256 unstakeAmount = 0;
        uint256 collatAmount = 0;
        uint256 outstandingBorrowAmount = type(uint256).max; // so that we enter the loop
        // unstakeAmount = (startingAmount * currentTotalBorrow/totalBorrowed); // debt of one iteration with its interest 
        unstakeAmount = IStHYPE(stHype).balanceOf(address(vault));
        console.log("initial stHype balance [THE START] : ", unstakeAmount);
        console.log("wHype balance just before the first ever unstaking [THE START] : ", IWHYPE(wHype).balanceOf(address(vault)));
        executeUnstaking(unstakeAmount,""); // e here we have to mention the amount of `hype` we wanna pull out. 
        console.log("wHype balance just after unstaking [FIRST UNSTAKE]: ", IWHYPE(wHype).balanceOf(address(vault)));
        uint256 wHypeBalanceVault = IWHYPE(wHype).balanceOf(address(vault));
        // for(uint i = 0;i<n;i++){
        while(wHypeBalanceVault < outstandingBorrowAmount){
            console.log("before repaying");
            // (uint128 borrowShares,,) = getTotalBorrowSharesAndAssets();
            // sharesRepay = (startingAmount*borrowShares)/totalBorrowed;
            // executeRepayUsingShares(sharesRepay);
            executeRepayUsingAssets(wHypeBalanceVault);
            console.log("after repaying");

            // how much collat to withdraw?
            // outstanding debt ko cover kar le, utna chodd de, baaki nikal le 
            (,uint256 borrowAssets,uint128 totalCollat) = getTotalBorrowSharesAndAssets();
            collatAmount = totalCollat - (borrowAssets*1e18)/ltv - 2; // this `-2` is for safety, just in case there are some rounding issues anywhere. all this dust collateral would anyways be withdrawn after the loop ends
            (,,uint128 collat) = IMorphoStaticTyping(morpho).position(MARKET_ID_MAINNET, address(vault));
            console.log("collat to withdraw : ", collatAmount);
            console.log("collateral amount before withdrawing : ", totalCollat);
            executeWithdrawCollateral(collatAmount);
            (,,collat) = IMorphoStaticTyping(morpho).position(MARKET_ID_MAINNET, address(vault));
            console.log("collateral amount after withdrawing : ", collat);
            console.log("Collateral withdrawn!");
            startingAmount = startingAmount*1e18/ltv;

            // unstake however much you have

            unstakeAmount = IStHYPE(stHype).balanceOf(address(vault));
            console.log("unstakeAmount : ", unstakeAmount);
            console.log("wHype balance just before unstaking : ", IWHYPE(wHype).balanceOf(address(vault)));
            executeUnstaking(unstakeAmount,"");
            console.log("wHype balance just after unstaking : ", IWHYPE(wHype).balanceOf(address(vault)));



            // after this iteration, find 2 things
            // 1. wHype balance of vault
            // 2.  outstanding borrow amount
            console.log("\n\nStatistics at the end of this iteration\n\n");
            wHypeBalanceVault = IWHYPE(wHype).balanceOf(address(vault));
            console.log("wHype balance of vault : ", wHypeBalanceVault);
            (,outstandingBorrowAmount,) = getTotalBorrowSharesAndAssets();

            console.log("\n///////////  One iteration of the loop complete ////////////////\n");
        }

        console.log("\n\nLoop ended\n\n");
        getTotalBorrowSharesAndAssets();
        console.log("final stHype balance : ", IStHYPE(stHype).balanceOf(address(vault)));

        // 9612777204301075267 = 9.6e18
        // 4016107526881720430 = 4e18 
        // so repay full amount then withdraw full collat

        // do I have any stHype left to redeem?
        console.log("stHype balance after loop ended : ", IStHYPE(stHype).balanceOf(address(vault)));

        console.log("Proceeding with the last step : repay remaining loan and unstake full");
        // right now I have a bunch of wHype, and my balance is exceeding borrow amount, so repay in full
        (sharesRepay,,) = getTotalBorrowSharesAndAssets();
        if(sharesRepay > 0){
            executeRepayUsingShares(sharesRepay);
        }
        (,,collatAmount) = getTotalBorrowSharesAndAssets();
        // withdraw collat
        if(collatAmount > 0){
            executeWithdrawCollateral(collatAmount);
        }
        getTotalBorrowSharesAndAssets();
        // unstake fully
        if(IStHYPE(stHype).balanceOf(address(vault)) > 0){
            executeUnstaking(IStHYPE(stHype).balanceOf(address(vault)),"");
        }
        console.log("final stHype balance : ", IStHYPE(stHype).balanceOf(address(vault)));
        console.log("final wHype balance of vault after fully exiting the loop : ", IWHYPE(wHype).balanceOf(address(vault))); 
        // 10286000000000000000 = 10.28e18 -> `n=1` (for 1 year)
        // 10359960000000000000 = 10.36e18 -> `n=2`
        // 10423565600000000000 = 10.42e18 -> `n=3`

        console.log("\n\n strategy unwind complete!"); 
    }

    function calculateStartingAmount(uint256 n, uint256 startingVaultBalance, uint256 ltv) public pure returns(uint256){
        uint256 WAD = 1e18;
        
        uint256 startingAmount = startingVaultBalance * ltv/WAD;
        for(uint i = 0;i<n-1;i++){
            startingAmount = (startingAmount * ltv)/1e18;
        }
        return startingAmount;
    }

    function getTotalBorrowSharesAndAssets() public view returns(uint128 borrowShares, uint256 borrowAssets, uint128 collateral){
        (
            ,
            ,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            ,
            
        ) = IMorphoStaticTyping(morpho).market(MARKET_ID_MAINNET);
        (,borrowShares,collateral) = IMorphoStaticTyping(morpho).position(MARKET_ID_MAINNET, address(vault));
        borrowAssets = uint256(borrowShares).toAssetsUp(totalBorrowAssets,totalBorrowShares);
        console.log("borrowShares : ", borrowShares);
        console.log("borrowAssets : ", borrowAssets);
        console.log("collateral : ", collateral);
    }

    // function executeFinishExitLoop(uint256 finalHypeToUnstake) public returns(uint256 finalWHypeBalance){
    //     executeUnstaking(finalHypeToUnstake,"");
    //     finalWHypeBalance = IWHYPE(wHype).balanceOf(address(vault));
    // }

}

// 659787331 = 6.59e8 => Felix Borrow rate

// staking APY = 2.44%
// per second : ~6.92e9 == 69.2e8
// 69.2e8 > 6.59e8 


////////// IF SOMETHING BREAKS, LOOK AT THE FOLLOWING
// - `stakingMultFactor` => mp we are getting 1 stHype per 1 hype so this should NOT be taken into account
// - rebasing mech of stHype, mp the sthype in my wallet will increase in balance, so after the full unwinding, I would have to burn all my remaining stHype to get the rewards, but thinking about it, i would have to burn these extra shares during unwinding, because that yield is what will pay for the borrow interest 

// 86000000000000000 = 0.086e18 