// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {IOverseer} from "../interfaces/IOverseer.sol";
import {IStHYPE} from "../interfaces/IStHYPE.sol";
import {IWHYPE} from "../interfaces/IWHYPE.sol";
import {IWstHype} from "../interfaces/IWstHype.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "@boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {TellerWithMultiAssetSupport} from "@boring-vault/src/base/Roles/TellerWithMultiAssetSupport.sol";
import {AccountantWithRateProviders} from "@boring-vault/src/base/Roles/AccountantWithRateProviders.sol";
import {StHYPEDecoderAndSanitizer} from "../decoders/StHYPEDecoderAndSanitizer.sol";
// import {MerkleGenerator} from "../merkle/MerkleGenerator.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";
import {MerkleTreeHelper, ChainValues} from "@boring-vault/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";
import {console} from "forge-std/console.sol";
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

import {
    IMorphoLiquidateCallback,
    IMorphoRepayCallback,
    IMorphoSupplyCallback,
    IMorphoSupplyCollateralCallback,
    IMorphoFlashLoanCallback
} from "../interfaces/IMorphoCallbacks.sol";

// with morpho, i must do 3 actions : 
// 1. supply wstHype as collat 
// 2. borrow hype 
// 3. repay hype 

contract Strategy is Auth, MerkleTreeHelper, IMorphoSupplyCollateralCallback /*,IMorphoRepayCallback*/ {

    error Strategy__NotRedeemable();

    ManagerWithMerkleVerification public immutable manager;
    BoringVault public immutable vault;
    address public immutable wHype;
    address public immutable stHype;
    address public immutable overseer;
    address public immutable decoderAndSanitizer;
    address public wstHype;
    bytes32[][] public manageTree;
    bytes32[][] public proofs;
    Id public MARKET_ID_MAINNET = Id.wrap(0xe9a9bb9ed3cc53f4ee9da4eea0370c2c566873d5de807e16559a99907c9ae227); // wstHype/Hype market on mainnet for felix
    address public immutable morpho;

    constructor(
        address _manager,
        address _vault,
        address _wHype,
        address _stHype,
        address _overseer,
        address _decoderAndSanitizer,
        address _owner,
        address _wstHype,
        address _morpho
    ) Auth(_owner, Authority(address(0))) {
        manager = ManagerWithMerkleVerification(_manager);
        vault = BoringVault(payable(_vault));
        wHype = _wHype;
        stHype = _stHype;
        overseer = _overseer;
        decoderAndSanitizer = _decoderAndSanitizer;
        wstHype = _wstHype;
        morpho = _morpho;
        createMerkleTree();
        // treeGeneration_dummy();
    }

    function createMerkleTree() public {

        ManageLeaf[] memory leaves = new ManageLeaf[](16);
        leaves[0] = ManageLeaf(
            wHype,
            true,
            "deposit()",
            new address[](0),
            "",
            decoderAndSanitizer
        );
        // console.log("Leaf no. 0 created");
        leaves[1] = ManageLeaf(
            wHype,
            false,
            "withdraw(uint256)",
            new address[](0),
            "",
            decoderAndSanitizer
        );
        // console.log("Leaf no. 1 created");
        address[] memory mintAddresses = new address[](1);
        mintAddresses[0] = address(vault);
        leaves[2] = ManageLeaf(
            overseer,
            true,
            "mint(address,string)",
            mintAddresses, // this is the whitelist for argument addresses
            "",
            decoderAndSanitizer
        );
        // console.log("Leaf no. 2 created");
        // leaves[2].argumentAddresses[0] = address(vault);
        address[] memory burnAddresses = new address[](1);
        burnAddresses[0] = address(vault);
        leaves[3] = ManageLeaf(
            overseer,
            false,
            "burnAndRedeemIfPossible(address,uint256,string)",
            burnAddresses,
            "",
            decoderAndSanitizer
        );
        // console.log("Leaf no. 3 created");
        leaves[3].argumentAddresses[0] = address(vault);
        leaves[4] = ManageLeaf(
            overseer,
            false,
            "redeem(uint256)",
            new address[](0),
            "",
            decoderAndSanitizer
        );
        // console.log("Leaf no. 4 created");
        address[] memory approveAddresses = new address[](1);
        approveAddresses[0] = address(overseer);
        leaves[5] = ManageLeaf(
            stHype,
            false,
            "approve(address,uint256)",
            approveAddresses,
            "",
            decoderAndSanitizer
        );

        address[] memory authAddresses = new address[](1);
        authAddresses[0] = address(this);
        // console.log("\n\n\nTarget(should be morpho address) : ", morpho, "\n\n\n");
        leaves[6] = ManageLeaf(
            morpho,
            false,
            "setAuthorization(address,bool)", 
            authAddresses,
            "",
            decoderAndSanitizer
        );

        address[] memory supplyCollatAddresses = new address[](1);
        supplyCollatAddresses[0] = address(vault);
        leaves[7] = ManageLeaf(
            morpho,
            false,
            // "supplyCollateral(MarketParams,uint256,address,bytes)",// write struct name directly
            "supplyCollateral((address,address,address,address,uint256),uint256,address,bytes)",
            supplyCollatAddresses,
            "",
            decoderAndSanitizer
        );

        address[] memory borrowAddresses = new address[](2);
        borrowAddresses[0] = address(vault); // onBehalf
        borrowAddresses[1] = address(vault); // receiver
        leaves[8] = ManageLeaf(
            morpho,
            false,
            "borrow((address,address,address,address,uint256),uint256,uint256,address,address)",
            borrowAddresses,
            "",
            decoderAndSanitizer
        );

        address[] memory newApproveAddresses = new address[](1);
        newApproveAddresses[0] = morpho;
        leaves[9] = ManageLeaf(
            wstHype,
            false,
            "approve(address,uint256)",
            newApproveAddresses,
            "",
            decoderAndSanitizer
        );

        address[] memory repayAddresses = new address[](1);
        repayAddresses[0] = address(vault);
        leaves[10] = ManageLeaf(
            morpho,
            false,
            "repay((address,address,address,address,uint256),uint256,uint256,address,bytes)",
            repayAddresses,
            "",
            decoderAndSanitizer
        );

        address[] memory withdrawCollatAddresses = new address[](2);
        withdrawCollatAddresses[0] = address(vault);
        withdrawCollatAddresses[1] = address(vault);
        
        leaves[11] = ManageLeaf(
            morpho,
            false,
            "withdrawCollateral((address,address,address,address,uint256),uint256,address,address)",
            withdrawCollatAddresses,
            "",
            decoderAndSanitizer
        );

        address[] memory wHypeApproveAddresses = new address[](1);
        wHypeApproveAddresses[0] = morpho;

        leaves[12] = ManageLeaf(
            wHype,
            false,
            "approve(address,uint256)",
            wHypeApproveAddresses,
            "",
            decoderAndSanitizer
        );
        
        leaves[13] = ManageLeaf(
            address(0),
            false,
            "",
            new address[](0),
            "",
            decoderAndSanitizer
        );
        leaves[14] = ManageLeaf(
            address(0),
            false,
            "",
            new address[](0),
            "",
            decoderAndSanitizer
        );
        leaves[15] = ManageLeaf(
            address(0),
            false,
            "",
            new address[](0),
            "",
            decoderAndSanitizer
        );

        // IMP NOTE : in filler leaves, you have to mention decoder addresses. you cant give it as address(0). this is because while generating proof, leaf is constructed from scratch, and there all other arguments are same as the leaves given in input, there is one parameter that they OVERRIDE,and that is the decoder addresses, they fill it as the address of decoder of the chain. SO if in any leaf I mess up the decoder address, the leaf generated while proof generation will not match, and i will get following error :
        // "Leaf not found in tree"

        manageTree = _generateMerkleTree(leaves);

        configureChainValues();
        proofs = _getProofsUsingTree(leaves, manageTree);
    }

    // we need to do this because of the way `_getProofsUsingTree` is written 
    function configureChainValues() public {
        setSourceChainName("hyper_mainnet");
        setAddress(
            true,
            "hyper_mainnet",
            "rawDataDecoderAndSanitizer",
            address(decoderAndSanitizer)
        );
    }

    function visualiseTree() public view {
        console.log("=== MERKLE TREE STRUCTURE ===");
        console.log("(Leaves at top, Root at bottom)");
        console.log("");

        // Print from leaves (top) to root (bottom)
        for (uint256 level = 0; level < manageTree.length; level++) {
            // Create indentation based on level
            string memory indent = "";
            for (uint256 space = 0; space < level * 4; space++) {
                indent = string.concat(indent, " ");
            }

            console.log(string.concat("Level ", vm.toString(level), ":"));

            for (uint256 i = 0; i < manageTree[level].length; i++) {
                // Print with indentation
                string memory nodeInfo = string.concat(
                    indent,
                    "Node",
                    vm.toString(i),
                    ":"
                );
                console.log(nodeInfo);

                string memory hashStr = string.concat(
                    indent,
                    "  0x",
                    vm.toString(manageTree[level][i])
                );
                console.log(hashStr);
            }
            console.log("");
        }

        console.log("=== ROOT (Bottom) ===");
        console.log("ROOT:");
        console.logBytes32(manageTree[manageTree.length - 1][0]);
    }

    function visualiseProof(uint256 j) public view {
        console.log("=== PROOF FOR LEAF ", j, "  ===");
        console.log("Proof length:");
        console.log(proofs[j].length);

        for (uint256 i = 0; i < proofs[j].length; i++) {
            console.log("Proof step:");
            console.log(i);
            console.log("Hash:");
            console.logBytes32(proofs[j][i]);
        }
        console.log("=== END PROOF ===");
    }

    function getManageTreeRoot() public view returns (bytes32) {
        return manageTree[manageTree.length - 1][0];
    }

    function executeStaking(
        uint256 amount,
        string memory communityCode
    ) public {
        // the vault must do 2 things
        // 1. unwrap `amount` amount of wHYPE
        // 2. call mint

        address[] memory targets = new address[](2);
        targets[0] = wHype;
        targets[1] = overseer;

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(
            IWHYPE.withdraw.selector,
            amount
        );
        targetData[1] = abi.encodeWithSelector(
            IOverseer.mint.selector,
            address(vault),
            communityCode
        );

        bytes32[][] memory stakingProofs = new bytes32[][](2);
        stakingProofs[0] = proofs[1];
        stakingProofs[1] = proofs[2];

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = amount;

        address[] memory decoders = new address[](2);
        decoders[0] = decoderAndSanitizer;
        decoders[1] = decoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(
            stakingProofs,
            decoders,
            targets,
            targetData,
            values
        );
    }

    function executeUnstaking(
        uint256 amount,
        string memory communityCode
    ) public returns (uint256 latestBurnId) {
        address[] memory targets = new address[](2);
        targets[0] = stHype;
        targets[1] = overseer;

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(
            IStHYPE.approve.selector,
            overseer,
            amount
        );
        targetData[1] = abi.encodeWithSelector(
            IOverseer.burnAndRedeemIfPossible.selector,
            address(vault),
            amount,
            communityCode
        );

        bytes32[][] memory unstakingProofs = new bytes32[][](2);
        unstakingProofs[0] = proofs[5];
        unstakingProofs[1] = proofs[3];

        uint256[] memory values = new uint256[](2);

        address[] memory decoders = new address[](2);
        decoders[0] = decoderAndSanitizer;
        decoders[1] = decoderAndSanitizer;

        uint256 startingBalance = address(vault).balance;

        manager.manageVaultWithMerkleVerification(
            unstakingProofs,
            decoders,
            targets,
            targetData,
            values
        );

        uint256 hypeReceived = address(vault).balance - startingBalance;

        if (hypeReceived > 0) {
            // convert HYPE -> wHYPE
            address[] memory newTargets = new address[](1);
            newTargets[0] = wHype;

            bytes[] memory newTargetData = new bytes[](1);
            newTargetData[0] = abi.encodeWithSelector(IWHYPE.deposit.selector);

            bytes32[][] memory wrapProofs = new bytes32[][](1);
            wrapProofs[0] = proofs[0];

            uint256[] memory newValues = new uint256[](1);
            newValues[0] = hypeReceived;

            address[] memory newDecoders = new address[](1);
            newDecoders[0] = decoderAndSanitizer;

            manager.manageVaultWithMerkleVerification(
                wrapProofs,
                newDecoders,
                newTargets,
                newTargetData,
                newValues
            );
        }

        uint256 max_redeem_amount = IOverseer(overseer).maxRedeemable();
        if (amount > max_redeem_amount) {
            // fetch burn Id, use it to call `redeem`
            (, uint256[] memory burnIds, ) = IOverseer(overseer).getBurns(
                address(vault)
            );
            latestBurnId = burnIds[burnIds.length - 1];
        } // else, full amount requested would have been instantly redeemed, no need to call `redeem` explicitly. even if you do, it would revert since `redeemable` will be false

        // this function will return 0 if `amount < max_redeem_amount`. and `redeemable(0)` always returns false. Preferabbly add sanity checks on return value agains this case.
    }

    // wont be used
    function executeWrap(uint256 amount) public{
        address[] memory newTargets = new address[](1);
        newTargets[0] = wHype;

        bytes[] memory newTargetData = new bytes[](1);
        newTargetData[0] = abi.encodeWithSelector(IWHYPE.deposit.selector);

        bytes32[][] memory wrapProofs = new bytes32[][](1);
        wrapProofs[0] = proofs[0];

        uint256[] memory newValues = new uint256[](1);
        newValues[0] = amount;

        address[] memory newDecoders = new address[](1);
        newDecoders[0] = decoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(
            wrapProofs,
            newDecoders,
            newTargets,
            newTargetData,
            newValues
        );
    }

    function executeRedeem(uint256 burnId) public {
        bool allowed = IOverseer(overseer).redeemable(burnId);
        if (!allowed) {
            revert Strategy__NotRedeemable();
        }
        // ask manager to call `redeem`

        address[] memory targets = new address[](1);
        targets[0] = overseer;

        bytes[] memory targetData = new bytes[](1);
        targetData[0] = abi.encodeWithSelector(
            IOverseer.redeem.selector,
            burnId
        );

        bytes32[][] memory redeemProofs = new bytes32[][](1);
        redeemProofs[0] = proofs[4];

        uint256[] memory values = new uint256[](1);

        address[] memory decoders = new address[](1);
        decoders[0] = decoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(
            redeemProofs,
            decoders,
            targets,
            targetData,
            values
        );
    }

    function executeSupplyCollateral(uint256 amount) public{
        // 1. create leaf for vault to allow this strategy contract as an authorised address
        // 2. fetch `MarketParams` via id, get id from docs
        // 3. create leaf for supply
        // 4. call `supply`, on behalf of vault


        // No need to call `setAuthorization` since vault will call all the functions itself 

        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) = IMorphoStaticTyping(morpho).idToMarketParams(MARKET_ID_MAINNET);
        MarketParams memory marketParams = MarketParams(loanToken,collateralToken,oracle,irm,lltv);

        address[] memory targets = new address[](2);
        targets[0] = wstHype;
        targets[1] = morpho;

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(
            IWstHype.approve.selector,
            morpho,
            amount
        );
        targetData[1] = abi.encodeWithSelector(
            IMorphoBase.supplyCollateral.selector,
            marketParams,
            amount, // input amount should be scaled by 10^18 beforehand.(stHype or wstHype has 18 decimals)
            address(vault),
            ""
        );

        bytes32[][] memory supplyingCollateralProofs = new bytes32[][](2);
        supplyingCollateralProofs[0] = proofs[9];
        supplyingCollateralProofs[1] = proofs[7];

        uint256[] memory values = new uint256[](2);

        address[] memory decoders = new address[](2);
        decoders[0] = decoderAndSanitizer;
        decoders[1] = decoderAndSanitizer;


        // LOGS TO DEBUG THE FIRST CALL FLOW
        // console.log("Target : ", targets[0]);
        // console.log("decoder : ", decoders[0]);
        // console.log("Value : ", values[0]);
        // console.log("Packed arg addresses : ");
        // console.logBytes(abi.encodePacked(address(this)));

        manager.manageVaultWithMerkleVerification(
            supplyingCollateralProofs,
            decoders,
            targets,
            targetData,
            values
        );
    }

    function onMorphoSupplyCollateral(uint256, bytes calldata) external pure{
        console.log("Supply collateral callback called!");
        // wont be called
    }

    function executeBorrow(uint256 amount) public{
        // auth is alr set if I am calling this after `executeStaking` => again, no need for auth
        // just make the call to withdraw some wHype
        // what is max amount I can borrow? == current collat balance of vault * lltv for this market 

        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) = IMorphoStaticTyping(morpho).idToMarketParams(MARKET_ID_MAINNET);
        MarketParams memory marketParams = MarketParams(loanToken,collateralToken,oracle,irm,lltv);

        address[] memory targets = new address[](1);
        targets[0] = morpho;

        bytes[] memory targetData = new bytes[](1);
        targetData[0] = abi.encodeWithSelector(
            IMorphoBase.borrow.selector,
            marketParams,
            amount,
            0,
            address(vault),
            address(vault)
        );
        bytes32[][] memory borrowProofs = new bytes32[][](1);
        borrowProofs[0] = proofs[8];

        uint256[] memory values = new uint256[](1);

        address[] memory decoders = new address[](1);
        decoders[0] = decoderAndSanitizer;


        // LOGS TO DEBUG THE FIRST CALL FLOW
        // console.log("Target : ", targets[0]);
        // console.log("decoder : ", decoders[0]);
        // console.log("Value : ", values[0]);
        // console.log("Packed arg addresses : ");
        // console.logBytes(abi.encodePacked(address(this)));

        manager.manageVaultWithMerkleVerification(
            borrowProofs,
            decoders,
            targets,
            targetData,
            values
        );

    }

    function executeRepayUsingAssets(uint256 amount) public{
        // 1. wHype.approve(morpho, amount)
        // 2. morpho.repay

        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) = IMorphoStaticTyping(morpho).idToMarketParams(MARKET_ID_MAINNET);
        MarketParams memory marketParams = MarketParams(loanToken,collateralToken,oracle,irm,lltv);

        address[] memory targets = new address[](2);
        targets[0] = wHype;
        targets[1] = morpho;

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(
            IWHYPE.approve.selector,
            morpho,
            amount
        );
        targetData[1] = abi.encodeWithSelector(
            IMorphoBase.repay.selector,
            marketParams,
            amount,
            0,
            address(vault),
            ""
        );
        bytes32[][] memory repayProofs = new bytes32[][](2);
        repayProofs[0] = proofs[12];
        repayProofs[1] = proofs[10];

        uint256[] memory values = new uint256[](2);

        address[] memory decoders = new address[](2);
        decoders[0] = decoderAndSanitizer;
        decoders[1] = decoderAndSanitizer;

        // LOGS TO DEBUG THE FIRST CALL FLOW
        // console.log("Target : ", targets[0]);
        // console.log("decoder : ", decoders[0]);
        // console.log("Value : ", values[0]);
        // console.log("Packed arg addresses : ");
        // console.logBytes(abi.encodePacked(address(this)));

        manager.manageVaultWithMerkleVerification(
            repayProofs,
            decoders,
            targets,
            targetData,
            values
        );
    }

    function executeRepayUsingShares(uint256 shares) public{
        // 1. wHype.approve(morpho, amount)
        // 2. morpho.repay

        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) = IMorphoStaticTyping(morpho).idToMarketParams(MARKET_ID_MAINNET);
        MarketParams memory marketParams = MarketParams(loanToken,collateralToken,oracle,irm,lltv);

        address[] memory targets = new address[](2);
        targets[0] = wHype;
        targets[1] = morpho;

        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(
            IWHYPE.approve.selector,
            morpho,
            /*assets*/ type(uint256).max
        );
        targetData[1] = abi.encodeWithSelector(
            IMorphoBase.repay.selector,
            marketParams,
            0,
            shares,
            address(vault),
            ""
        );
        bytes32[][] memory repayProofs = new bytes32[][](2);
        repayProofs[0] = proofs[12];
        repayProofs[1] = proofs[10];

        uint256[] memory values = new uint256[](2);

        address[] memory decoders = new address[](2);
        decoders[0] = decoderAndSanitizer;
        decoders[1] = decoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(
            repayProofs,
            decoders,
            targets,
            targetData,
            values
        );
    } 

    function executeWithdrawCollateral(uint256 amount) public{
        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) = IMorphoStaticTyping(morpho).idToMarketParams(MARKET_ID_MAINNET);
        MarketParams memory marketParams = MarketParams(loanToken,collateralToken,oracle,irm,lltv);

        address[] memory targets = new address[](1);
        targets[0] = morpho;

        bytes[] memory targetData = new bytes[](1);
        targetData[0] = abi.encodeWithSelector(
            IMorphoBase.withdrawCollateral.selector,
            marketParams,
            amount, // input amount should be scaled by 10^18 beforehand.(stHype or wstHype has 18 decimals)
            address(vault),
            address(vault)
        );

        bytes32[][] memory withdrawCollatProofs = new bytes32[][](1);
        withdrawCollatProofs[0] = proofs[11];

        uint256[] memory values = new uint256[](1);

        address[] memory decoders = new address[](1);
        decoders[0] = decoderAndSanitizer;

        manager.manageVaultWithMerkleVerification(
            withdrawCollatProofs,
            decoders,
            targets,
            targetData,
            values
        );
    }


    /*//////////////////////////////////////////////////////////////
                        HELPER MERKLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    function getManageTreeDepth() public view returns (uint256) {
        return manageTree.length;
    }

    function getManageTreeLevel(uint256 level) public view returns (bytes32[] memory) {
        require(level < manageTree.length, "Level out of bounds");
        return manageTree[level];
    }

    function getProof(uint256 leafIndex) public view returns (bytes32[] memory) {
        require(leafIndex < proofs.length, "Leaf index out of bounds");
        return proofs[leafIndex];
    }

    function getProofLength(uint256 leafIndex) public view returns (uint256) {
        require(leafIndex < proofs.length, "Leaf index out of bounds");
        return proofs[leafIndex].length;
    }

    function getProofsLength() public view returns (uint256) {
        return proofs.length;
    }

}
