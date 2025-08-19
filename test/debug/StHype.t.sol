// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IStHYPE} from "../../src/interfaces/IStHYPE.sol";
import {Test, console} from "forge-std/Test.sol";

contract StHypeTest is Test{
    IStHYPE stHype;

    function setUp() external{
        console.log("chain id : ", block.chainid);
        // stHype = IStHYPE(0xe2FbC9cB335A65201FcDE55323aE0F4E8A96A616);
        if(block.chainid == 998){
            stHype = IStHYPE(0xe2FbC9cB335A65201FcDE55323aE0F4E8A96A616);
        } else if(block.chainid == 999){
            stHype = IStHYPE(0xfFaa4a3D97fE9107Cef8a3F48c069F577Ff76cC1);
        }
    }

    function test_stHypeWorksOrNot() view public{
        // i think that the rpc was the problem,following all are working on testnet and mainnet
        console.log(stHype.owner());
        console.log(stHype.balanceToShareDecimals());
        console.log(stHype.totalSupply());
        // console.log(stHype.)
    }
}