// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {BaseDecoderAndSanitizer, DecoderCustomTypes} from "@boring-vault/src/base/DecodersAndSanitizers/BaseDecoderAndSanitizer.sol";
import {IOverseer} from "../interfaces/IOverseer.sol";
import {IStHYPE} from "../interfaces/IStHYPE.sol";
import {IWHYPE} from "../interfaces/IWHYPE.sol";
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

// note : please dont be mislead by the name, this is the decoder for ALL operations, not just staking/unstaking
contract StHYPEDecoderAndSanitizer is BaseDecoderAndSanitizer{

    address public immutable boringVault;
    address public immutable overseer;
    address public immutable stHypeToken;
    address public immutable wHypeToken;
    
    constructor(
        address _boringVault,
        address _overseer,
        address _stHypeToken,
        address _wHypeToken
    ) {
        boringVault = _boringVault;
        overseer = _overseer;
        stHypeToken = _stHypeToken;
        wHypeToken = _wHypeToken;
    }

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    // staking in stHype is done through this fn : `mint(address to, uint256 communityCode)(uint256)`
    function mint(address to, string memory) external pure returns(bytes memory addressesFound){
        addressesFound = abi.encodePacked(to);
    }

    // unstaking : `burnAndRedeemIfPossible(address to, uint256 amount, string communityCode)`
    function burnAndRedeemIfPossible(address to, uint256, string memory) external pure returns(bytes memory addressesFound){
        addressesFound = abi.encodePacked(to);
    }

    // redeeming(what couldnt be redeemed in the unstake call instantly) : `redeem(uint256 burnID)`
    function redeem(uint256) external pure returns(bytes memory addressesFound){
        // no addresses to sanitize
        return addressesFound;
    }

    function assetsOf(address account) external pure returns (bytes memory addressesFound){
        addressesFound = abi.encodePacked(account);
    }

    /*//////////////////////////////////////////////////////////////
                                 ERC20
    //////////////////////////////////////////////////////////////*/

    // NOTE : `transfer` and `approve` are covered in base file!

    function transferFrom(address from, address to, uint256) 
        external 
        pure 
        returns (bytes memory addressesFound) 
    {
        // Return both sender and recipient addresses
        addressesFound = abi.encodePacked(from, to);
    }
    
    /*//////////////////////////////////////////////////////////////
                                 WHYPE
    //////////////////////////////////////////////////////////////*/

    function deposit() // sand native HYPE, and wHYPE will be sent to msg.sender
        external 
        pure 
        returns (bytes memory addressesFound) 
    {
        addressesFound = hex"";
    }

    function withdraw(uint256) 
        external 
        pure 
        returns (bytes memory addressesFound) 
    {
        addressesFound = hex"";
    }


    /*//////////////////////////////////////////////////////////////
                                 MORPHO
    //////////////////////////////////////////////////////////////*/

    function setAuthorization(address authorized, bool) external pure returns(bytes memory addressesFound){
        addressesFound = abi.encodePacked(authorized);
    }

    function supplyCollateral(
        MarketParams memory,
        uint256, 
        address onBehalf, 
        bytes calldata) 
        external 
        pure 
        returns(bytes memory addressesFound)
    {
        addressesFound = abi.encodePacked(onBehalf);
    }

    function borrow(
        MarketParams memory,
        uint256,
        uint256,
        address onBehalf,
        address receiver
    ) external pure returns (bytes memory addressesFound) {
        addressesFound = abi.encodePacked(onBehalf,receiver);
    }

    function repay(
        MarketParams memory,
        uint256,
        uint256,
        address onBehalf,
        bytes memory
    ) external pure returns (bytes memory addressesFound){
        addressesFound = abi.encodePacked(onBehalf);
    }

    function withdrawCollateral(
        MarketParams memory,
        uint256, 
        address onBehalf, 
        address receiver
    ) external pure returns(bytes memory addressesFound){
         addressesFound = abi.encodePacked(onBehalf, receiver); 
    }
    
    /*//////////////////////////////////////////////////////////////
                             THIS_CONTRACT
    //////////////////////////////////////////////////////////////*/

    function getConfiguration() external view returns (
        address _vault,
        address _overseer,
        address _stHype,
        address _whype
    ) {
        return (boringVault, overseer, stHypeToken, wHypeToken);
    }
}