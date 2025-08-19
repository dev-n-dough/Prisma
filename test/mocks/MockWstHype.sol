// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

interface IStHype {
    function transferShares(address from, address to, uint256 sharesAmount) external returns (bool);
    function sharesOf(address account) external view returns (uint256);
    function totalShares() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/**
 * @title Simple MockWstHype
 * @notice Wrapped stHYPE that shows shares directly (yield-bearing)
 * @dev Balance stays constant, but exchange rate increases over time
 */
contract MockWstHype is IERC20 {
    string public name = "Wrapped Staked Hype";
    string public symbol = "wstHYPE";
    uint8 public decimals = 18;

    IStHype public sthype;
    uint256 public constant balanceToShareDecimals = 10 ** 6; // 6 extra decimals

    mapping(address => mapping(address => uint256)) private _allowances;

    event TransferWstHype(address indexed from, address indexed to, uint256 amount);
    event ApprovalWstHype(address indexed owner, address indexed spender, uint256 amount);

    constructor(address _sthype) {
        sthype = IStHype(_sthype);
    }

    // ==================== ERC20 INTERFACE (YIELD-BEARING) ====================

    /**
     * @notice Total supply shows total shares converted to 18 decimals
     */
    function totalSupply() external view override returns (uint256) {
        return sthype.totalShares() / balanceToShareDecimals;
    }

    /**
     * @notice Balance shows shares converted to 18 decimals - STAYS CONSTANT!
     */
    function balanceOf(address who) external view override returns (uint256) {
        return sthype.sharesOf(who) / balanceToShareDecimals;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _allowances[msg.sender][spender] = value;
        emit ApprovalWstHype(msg.sender, spender, value);
        return true;
    }

    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _allowances[msg.sender][spender] += addedValue;
        emit ApprovalWstHype(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _allowances[msg.sender][spender] = currentAllowance - subtractedValue;
        emit ApprovalWstHype(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    // ==================== INTERNAL FUNCTIONS ====================

    function _transfer(address from, address to, uint256 amount) internal {
        // Convert wstHYPE amount (18 decimals) to shares (24 decimals)
        uint256 shareAmount = amount * balanceToShareDecimals;
        sthype.transferShares(from, to, shareAmount);
        emit TransferWstHype(from, to, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            _allowances[owner][spender] = currentAllowance - amount;
        }
    }

    // ==================== CONVERSION/UTILITY FUNCTIONS ====================

    /**
     * @notice Convert wstHYPE balance to shares (24 decimals)
     */
    function balanceToShares(uint256 balance) external pure returns (uint256) {
        return balance * balanceToShareDecimals;
    }

    /**
     * @notice Convert shares (24 decimals) to wstHYPE balance
     */
    function sharesToBalance(uint256 shares) external pure returns (uint256) {
        return shares / balanceToShareDecimals;
    }

    /**
     * @notice Get shares balance directly (24 decimals)
     */
    function sharesOf(address who) external view returns (uint256) {
        return sthype.sharesOf(who);
    }

    /**
     * @notice Get total shares (24 decimals)
     */
    function totalShares() external view returns (uint256) {
        return sthype.totalShares();
    }

    /**
     * @notice Get how much stHYPE each wstHYPE token is worth (exchange rate)
     */
    function stHypePerToken() external view returns (uint256) {
        uint256 totalShares_ = sthype.totalShares();
        // console.log("From inside MockWstHype");
        // console.log("totalShares_ : ", totalShares_);
        // console.log("sthype.totalSupply() : ", sthype.totalSupply());
        if (totalShares_ == 0) return 1e18;
        // console.log("balanceToShareDecimals * sthype.totalSupply() : ", balanceToShareDecimals * sthype.totalSupply());
        
        // How much stHYPE is 1 wstHYPE worth?
        // 1 wstHYPE = balanceToShareDecimals shares
        // Those shares are worth (shares * totalStHypeSupply) / totalShares_ stHYPE 
        return (balanceToShareDecimals * sthype.totalSupply() * 1e18) / totalShares_; 
    }

    /**
     * @notice Get how much wstHYPE you get for 1 stHYPE (inverse exchange rate)
     */
    function tokensPerStHype() external view returns (uint256) {
        uint256 stHypePerWst = this.stHypePerToken();
        if (stHypePerWst == 0) return 1e18;
        return (1e18 * 1e18) / stHypePerWst;
    }

    /**
     * @notice Convert stHYPE amount to wstHYPE amount at current rate
     */
    function getWstHypeByStHype(uint256 stHypeAmount) external view returns (uint256) {
        return (stHypeAmount * this.tokensPerStHype()) / 1e18;
    }

    /**
     * @notice Convert wstHYPE amount to stHYPE amount at current rate
     */
    function getStHypeByWstHype(uint256 wstHypeAmount) external view returns (uint256) {
        return (wstHypeAmount * this.stHypePerToken()) / 1e18;
    }
}
