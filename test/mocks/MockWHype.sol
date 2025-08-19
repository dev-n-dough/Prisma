// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWHYPE} from "../../src/interfaces/IWHYPE.sol";
import {console} from "forge-std/console.sol";

contract MockWHype is IERC20 {
    string public name = "Wrapped HYPE";
    string public symbol = "wHYPE";
    uint8 public decimals = 18;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    uint256 private _totalSupply;
    
    event Deposit(address indexed account, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);
    
    /**
     * @dev Deposit native HYPE tokens and mint equivalent wHYPE
     */
    function deposit() external payable {
        require(msg.value > 0, "Cannot deposit 0 tokens");
        
        _balances[msg.sender] += msg.value;
        _totalSupply += msg.value;
        
        emit Deposit(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }
    
    /**
     * @dev Burn wHYPE tokens and withdraw equivalent native HYPE
     */
    function withdraw(uint256 amount) external {
        require(amount > 0, "Cannot withdraw 0 tokens");
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        require(address(this).balance >= amount, "Insufficient contract balance");
        
        // console.log("From MockWHype::withdraw");
        // console.log("_balances[msg.sender] : ", _balances[msg.sender]);
        _balances[msg.sender] -= amount;
        _totalSupply -= amount;
        
        payable(msg.sender).transfer(amount);
        
        emit Withdrawal(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
    }
    
    /**
     * @dev Returns the balance of wHYPE tokens for an account
     */
    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    /**
     * @dev Returns total supply of wHYPE tokens
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    /**
     * @dev Transfer wHYPE tokens to another address
     */
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    /**
     * @dev Transfer wHYPE tokens from one address to another (requires approval)
     */
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    /**
     * @dev Approve spender to transfer tokens on behalf of owner
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    /**
     * @dev Returns the allowance of spender for owner's tokens
     */
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    /**
     * @dev Increase allowance for spender
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }
    
    /**
     * @dev Decrease allowance for spender
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }
    
    /**
     * @dev Internal transfer function
     */
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        
        _balances[from] -= amount;
        _balances[to] += amount;
        
        emit Transfer(from, to, amount);
    }
    
    /**
     * @dev Internal approval function
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
        // console.log("approval updated to : ", _allowances[owner][spender]);
        emit Approval(owner, spender, amount);
    }
    
    /**
     * @dev Internal function to handle allowance spending
     */
    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        // if(owner == spem)
        uint256 currentAllowance = _allowances[owner][spender];
        // console.log("current allowance : ", currentAllowance);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }
    
    /**
     * @dev Receive function to allow direct ETH deposits
     */
    receive() external payable {
        if (msg.value > 0) {
            _balances[msg.sender] += msg.value;
            _totalSupply += msg.value;
            emit Deposit(msg.sender, msg.value);
            emit Transfer(address(0), msg.sender, msg.value);
        }
    }
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {
        if (msg.value > 0) {
            _balances[msg.sender] += msg.value;
            _totalSupply += msg.value;
            emit Deposit(msg.sender, msg.value);
            emit Transfer(address(0), msg.sender, msg.value);
        }
    }
}