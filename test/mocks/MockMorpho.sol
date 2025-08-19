// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
import {
    IMorphoLiquidateCallback,
    IMorphoRepayCallback,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback,
    IMorphoFlashLoanCallback
} from "../../src/interfaces/IMorphoCallbacks.sol";

uint256 constant WAD = 1e18;
// uint256 constant INTEREST_RATE = 633620772; // actual APY taken from block explorer - for compound 
uint256 constant INTEREST_RATE = 1; // 1% simple interest per year
uint256 constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;

import {MathLib} from "../../src/libraries/MathLib.sol";
import {SharesMathLib} from "../../src/libraries/SharesMathLib.sol";
import {MarketParamsLib} from "../../src/libraries/MarketParamsLib.sol";

contract MockMorpho {
    using SharesMathLib for uint256;
    using MathLib for uint256;
    using MathLib for uint128;
    
    // Events 
    event SupplyCollateral(Id indexed id, address indexed supplier, address indexed onBehalf, uint256 assets, uint256 shares);
    event WithdrawCollateral(Id indexed id, address indexed supplier, address indexed onBehalf, address receiver, uint256 assets, uint256 shares);
    event Borrow(Id indexed id, address indexed borrower, address indexed onBehalf, address receiver, uint256 assets, uint256 shares);
    event Repay(Id indexed id, address indexed repayer, address indexed onBehalf, uint256 assets, uint256 shares);
    event SetAuthorization(address indexed authorizer, address indexed authorized, bool newIsAuthorized);

    // Storage
    mapping(Id => MarketParams) public idToMarketParams;
    mapping(Id => Market) public market;
    mapping(Id => mapping(address => Position)) public position;
    mapping(address => mapping(address => bool)) public isAuthorized;
    
    // Mock market configuration
    Id public constant MARKET_ID = Id.wrap(0xe9a9bb9ed3cc53f4ee9da4eea0370c2c566873d5de807e16559a99907c9ae227);
    
    uint256 public lastUpdateTimestamp;
    

    // ✅
    constructor(
        address loanToken,    // wHYPE
        address collateralToken// wstHYPE
    ) {
        // Initialize the main market with 86% LTV (0.86 * 1e18)
        uint256 lltv = 860000000000000000; // 86% LTV - can borrow up to 86% of collateral value
        MarketParams memory params = MarketParams({
            loanToken: loanToken,
            collateralToken: collateralToken,
            oracle: address(2),
            irm: address(3),
            lltv: lltv
        });
        
        idToMarketParams[MARKET_ID] = params;
        
        // Initialize market state
        market[MARKET_ID] = Market({
            totalSupplyAssets: 0,
            totalSupplyShares: 0,
            totalBorrowAssets: 0,
            totalBorrowShares: 0,
            lastUpdate: uint128(block.timestamp),
            fee: 0
        });
        
        lastUpdateTimestamp = block.timestamp;
        // Fund the contract with some loan tokens for borrowing
    }
    
    // ✅
    function setAuthorization(address authorized, bool newIsAuthorized) external {
        isAuthorized[msg.sender][authorized] = newIsAuthorized;
        emit SetAuthorization(msg.sender, authorized, newIsAuthorized);
    }
    
    // ✅
    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes calldata data
    ) external {
        require(_isAuthorizedFor(onBehalf, msg.sender), "Not authorized");
        Id id = MARKET_ID;

        // Update market state with interest
        accrueInterest(id);
        
        // Transfer collateral tokens to this contract
        IERC20(marketParams.collateralToken).transferFrom(msg.sender, address(this), assets);
        
        // Update position
        position[id][onBehalf].collateral += uint128(assets);
        
        // Callback if provided
        if (data.length > 0) {
            IMorphoSupplyCollateralCallback(msg.sender).onMorphoSupplyCollateral(assets, data);
        }
        
        emit SupplyCollateral(id, msg.sender, onBehalf, assets, assets); // 1:1 ratio for simplicity
    }

    // ✅
    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external {
        require(_isAuthorizedFor(onBehalf, msg.sender), "Not authorized");
        Id id = MARKET_ID;
        
        // Update market state with interest
        accrueInterest(id);
        
        Position storage pos = position[id][onBehalf];
        require(pos.collateral >= assets, "Insufficient collateral");
        
        pos.collateral -= uint128(assets);
        require(_isHealthy(id, pos.collateral, pos.borrowShares), "Unhealthy position");

        // Transfer collateral tokens to receiver
        IERC20(marketParams.collateralToken).transfer(receiver, assets);
        
        emit WithdrawCollateral(id, msg.sender, onBehalf, receiver, assets, assets);
    }
    
    // ✅
    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed) {
        Id id = MARKET_ID;
        require(_isAuthorizedFor(onBehalf, msg.sender), "Not authorized");
        
        // Update market state with interest
        accrueInterest(id);
        
        // Use assets if shares is 0, otherwise use shares
        if (shares == 0) {
            sharesBorrowed = assets.toSharesUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
            assetsBorrowed = assets;
        } else {
            assetsBorrowed = shares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
            sharesBorrowed = shares;
        }
        
        // Check if borrow is safe
        Position storage pos = position[id][onBehalf];
        uint256 newBorrowShares = pos.borrowShares + sharesBorrowed;
        require(_isHealthy(id, pos.collateral, newBorrowShares), "Unhealthy position");
        
        // Update position and market
        pos.borrowShares += uint128(sharesBorrowed);
        market[id].totalBorrowAssets += uint128(assetsBorrowed);
        market[id].totalBorrowShares += uint128(sharesBorrowed);
        
        // Transfer loan tokens to receiver
        IERC20(marketParams.loanToken).transfer(receiver, assetsBorrowed);
        
        emit Borrow(id, msg.sender, onBehalf, receiver, assetsBorrowed, sharesBorrowed);
    }
    

    // ✅
    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        Id id = MARKET_ID;

        // Update market state with interest
        accrueInterest(id);
        
        Position storage pos = position[id][onBehalf];
        
        // Calculate actual repayment amounts
        if (shares == 0) {
            sharesRepaid = assets.toSharesDown(market[id].totalBorrowAssets, market[id].totalBorrowShares);
            assetsRepaid = assets;
        } else {
            assetsRepaid = shares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
            sharesRepaid = shares;
        }
        
        // Cap at actual borrowed amount
        if (sharesRepaid > pos.borrowShares) {
            sharesRepaid = pos.borrowShares;
            assetsRepaid = SharesMathLib.toAssetsDown(sharesRepaid, market[id].totalBorrowAssets, market[id].totalBorrowShares);
        }
        
        // Transfer loan tokens from sender
        IERC20(marketParams.loanToken).transferFrom(msg.sender, address(this), assetsRepaid);
        
        // Update position and market
        pos.borrowShares -= uint128(sharesRepaid);
        market[id].totalBorrowAssets -= uint128(assetsRepaid);
        market[id].totalBorrowShares -= uint128(sharesRepaid);
        
        // Callback if provided
        if (data.length > 0) {
            IMorphoRepayCallback(msg.sender).onMorphoRepay(assetsRepaid, data);
        }
        
        emit Repay(id, msg.sender, onBehalf, assetsRepaid, sharesRepaid);
    }
    
    // View functions

    // ✅
    function borrowShares(Id id, address user) external view returns (uint256) {
        return position[id][user].borrowShares;
    }
    

    // ✅
    function collateral(Id id, address user) external view returns (uint256) {
        return position[id][user].collateral;
    }
    
    // Internal helper functions
    // ✅
    function _getMarketId(MarketParams memory params) internal pure returns (Id) {
        return MarketParamsLib.id(params);
    }
    
    // ✅
    function _isAuthorizedFor(address onBehalf, address sender) internal view returns (bool) {
        return onBehalf == sender || isAuthorized[onBehalf][sender];
    }
    
    // ✅
    function accrueInterest(Id id) public{
        Market storage marketData = market[id];
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        
        if (timeElapsed > 0 && marketData.totalBorrowAssets > 0) {
            // uint256 interest = marketData.totalBorrowAssets.wMulDown(INTEREST_RATE.wTaylorCompounded(timeElapsed));
            // uint256 interest = marketData.totalBorrowAssets.
            uint256 interestRate = (INTEREST_RATE * timeElapsed) / (SECONDS_PER_YEAR);
            uint256 interest = (marketData.totalBorrowAssets * interestRate) / 100;
            marketData.totalBorrowAssets += uint128(interest);
            marketData.lastUpdate = uint128(block.timestamp);
        }
        
        lastUpdateTimestamp = block.timestamp;
    }

    
    // ✅
    function _isHealthy(Id id, uint256 collateralAmount, uint256 _borrowShares) internal view returns (bool) {
        if (_borrowShares == 0) return true;
        
        Market storage marketData = market[id];
        uint256 borrowAssets = SharesMathLib.toAssetsUp(_borrowShares, marketData.totalBorrowAssets, marketData.totalBorrowShares);
        
        // Get market params
        MarketParams memory params = idToMarketParams[id];
        
        // Simple health check: collateral value > borrow value / lltv
        // Since wstHYPE price = 1 wHYPE (1:1 ratio), we can directly compare
        uint256 maxBorrow = collateralAmount.wMulDown(params.lltv);
        
        return borrowAssets <= maxBorrow;
    }
    
    // ✅
    function setMarketLltv(Id id, uint256 newLltv) external {
        idToMarketParams[id].lltv = newLltv;
    }

    function setPosition(Id id,address user,uint256 _supplyShares, uint128 _borrowShares,uint128 _collateral) public {
        Position memory pos;
        pos.supplyShares = _supplyShares;
        pos.borrowShares = _borrowShares;
        pos.collateral = _collateral;
        position[id][user] = pos;
    }

    function setMarket(
        Id id,
        uint128 totalSupplyAssets,
        uint128 totalSupplyShares,
        uint128 totalBorrowAssets,
        uint128 totalBorrowShares,
        uint128 lastUpdate,
        uint128 fee
    ) public {
        market[id] = Market({
            totalSupplyAssets: totalSupplyAssets,
            totalSupplyShares: totalSupplyShares,
            totalBorrowAssets: totalBorrowAssets,
            totalBorrowShares: totalBorrowShares,
            lastUpdate: lastUpdate,
            fee: fee
        });
    }
}