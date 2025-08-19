// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOverseer{
    function mint(address to, string memory communityCode) external payable returns (uint256);
    function burnAndRedeemIfPossible(address to, uint256 amount, string memory communityCode) external returns (bool);
    function redeem(uint256 burnId) external;
    function redeemable(uint256 burnId) external view returns (bool);
    function getBurns(address account) external view returns (
        Burn[] memory burns,
        uint256[] memory burnIds, 
        bool[] memory redeemables
    );
    function maxRedeemable() external view returns (uint256);
}

struct Burn {
    uint88 amount;
    address user;
    bool completed;
    uint256 sum;
}