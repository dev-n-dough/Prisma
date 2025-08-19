
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {IStHYPE} from "../../src/interfaces/IStHYPE.sol";

interface IStHypeRebasing is IStHYPE{
    function rebase(uint256 rewards) external;
}

uint256 constant MAX_REDEEMABLE = 100000 ether; // not used in this mock
uint256 constant APY = 200; // 2% APY in basis points
uint256 constant SECONDS_PER_YEAR = 365 * 24 * 60 * 60;

contract MockOverseer {
    
    IStHypeRebasing public stHype;
    
    uint256 public lastRebaseTime;
    uint256 public totalOriginalStaked; // Track original stakes for stats 
    
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Rebased(uint256 rewards, uint256 newTotalSupply);
    
    constructor(address _stHype) {
        stHype = IStHypeRebasing(_stHype);
        lastRebaseTime = block.timestamp;
    }
    
    function mint(address to, string memory) external payable {
        require(msg.value > 0, "Cannot stake 0 tokens");
        
        // Rebase before minting
        _triggerRebase();
        
        totalOriginalStaked += msg.value;
        stHype.mint(to, msg.value);
        
        emit Staked(to, msg.value);
    }
    

    function burnAndRedeemIfPossible(address to, uint256 amount, string memory) external returns (bool) {
        require(amount > 0, "Amount must be greater than 0");
        
        // Rebase before burning
        _triggerRebase();
        
        require(stHype.balanceOf(msg.sender) >= amount, "Insufficient stHYPE balance");
        require(address(this).balance >= amount, "Insufficient contract balance");
        
        // Burn stHYPE and send ETH
        stHype.burn(msg.sender, amount);
        
        payable(to).transfer(amount);
        
        emit Unstaked(msg.sender, amount);
        return true;
    }
    
    function rebase() external {
        _triggerRebase();
    }
    
    function _triggerRebase() internal {
        uint256 timeElapsed = block.timestamp - lastRebaseTime;
        
        if (timeElapsed == 0) return; // No time passed
        
        uint256 currentSupply = stHype.totalSupply();
        if (currentSupply == 0) return; // No tokens to rebase
        
        // Calculate rewards: totalSupply * APY * timeElapsed / secondsPerYear 
        uint256 rewards = (currentSupply * APY * timeElapsed) / (10000 * SECONDS_PER_YEAR);
        
        if (rewards > 0) {
            // Add rewards to the pool - everyone's balance increases automatically!
            stHype.rebase(rewards);
            emit Rebased(rewards, currentSupply + rewards);
        }
        
        lastRebaseTime = block.timestamp;
    }
    
    function currentValueOf(address user) external view returns (uint256) {
        return stHype.balanceOf(user);
    }
    

    function getContractStats() external view returns (
        uint256 _totalOriginalStaked,
        uint256 totalStHypeSupply,
        uint256 contractBalance,
        uint256 totalRewards
    ) {
        _totalOriginalStaked = totalOriginalStaked;
        totalStHypeSupply = stHype.totalSupply();
        contractBalance = address(this).balance;
        totalRewards = totalStHypeSupply > _totalOriginalStaked ? 
            totalStHypeSupply - _totalOriginalStaked : 0;
    }
    

    function pendingRebaseRewards() external view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastRebaseTime;
        uint256 currentSupply = stHype.totalSupply();
        
        if (timeElapsed == 0 || currentSupply == 0) return 0;
        
        return (currentSupply * APY * timeElapsed) / (10000 * SECONDS_PER_YEAR);
    }
    

    function getRebaseInfo() external view returns (
        uint256 lastRebase,
        uint256 nextRebaseRewards,
        uint256 currentAPY,
        uint256 timeSinceLastRebase
    ) {
        lastRebase = lastRebaseTime;
        nextRebaseRewards = this.pendingRebaseRewards();
        currentAPY = APY;
        timeSinceLastRebase = block.timestamp - lastRebaseTime;
    }
    
    function maxRedeemable() external pure returns (uint256) {
        return MAX_REDEEMABLE;
    }
    
    function getExchangeRate() external pure returns (uint256) {
        return 1e18;
    }
    
    // Allow contract to receive ETH
    receive() external payable {}
}
