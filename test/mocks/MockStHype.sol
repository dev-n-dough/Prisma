// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

contract MockStHype is IERC20 {

    // ==================== EVENTS ====================
    
    event Rebase(uint256 oldSupply, uint256 newSupply, uint256 rewardsAdded);

    
    string public name = "Staked Hype";
    string public symbol = "stHYPE";
    uint8 public decimals = 18;
    
    // True rebasing state
    mapping(address => uint256) private _shares; // 24 decimals (for wstHYPE compatibility)
    uint256 private _totalShares; // 24 decimals
    uint256 public totalPooledHYPE; // 18 decimals - this grows with rewards
    
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 public constant balanceToShareDecimals = 10 ** 6; // Converts 18 decimals to 24 decimals
    
    address public overseer;
    address public wstHype;
    
    modifier onlyOverseer() {
        require(msg.sender == overseer, "Only overseer can call this function");
        _;
    }
    
    modifier onlyWstHype() {
        require(msg.sender == wstHype, "Only wstHype can call this function");
        _;
    }
    
    constructor() {
        // maybe couldve taken overseer and wstHype as constructor inputs, but we can leave that for now
        // just make sure to call `setOverseer` and `setWstHype` manually just after constructing it 
        overseer = address(0);
        totalPooledHYPE = 0;
        _totalShares = 0;
    }
    
    function setOverseer(address _overseer) external {
        overseer = _overseer;
    }

    function setWstHype(address _wstHype) external {
        wstHype = _wstHype;
    }
    
    function rebase(uint256 rewards) external {
        totalPooledHYPE += rewards;
        emit Rebase(totalPooledHYPE - rewards, totalPooledHYPE, rewards);
    }
    
    function totalSupply() external view override returns (uint256) {
        return totalPooledHYPE;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        if (_totalShares == 0) return 0;
        return (_shares[account] * totalPooledHYPE) / _totalShares;
    }
    
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _allowances[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _allowances[msg.sender][spender] = currentAllowance - subtractedValue;
        emit Approval(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }
    
    // ==================== MINTING AND BURNING ====================
    
    /**
     * @notice Mint stHYPE by adding shares and increasing totalPooledHYPE
     */
    function mint(address to, uint256 amount) external onlyOverseer {
        require(to != address(0), "ERC20: mint to the zero address");
        require(amount > 0, "Cannot mint 0 tokens");
        
        uint256 sharesToMint;
        if (_totalShares == 0) {
            // First mint: 1:1 ratio, convert to 24 decimals 
            sharesToMint = amount * balanceToShareDecimals;
        } else {
            // Calculate shares based on current ratio
            sharesToMint = (amount * _totalShares) / totalPooledHYPE;
        }
        
        _shares[to] += sharesToMint;
        _totalShares += sharesToMint;
        totalPooledHYPE += amount;
        
        emit Transfer(address(0), to, amount);
    }
    
    /**
     * @notice Burn stHYPE by removing shares and decreasing totalPooledHYPE
     */
    function burn(address from, uint256 amount) external onlyOverseer {
        require(from != address(0), "ERC20: burn from the zero address");
        require(amount > 0, "Cannot burn 0 tokens");
        
        uint256 currentBalance = this.balanceOf(from); // to access external functions inside the same contract, use the `this` keyword 
        require(currentBalance >= amount, "ERC20: burn amount exceeds balance"); 
        
        uint256 sharesToBurn = (_shares[from] * amount) / currentBalance;
        
        _shares[from] -= sharesToBurn;
        _totalShares -= sharesToBurn;
        totalPooledHYPE -= amount;
        
        emit Transfer(from, address(0), amount);
    }
    
    // ==================== SHARES INTERFACE (for wstHYPE) ====================
    
    /**
     * @notice Get shares balance (24 decimals)
     */
    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }
    
    /**
     * @notice Get total shares (24 decimals)
     */
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }
    
    /**
     * @notice Transfer shares directly (for wstHYPE)
     */ 
    function transferShares(address from, address to, uint256 sharesAmount) external onlyWstHype returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_shares[from] >= sharesAmount, "ERC20: transfer amount exceeds shares");
        
        _shares[from] -= sharesAmount;
        _shares[to] += sharesAmount;
        
        // Calculate balance amount for event 
        uint256 balanceAmount = 0;
        if (_totalShares > 0) {
            balanceAmount = (sharesAmount * totalPooledHYPE) / _totalShares;
        }
        
        emit Transfer(from, to, balanceAmount);
        return true;
    }
    
    // ==================== INTERNAL FUNCTIONS ====================
    
    // internally everything would be done with shares
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        
        uint256 fromBalance = this.balanceOf(from);
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        
        // Calculate shares to transfer
        uint256 sharesToTransfer = (_shares[from] * amount) / fromBalance;
        
        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        
        emit Transfer(from, to, amount);
    }
    
    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        if (spender == wstHype) {
            return; // wstHYPE has unlimited allowance
        }
        
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _allowances[owner][spender] = currentAllowance - amount;
        }
    }
    
    // ==================== COMPATIBILITY FUNCTIONS ====================
    
    /**
     * @notice Convert balance to shares
     */
    function balanceToShares(uint256 balance) external view returns (uint256) {
        if (_totalShares == 0 || totalPooledHYPE == 0) {
            return balance * balanceToShareDecimals;
        }
        return (balance * _totalShares) / totalPooledHYPE;
    }
    
    /**
     * @notice Convert shares to balance
     */
    function sharesToBalance(uint256 shares) external view returns (uint256) {
        if (_totalShares == 0) {
            return shares / balanceToShareDecimals;
        }
        return (shares * totalPooledHYPE) / _totalShares;
    }
    
    /**
     * @notice Get balance per share (for compatibility)
     */
    function balancePerShare() external view returns (uint256) {
        if (_totalShares == 0) return 1e18;
        return (totalPooledHYPE * shareDecimals) / _totalShares; // answer in 18 decimals 
    }
    
    /**
     * @notice Get exchange rate (HYPE per stHYPE, should always be 1e18 for rebasing)
     */
    function getExchangeRate() external pure returns (uint256) {
        return 1e18; 
    }
    
    // ==================== VIEW HELPERS ====================
    
    function getTotalShares() external view returns (uint256) {
        return _totalShares;
    }
    
    function getTotalBalance() external view returns (uint256) {
        return totalPooledHYPE;
    }
    
    uint256 public constant shareDecimals = 10 ** 24;
}
