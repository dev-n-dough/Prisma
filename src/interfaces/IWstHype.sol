// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStHYPE} from "../../src/interfaces/IStHYPE.sol";

interface IWstHype is IERC20 {
    function sthype() external view returns (IStHYPE);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner_, address spender) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool success);
    function transferFrom(address from, address to, uint256 value) external returns (bool success);
    function approve(address spender, uint256 value) external returns (bool success);
    function balanceToSharesDecimals() external view returns(uint256);
}