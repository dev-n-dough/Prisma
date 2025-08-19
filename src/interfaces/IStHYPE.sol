// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStHYPE {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceToShares(uint256 balance) external view returns (uint256);
    function owner() external view returns(address);
    function balanceToShareDecimals() external view returns(uint256);
    function balancePerShare() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function sharesToBalance(uint256 shares) external view returns (uint256);
}