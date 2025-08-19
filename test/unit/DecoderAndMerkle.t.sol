// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test, stdStorage, StdStorage, stdError, console} from "@forge-std/Test.sol";
import {StHYPEDecoderAndSanitizer} from "../../src/decoders/StHYPEDecoderAndSanitizer.sol";
import {Strategy} from "../../src/strategy/Strategy.sol";
import {BoringVault} from "@boring-vault/src/base/BoringVault.sol";
import {ManagerWithMerkleVerification} from "@boring-vault/src/base/Roles/ManagerWithMerkleVerification.sol";
import {RolesAuthority, Authority} from "@solmate/auth/authorities/RolesAuthority.sol";
import {MerkleTreeHelper} from "@boring-vault/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol";

import {IOverseer} from "../../src/interfaces/IOverseer.sol";
import {IStHYPE} from "../../src/interfaces/IStHYPE.sol";
import {IWHYPE} from "../../src/interfaces/IWHYPE.sol";
import {
    Id,
    IMorphoStaticTyping,
    IMorphoBase,
    MarketParams,
    Position,
    Market,
    Authorization,
    Signature
} from "../../src/interfaces/IMorpho.sol";

// Import Mocks
import {MockWHype} from "../mocks/MockWHype.sol";
import {MockOverseer} from "../mocks/MockOverseer.sol";
import {MockStHype} from "../mocks/MockStHype.sol";
import {MockWstHype} from "../mocks/MockWstHype.sol";
import {MockMorpho} from "../mocks/MockMorpho.sol";

contract DecoderAndMerkleTests is Test, MerkleTreeHelper {

    // Core contracts
    BoringVault public vault;
    ManagerWithMerkleVerification public manager;
    StHYPEDecoderAndSanitizer public decoder;
    Strategy public strategy;
    RolesAuthority public rolesAuthority;

    // Mock contracts
    MockWHype public mockWHype;
    MockStHype public mockStHype;
    MockOverseer public mockOverseer;
    MockWstHype public mockWstHype;
    MockMorpho public mockMorpho;

    // Test addresses
    address public constant VALID_RECIPIENT = address(0x123);
    address public constant INVALID_RECIPIENT = address(0x456);
    
    // Role constants
    uint8 public constant MANAGER_ROLE = 1;
    uint8 public constant STRATEGIST_ROLE = 2;
    uint8 public constant ADMIN_ROLE = 4;

    // Network config
    struct NetworkConfig {
        address wHype;
        address stHype;
        address overseer;
        address wstHype;
        address morpho;
    }

    NetworkConfig config;

    function setUp() external {
        // Deploy mock contracts
        mockWHype = new MockWHype();
        mockStHype = new MockStHype();
        mockOverseer = new MockOverseer(address(mockStHype));
        mockWstHype = new MockWstHype(address(mockStHype));
        mockMorpho = new MockMorpho(address(mockWHype), address(mockWstHype));

        deal(address(mockOverseer), 10000 ether);
        mockStHype.setOverseer(address(mockOverseer));
        mockStHype.setWstHype(address(mockWstHype));
        uint256 fundAmount = 1000 ether;
        deal(address(mockWHype), address(this), fundAmount);
        mockWHype.approve(address(mockMorpho), fundAmount);
        mockWHype.transfer(address(mockMorpho), fundAmount);

        // Setup config
        config = NetworkConfig({
            wHype: address(mockWHype),
            stHype: address(mockStHype),
            overseer: address(mockOverseer),
            wstHype: address(mockWstHype),
            morpho: address(mockMorpho)
        });

        // Deploy core contracts
        vault = new BoringVault(address(this), "Test Vault", "TV", 18);
        manager = new ManagerWithMerkleVerification(
            address(this),
            address(vault),
            address(vault)
        );
        
        decoder = new StHYPEDecoderAndSanitizer(
            address(vault),
            config.overseer,
            config.stHype,
            config.wHype 
        );

        strategy = new Strategy(
            address(manager),
            address(vault),
            config.wHype,
            config.stHype,
            config.overseer,
            address(decoder),
            address(this),
            config.wstHype,
            config.morpho
        );

        // Setup roles 
        rolesAuthority = new RolesAuthority(address(this), Authority(address(0)));
        vault.setAuthority(rolesAuthority);
        manager.setAuthority(rolesAuthority);

        // Configure roles
        rolesAuthority.setRoleCapability(
            MANAGER_ROLE,
            address(vault),
            bytes4(keccak256(abi.encodePacked("manage(address,bytes,uint256)"))),
            true
        );
        rolesAuthority.setRoleCapability(
            STRATEGIST_ROLE,
            address(manager),
            ManagerWithMerkleVerification.manageVaultWithMerkleVerification.selector,
            true
        );
        rolesAuthority.setRoleCapability(
            ADMIN_ROLE,
            address(manager),
            ManagerWithMerkleVerification.setManageRoot.selector,
            true
        );

        rolesAuthority.setUserRole(address(strategy), STRATEGIST_ROLE, true);
        rolesAuthority.setUserRole(address(this), ADMIN_ROLE, true);
        rolesAuthority.setUserRole(address(manager), MANAGER_ROLE, true);

        rolesAuthority.setPublicCapability(address(vault), bytes4(0), true);

        // Setup merkle root
        bytes32 manageRoot = strategy.getManageTreeRoot();
        manager.setManageRoot(address(strategy), manageRoot);
    }

    /*//////////////////////////////////////////////////////////////
                        DECODER TESTS - STAKING
    //////////////////////////////////////////////////////////////*/

    function test_decoder_mint_validRecipient() public {
        bytes memory addressesFound = decoder.mint(address(vault), "test");
        bytes memory expected = abi.encodePacked(address(vault));
        assertEq(addressesFound, expected);
    }

    function test_decoder_burnAndRedeemIfPossible() public {
        address recipient = address(0x789);
        bytes memory addressesFound = decoder.burnAndRedeemIfPossible(recipient, 100e18, "test");
        bytes memory expected = abi.encodePacked(recipient);
        assertEq(addressesFound, expected);
    }

    function test_decoder_redeem() public {
        bytes memory addressesFound = decoder.redeem(1);
        assertEq(addressesFound.length, 0);
    }

    function test_decoder_assetsOf() public {
        address account = address(0xabc);
        bytes memory addressesFound = decoder.assetsOf(account);
        bytes memory expected = abi.encodePacked(account);
        assertEq(addressesFound, expected);
    }

    /*//////////////////////////////////////////////////////////////
                        DECODER TESTS - ERC20
    //////////////////////////////////////////////////////////////*/

    function test_decoder_transferFrom() public {
        address from = address(0x111);
        address to = address(0x222);
        uint256 amount = 100e18;
        
        bytes memory addressesFound = decoder.transferFrom(from, to, amount);
        bytes memory expected = abi.encodePacked(from, to);
        assertEq(addressesFound, expected);
    }

    /*//////////////////////////////////////////////////////////////
                        DECODER TESTS - WHYPE
    //////////////////////////////////////////////////////////////*/

    function test_decoder_deposit() public {
        bytes memory addressesFound = decoder.deposit();
        assertEq(addressesFound, hex"");
    }

    function test_decoder_withdraw() public {
        bytes memory addressesFound = decoder.withdraw(100e18);
        assertEq(addressesFound, hex"");
    }

    /*//////////////////////////////////////////////////////////////
                        DECODER TESTS - MORPHO
    //////////////////////////////////////////////////////////////*/

    function test_decoder_setAuthorization() public {
        address authorized = address(0x333);
        bytes memory addressesFound = decoder.setAuthorization(authorized, true);
        bytes memory expected = abi.encodePacked(authorized);
        assertEq(addressesFound, expected);
    }

    function test_decoder_supplyCollateral() public {
        MarketParams memory marketParams = MarketParams({
            loanToken: address(0x1),
            collateralToken: address(0x2),
            oracle: address(0x3),
            irm: address(0x4),
            lltv: 800000000000000000
        });
        
        address onBehalf = address(0x444);
        bytes memory addressesFound = decoder.supplyCollateral(marketParams, 100e18, onBehalf, "");
        bytes memory expected = abi.encodePacked(onBehalf);
        assertEq(addressesFound, expected);
    }

    function test_decoder_borrow() public {
        MarketParams memory marketParams = MarketParams({
            loanToken: address(0x1),
            collateralToken: address(0x2),
            oracle: address(0x3),
            irm: address(0x4),
            lltv: 800000000000000000
        });
        
        address onBehalf = address(0x555);
        address receiver = address(0x666);
        
        bytes memory addressesFound = decoder.borrow(marketParams, 100e18, 0, onBehalf, receiver);
        bytes memory expected = abi.encodePacked(onBehalf, receiver);
        assertEq(addressesFound, expected);
    }

    function test_decoder_repay() public {
        MarketParams memory marketParams = MarketParams({
            loanToken: address(0x1),
            collateralToken: address(0x2),
            oracle: address(0x3),
            irm: address(0x4),
            lltv: 800000000000000000
        });
        
        address onBehalf = address(0x777);
        bytes memory addressesFound = decoder.repay(marketParams, 100e18, 0, onBehalf, "");
        bytes memory expected = abi.encodePacked(onBehalf);
        assertEq(addressesFound, expected);
    }

    function test_decoder_withdrawCollateral() public {
        MarketParams memory marketParams = MarketParams({
            loanToken: address(0x1),
            collateralToken: address(0x2),
            oracle: address(0x3),
            irm: address(0x4),
            lltv: 800000000000000000
        });
        
        address onBehalf = address(0x888);
        address receiver = address(0x999);
        
        bytes memory addressesFound = decoder.withdrawCollateral(marketParams, 100e18, onBehalf, receiver);
        bytes memory expected = abi.encodePacked(onBehalf, receiver);
        assertEq(addressesFound, expected);
    }

    /*//////////////////////////////////////////////////////////////
                        DECODER TESTS - CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    function test_decoder_getConfiguration() public {
        (
            address _vault,
            address _overseer,
            address _stHype,
            address _whype
        ) = decoder.getConfiguration();
        
        assertEq(_vault, address(vault));
        assertEq(_overseer, config.overseer);
        assertEq(_stHype, config.stHype);
        assertEq(_whype, config.wHype);
    }

    function test_decoder_immutableVariables() public {
        assertEq(decoder.boringVault(), address(vault));
        assertEq(decoder.overseer(), config.overseer);
        assertEq(decoder.stHypeToken(), config.stHype);
        assertEq(decoder.wHypeToken(), config.wHype);
    }

    /*//////////////////////////////////////////////////////////////
                        MERKLE TREE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_merkleTree_rootGeneration() public {
        bytes32 root = strategy.getManageTreeRoot();
        assertTrue(root != bytes32(0), "Root should not be empty");
    }

    function test_merkleTree_merkleDepth() public view {
        assert(strategy.getManageTreeDepth() == 5);
    }

    function test_merkleTree_proofsLength() public view{
        assert(strategy.getProofsLength() == 16);
    }

    function test_merkleTree_lengthOfEachLevel() public view{
        assert(strategy.getManageTreeLevel(0).length == 16);
        assert(strategy.getManageTreeLevel(1).length == 8);
        assert(strategy.getManageTreeLevel(2).length == 4);
        assert(strategy.getManageTreeLevel(3).length == 2);
        assert(strategy.getManageTreeLevel(4).length == 1);
    }

    function test_merkleTree_getProofLength() public view{
        for(uint i =0;i<16;i++){
            assert(strategy.getProofLength(i) == 4);
        }
    }

    function test_merkleTree_directLeafGeneration() public {
        // Test direct leaf generation using MerkleTreeHelper
        ManageLeaf[] memory leaves = new ManageLeaf[](2);
        
        // Create a simple leaf for wHYPE deposit
        leaves[0] = ManageLeaf(
            config.wHype,
            true,
            "deposit()",
            new address[](0),
            "",
            address(decoder)
        );
        
        // Create a simple leaf for wHYPE withdraw
        leaves[1] = ManageLeaf(
            config.wHype,
            false,
            "withdraw(uint256)",
            new address[](0),
            "",
            address(decoder)
        );

        // Generate tree directly
        bytes32[][] memory tree = _generateMerkleTree(leaves);
        
        // Verify tree structure
        assertTrue(tree.length > 0, "Tree should have levels");
        assertTrue(tree[tree.length - 1].length == 1, "Root level should have one element");
        
        bytes32 root = tree[tree.length - 1][0];
        assertTrue(root != bytes32(0), "Root should not be zero");
    }

    function test_merkleTree_managerVerification() public {
        // Test that manager can verify proofs correctly
        bytes32 root = strategy.getManageTreeRoot();
        
        // Set the root in manager
        manager.setManageRoot(address(this), root);
        
        // Try to use manager's verification (this tests the merkle verification internally)
        // We'll create a simple call that should work with the merkle tree
        
        address[] memory targets = new address[](1);
        targets[0] = config.wHype;
        
        bytes[] memory targetData = new bytes[](1);
        targetData[0] = abi.encodeWithSelector(IWHYPE.withdraw.selector, 0);
        
        bytes32[][] memory testProofs = new bytes32[][](1);
        // We need the actual proof for withdraw - this would come from strategy's proofs[1]
        // For testing, we'll use an empty proof to verify the manager rejects invalid proofs
        testProofs[0] = new bytes32[](0);
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        address[] memory decoders = new address[](1);
        decoders[0] = address(decoder);
        
        // This should revert because we're providing an invalid (empty) proof
        vm.expectRevert();
        manager.manageVaultWithMerkleVerification(
            testProofs,
            decoders,
            targets,
            targetData,
            values
        );
    }

    function test_merkleTree_invalidRoot() public {
        // Test that invalid root is rejected
        bytes32 invalidRoot = keccak256("invalid");
        
        // vm.expectRevert();
        manager.setManageRoot(address(this), invalidRoot);
        
        // Then try to use it - should fail
        address[] memory targets = new address[](1);
        targets[0] = config.wHype;
        
        bytes[] memory targetData = new bytes[](1);
        targetData[0] = abi.encodeWithSelector(IWHYPE.withdraw.selector, 0);
        
        bytes32[][] memory testProofs = new bytes32[][](1);
        testProofs[0] = new bytes32[](1);
        testProofs[0][0] = keccak256("fake proof");
        
        uint256[] memory values = new uint256[](1);
        address[] memory decoders = new address[](1);
        decoders[0] = address(decoder);
        
        vm.expectRevert();
        manager.manageVaultWithMerkleVerification(
            testProofs,
            decoders,
            targets,
            targetData,
            values
        );
    }
}