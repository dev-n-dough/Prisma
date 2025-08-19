// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {IStHYPE} from "../interfaces/IStHYPE.sol";
import {IWHYPE} from "../interfaces/IWHYPE.sol";
import {IWstHype} from "../interfaces/IWstHype.sol";
import {IOverseer} from "../interfaces/IOverseer.sol";
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
import {SharesMathLib} from "../libraries/SharesMathLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {console} from "forge-std/console.sol";

contract CustomAccountant is Auth {
    using SharesMathLib for uint256;

    BoringVault public immutable vault;
    AccountantWithRateProviders public immutable accountant;
    address public immutable stHype;
    address public immutable wHype;
    address public immutable wstHype;
    address public immutable overseer;
    address public immutable morpho;
    Id public immutable marketId;

    // Events 
    event ExchangeRateCalculated(
        uint256 wHypeBalance,
        uint256 stHypeValue,
        uint256 morphoNetValue,
        uint256 totalValue,
        uint256 totalShares,
        uint96 newExchangeRate
    );

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _stHype,
        address _wHype,
        address _wstHype,
        address _overseer,
        address _morpho,
        Id _marketId
    ) Auth(_owner, Authority(address(0))) {
        vault = BoringVault(payable(_vault));
        accountant = AccountantWithRateProviders(_accountant);
        stHype = _stHype;
        wHype = _wHype;
        wstHype = _wstHype;
        overseer = _overseer;
        morpho = _morpho;
        marketId = _marketId;
    }

    /**
     * @notice Calculate the current vault value and update the exchange rate
     * @dev This should be called periodically (daily/weekly) to update share prices
     */
    function updateExchangeRate() external requiresAuth {
        uint256 totalVaultValue = calculateTotalVaultValue();
        uint256 totalShares = vault.totalSupply();
        
        // Avoid division by zero
        if (totalShares == 0) return;
        
        // Calculate new exchange rate: total value per share
        // Exchange rate is typically in 18 decimals
        uint96 newExchangeRate = uint96((totalVaultValue * 1e18) / totalShares);
        
        // Update the accountant 
        accountant.updateExchangeRate(newExchangeRate);
        // console.log("From CustomAccountant::updateExchangeRate");
        // console.log("newExchangeRate : ", newExchangeRate);
        
        emit ExchangeRateCalculated(
            getWHypeBalance(),
            getStHypeValueInWHype(),
            getMorphoNetPositionInWHype(),
            totalVaultValue,
            totalShares,
            newExchangeRate
        );
    }

    /**
     * @notice Calculate total vault value in wHYPE terms
     * @return Total value of all vault positions
     */
    function calculateTotalVaultValue() public view returns (uint256) {
        // 1. Direct wHYPE balance
        uint256 wHypeBalance = getWHypeBalance();
        
        // 2. Convert stHYPE to wHYPE equivalent
        uint256 stHypeValue = getStHypeValueInWHype();
        
        // 3. Get net Morpho position value (collateral - debt)
        uint256 morphoNetValue = getMorphoNetPositionInWHype();
        
        return wHypeBalance + stHypeValue + morphoNetValue; // all in 18 decimals only 
    }

    /**
     * @notice Get direct wHYPE balance
     */
    function getWHypeBalance() public view returns (uint256) {
        return IWHYPE(wHype).balanceOf(address(vault));
        // if someone deposits after we start our startegy, that would be reflected here
    }

    /**
     * @notice Convert stHYPE balance to wHYPE equivalent
     */
    function getStHypeValueInWHype() public view returns (uint256 stHypeBalance) {
        // if rebase has happened then this will show updated value
        // note remember to call `rebase` in mock testing before updating the exchange rate 
        stHypeBalance = IStHYPE(stHype).balanceOf(address(vault));
    }

    /**
     * @notice Get net Morpho position value (collateral - debt) in wHYPE terms
     */
    function getMorphoNetPositionInWHype() public view returns (uint256) {

        (
            ,
            ,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            ,
            
        ) = IMorphoStaticTyping(morpho).market(marketId);
        (,uint128 borrowShares,uint128 collateral) = IMorphoStaticTyping(morpho).position(marketId, address(vault));
        uint256 borrowAssets = 0;
        if (collateral == 0 && borrowShares == 0) {
            return 0; // No position
        }
        if (borrowShares > 0) {
            borrowAssets = uint256(borrowShares).toAssetsUp(totalBorrowAssets, totalBorrowShares);
        }

        uint256 collateralValue = convertWstHypeToWHype(collateral);

        // Net position = collateral value - debt
        if (collateralValue >= borrowAssets) {
            return collateralValue - borrowAssets;
        } else {
            // In case of bad debt (shouldn't happen with proper LTV)
            return 0;
        }
    }

    /**
     * @notice Convert wstHYPE to wHYPE equivalent
     */
    function convertWstHypeToWHype(uint256 wstHypeAmount) public view returns (uint256) {
        if (wstHypeAmount == 0) return 0;
        // wstHypeAmount -> this is essentially stHype shares in 18 decimals
        uint256 decimals = IStHYPE(stHype).balanceToShareDecimals(); // should be 10^6
        uint256 stHypeShares = wstHypeAmount * decimals;
        uint256 stHypeBalance = IStHYPE(stHype).sharesToBalance(stHypeShares);
        return stHypeBalance;
    }

    /**
     * @notice Get detailed breakdown of all vault positions
     */
    function getPositionBreakdown() 
        external 
        view 
        returns (
            uint256 wHypeBalance,
            uint256 stHypeValue,
            uint256 morphoCollateralValue,
            uint256 morphoBorrowValue,
            uint256 morphoNetValue,
            uint256 totalValue
        ) 
    {
        address vaultAddress = address(vault);
        wHypeBalance = getWHypeBalance();
        stHypeValue = getStHypeValueInWHype();
        
        // Get detailed Morpho breakdown
        (
            ,
            uint128 borrowShares,
            uint128 collateral
        ) = IMorphoStaticTyping(morpho).position(marketId, vaultAddress);

        morphoCollateralValue = convertWstHypeToWHype(collateral);
        
        if (borrowShares > 0) {
            (
                ,
                ,
                uint128 totalBorrowAssets,
                uint128 totalBorrowShares,
                ,
            ) = IMorphoStaticTyping(morpho).market(marketId);
            
            morphoBorrowValue = uint256(borrowShares).toAssetsUp(totalBorrowAssets, totalBorrowShares);
        }
        
        morphoNetValue = morphoCollateralValue >= morphoBorrowValue 
            ? morphoCollateralValue - morphoBorrowValue 
            : 0;
            
        totalValue = wHypeBalance + stHypeValue + morphoNetValue;
    }

    /**
     * @notice Preview what the new exchange rate would be without updating
     */
    function previewExchangeRate() external view returns (uint96 newExchangeRate, uint256 totalValue) {
        totalValue = calculateTotalVaultValue();
        uint256 totalShares = vault.totalSupply();

        console.log("From CustomAccountant::previewExchangeRate");
        console.log("totalValue : ", totalValue); // 110000000000000000000 == 110e18
        console.log("totalShares : ", totalShares); // 100000000000000000000000000 = 100e24
        
        if (totalShares == 0) {
            newExchangeRate = 1e18; // Default rate
        } else {
            newExchangeRate = uint96((totalValue * 1e24) / totalShares); // @follow-up , I think this is correct since exchange rate must be in 18 decimals
        }
    }
}