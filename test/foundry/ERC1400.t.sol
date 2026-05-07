// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1400} from "../../contracts/ERC1400.sol";
import {ERC1400Whitelist} from "../../contracts/ERC1400Whitelist.sol";
import {ERC1400Factory} from "../../contracts/ERC1400Factory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ERC1400Test is Test {
    ERC1400 public token;
    ERC1400 public implementation;
    ERC1400Whitelist public whitelist;
    ERC1400Whitelist public whitelistImpl;

    address public owner;
    address public controller;
    address public alice;
    address public bob;
    address public operator;

    bytes32 public constant DEFAULT_PARTITION = bytes32(0);
    bytes32 public PARTITION_A;
    bytes32 public PARTITION_B;

    string public constant TOKEN_NAME = "Security Token";
    string public constant TOKEN_SYMBOL = "SEC";
    uint256 public constant GRANULARITY = 1;
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;

    event TransferByPartition(
        bytes32 indexed fromPartition,
        address operator,
        address indexed from,
        address indexed to,
        uint256 value,
        bytes data,
        bytes operatorData
    );

    event Issued(address indexed operator, address indexed to, uint256 value, bytes data);

    function setUp() public {
        owner = address(this);
        controller = makeAddr("controller");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        operator = makeAddr("operator");

        PARTITION_A = keccak256("PARTITION_A");
        PARTITION_B = keccak256("PARTITION_B");

        // Deploy implementation
        implementation = new ERC1400();

        // Deploy proxy
        address[] memory controllers = new address[](1);
        controllers[0] = controller;

        bytes32[] memory defaultPartitions = new bytes32[](1);
        defaultPartitions[0] = DEFAULT_PARTITION;

        bytes memory initData = abi.encodeWithSelector(
            ERC1400.initialize.selector,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            GRANULARITY,
            controllers,
            defaultPartitions
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        token = ERC1400(address(proxy));

        // Deploy whitelist
        whitelistImpl = new ERC1400Whitelist();
        bytes memory whitelistInitData = abi.encodeWithSelector(
            ERC1400Whitelist.initialize.selector,
            true
        );
        ERC1967Proxy whitelistProxy = new ERC1967Proxy(
            address(whitelistImpl),
            whitelistInitData
        );
        whitelist = ERC1400Whitelist(address(whitelistProxy));
    }

    // ============ Deployment Tests ============

    function test_Deployment() public view {
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.granularity(), GRANULARITY);
        assertEq(token.owner(), owner);
        assertTrue(token.isIssuable());
        assertTrue(token.isControllable());
    }

    function test_ControllersRegistered() public view {
        address[] memory controllers = token.controllers();
        assertEq(controllers.length, 1);
        assertEq(controllers[0], controller);
    }

    // ============ Issuance Tests ============

    function test_Issue() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.expectEmit(true, true, true, true);
        emit Issued(owner, alice, amount, "");

        token.issue(alice, amount, "");

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_IssueByPartition() public {
        uint256 amount = 1000 * 10 ** 18;

        token.issueByPartition(PARTITION_A, alice, amount, "");

        assertEq(token.balanceOfByPartition(PARTITION_A, alice), amount);
        assertEq(token.totalSupplyByPartition(PARTITION_A), amount);
    }

    function test_RevertIssue_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.issue(bob, 1000, "");
    }

    function test_RevertIssue_NotIssuable() public {
        token.setIssuable(false);

        vm.expectRevert(ERC1400.NotIssuable.selector);
        token.issue(alice, 1000, "");
    }

    function test_RevertIssue_ZeroAddress() public {
        vm.expectRevert(ERC1400.InvalidRecipient.selector);
        token.issue(address(0), 1000, "");
    }

    // ============ Transfer Tests ============

    function test_Transfer() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(alice);
        token.transfer(bob, 100 * 10 ** 18);

        assertEq(token.balanceOf(bob), 100 * 10 ** 18);
        assertEq(token.balanceOf(alice), 900 * 10 ** 18);
    }

    function test_TransferByPartition() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(alice);
        token.transferByPartition(DEFAULT_PARTITION, bob, 100 * 10 ** 18, "");

        assertEq(token.balanceOfByPartition(DEFAULT_PARTITION, bob), 100 * 10 ** 18);
    }

    function test_RevertTransfer_InsufficientBalance() public {
        token.issue(alice, 100, "");

        vm.prank(alice);
        vm.expectRevert(ERC1400.InsufficientBalance.selector);
        token.transfer(bob, 200);
    }

    function test_RevertTransfer_ZeroAddress() public {
        token.issue(alice, 1000, "");

        vm.prank(alice);
        vm.expectRevert(ERC1400.InvalidRecipient.selector);
        token.transfer(address(0), 100);
    }

    // ============ Operator Tests ============

    function test_AuthorizeOperator() public {
        vm.prank(alice);
        token.authorizeOperator(operator);

        assertTrue(token.isOperator(operator, alice));
    }

    function test_RevokeOperator() public {
        vm.prank(alice);
        token.authorizeOperator(operator);

        vm.prank(alice);
        token.revokeOperator(operator);

        assertFalse(token.isOperator(operator, alice));
    }

    function test_OperatorTransfer() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(alice);
        token.authorizeOperator(operator);

        vm.prank(operator);
        token.operatorTransferByPartition(
            DEFAULT_PARTITION,
            alice,
            bob,
            100 * 10 ** 18,
            "",
            ""
        );

        assertEq(token.balanceOf(bob), 100 * 10 ** 18);
    }

    function test_RevertOperatorTransfer_Unauthorized() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(operator);
        vm.expectRevert(ERC1400.InvalidOperator.selector);
        token.operatorTransferByPartition(
            DEFAULT_PARTITION,
            alice,
            bob,
            100 * 10 ** 18,
            "",
            ""
        );
    }

    function test_RevertSelfAuthorization() public {
        vm.prank(alice);
        vm.expectRevert(ERC1400.SelfAuthorization.selector);
        token.authorizeOperator(alice);
    }

    // ============ Controller Tests ============

    function test_ControllerTransfer() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(controller);
        token.controllerTransfer(alice, bob, amount, "", "");

        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ControllerRedeem() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(controller);
        token.controllerRedeem(alice, amount, "", "");

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_RevertControllerTransfer_NotController() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(bob);
        vm.expectRevert(ERC1400.NotController.selector);
        token.controllerTransfer(alice, bob, amount, "", "");
    }

    function test_RevertControllerTransfer_NotControllable() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");
        token.setControllable(false);

        vm.prank(controller);
        vm.expectRevert(ERC1400.NotControllable.selector);
        token.controllerTransfer(alice, bob, amount, "", "");
    }

    // ============ Redemption Tests ============

    function test_Redeem() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(alice);
        token.redeem(100 * 10 ** 18, "");

        assertEq(token.balanceOf(alice), 900 * 10 ** 18);
        assertEq(token.totalSupply(), 900 * 10 ** 18);
    }

    function test_RedeemByPartition() public {
        uint256 amount = 1000 * 10 ** 18;
        token.issue(alice, amount, "");

        vm.prank(alice);
        token.redeemByPartition(DEFAULT_PARTITION, 100 * 10 ** 18, "");

        assertEq(token.balanceOfByPartition(DEFAULT_PARTITION, alice), 900 * 10 ** 18);
    }

    // ============ Pause Tests ============

    function test_Pause() public {
        token.pause();
        assertTrue(token.paused());
    }

    function test_Unpause() public {
        token.pause();
        token.unpause();
        assertFalse(token.paused());
    }

    function test_RevertTransfer_WhenPaused() public {
        token.issue(alice, 1000, "");
        token.pause();

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 100);
    }

    // ============ Document Tests ============

    function test_SetDocument() public {
        bytes32 docName = keccak256("PROSPECTUS");
        string memory uri = "ipfs://Qm...";
        bytes32 docHash = keccak256("document content");

        token.setDocument(docName, uri, docHash);

        (string memory storedUri, bytes32 storedHash, uint256 timestamp) = token.getDocument(
            docName
        );

        assertEq(storedUri, uri);
        assertEq(storedHash, docHash);
        assertGt(timestamp, 0);
    }

    function test_GetAllDocuments() public {
        bytes32 doc1 = keccak256("DOC1");
        bytes32 doc2 = keccak256("DOC2");

        token.setDocument(doc1, "uri1", keccak256("hash1"));
        token.setDocument(doc2, "uri2", keccak256("hash2"));

        bytes32[] memory docs = token.getAllDocuments();
        assertEq(docs.length, 2);
    }

    function test_RemoveDocument() public {
        bytes32 docName = keccak256("PROSPECTUS");
        token.setDocument(docName, "uri", keccak256("hash"));

        token.removeDocument(docName);

        vm.expectRevert(ERC1400.DocumentNotFound.selector);
        token.getDocument(docName);
    }

    // ============ Transfer Validity Tests ============

    function test_CanTransfer_Valid() public {
        token.issue(alice, 1000, "");

        vm.prank(alice);
        (bytes1 statusCode, ) = token.canTransfer(bob, 100, "");

        assertEq(statusCode, bytes1(0x51)); // TRANSFER_VERIFIED
    }

    function test_CanTransfer_InsufficientBalance() public {
        vm.prank(alice);
        (bytes1 statusCode, ) = token.canTransfer(bob, 100, "");

        assertEq(statusCode, bytes1(0x52)); // INSUFFICIENT_BALANCE
    }

    function test_CanTransfer_Paused() public {
        token.issue(alice, 1000, "");
        token.pause();

        vm.prank(alice);
        (bytes1 statusCode, ) = token.canTransfer(bob, 100, "");

        assertEq(statusCode, bytes1(0x54)); // TRANSFERS_HALTED
    }

    // ============ Fuzz Tests ============

    function testFuzz_Issue(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);

        token.issue(alice, amount, "");

        assertEq(token.balanceOf(alice), amount);
    }

    function testFuzz_Transfer(uint256 issueAmount, uint256 transferAmount) public {
        vm.assume(issueAmount > 0 && issueAmount < type(uint128).max);
        vm.assume(transferAmount > 0 && transferAmount <= issueAmount);

        token.issue(alice, issueAmount, "");

        vm.prank(alice);
        token.transfer(bob, transferAmount);

        assertEq(token.balanceOf(bob), transferAmount);
        assertEq(token.balanceOf(alice), issueAmount - transferAmount);
    }

    // ============ Partition Tests ============

    function test_PartitionsOf() public {
        token.issueByPartition(PARTITION_A, alice, 100, "");
        token.issueByPartition(PARTITION_B, alice, 200, "");

        bytes32[] memory partitions = token.partitionsOf(alice);
        assertEq(partitions.length, 2);
    }

    function test_PartitionRemovedWhenEmpty() public {
        token.issueByPartition(PARTITION_A, alice, 100, "");

        vm.prank(alice);
        token.redeemByPartition(PARTITION_A, 100, "");

        bytes32[] memory partitions = token.partitionsOf(alice);
        assertEq(partitions.length, 0);
    }
}

contract ERC1400WhitelistTest is Test {
    ERC1400 public token;
    ERC1400Whitelist public whitelist;

    address public owner;
    address public manager;
    address public alice;
    address public bob;

    function setUp() public {
        owner = address(this);
        manager = makeAddr("manager");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Deploy token
        ERC1400 impl = new ERC1400();
        address[] memory controllers = new address[](0);
        bytes32[] memory partitions = new bytes32[](1);
        partitions[0] = bytes32(0);

        bytes memory initData = abi.encodeWithSelector(
            ERC1400.initialize.selector,
            "Security Token",
            "SEC",
            1,
            controllers,
            partitions
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = ERC1400(address(proxy));

        // Deploy whitelist
        ERC1400Whitelist whitelistImpl = new ERC1400Whitelist();
        bytes memory whitelistInitData = abi.encodeWithSelector(
            ERC1400Whitelist.initialize.selector,
            true
        );
        ERC1967Proxy whitelistProxy = new ERC1967Proxy(
            address(whitelistImpl),
            whitelistInitData
        );
        whitelist = ERC1400Whitelist(address(whitelistProxy));

        // Connect validator
        token.setTokenValidator(address(whitelist));
    }

    function test_WhitelistTransfer() public {
        whitelist.batchAddToWhitelist(_toArray(alice, bob));
        token.issue(alice, 1000, "");

        vm.prank(alice);
        token.transfer(bob, 100);

        assertEq(token.balanceOf(bob), 100);
    }

    function test_RevertTransfer_NotWhitelisted() public {
        whitelist.addToWhitelist(alice);
        // bob is NOT whitelisted
        token.issue(alice, 1000, "");

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 100);
    }

    function test_TransferWhenWhitelistInactive() public {
        // No one is whitelisted, but whitelist is inactive
        whitelist.setWhitelistActive(false);
        token.issue(alice, 1000, "");

        vm.prank(alice);
        token.transfer(bob, 100);

        assertEq(token.balanceOf(bob), 100);
    }

    function _toArray(address a, address b) internal pure returns (address[] memory) {
        address[] memory arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
        return arr;
    }
}

contract ERC1400FactoryTest is Test {
    ERC1400Factory public factory;
    ERC1400 public erc1400Impl;
    ERC1400Whitelist public whitelistImpl;

    address public owner;
    address public deployer;

    function setUp() public {
        owner = address(this);
        deployer = makeAddr("deployer");

        erc1400Impl = new ERC1400();
        whitelistImpl = new ERC1400Whitelist();
        factory = new ERC1400Factory(address(erc1400Impl), address(whitelistImpl));
    }

    function test_DeployToken() public {
        bytes32[] memory partitions = new bytes32[](1);
        partitions[0] = bytes32(0);
        address[] memory controllers = new address[](0);

        vm.prank(deployer);
        address tokenAddr = factory.deployToken(
            "Test Token",
            "TST",
            1,
            controllers,
            partitions
        );

        assertTrue(tokenAddr != address(0));
        assertEq(factory.getTokenCount(), 1);
    }

    function test_DeployDeterministic() public {
        bytes32[] memory partitions = new bytes32[](1);
        partitions[0] = bytes32(0);
        address[] memory controllers = new address[](0);
        bytes32 salt = keccak256("SALT");

        address predicted = factory.computeTokenAddress(
            "Test Token",
            "TST",
            1,
            controllers,
            partitions,
            salt
        );

        vm.prank(deployer);
        address actual = factory.deployTokenDeterministic(
            "Test Token",
            "TST",
            1,
            controllers,
            partitions,
            salt
        );

        assertEq(predicted, actual);
    }

    function test_TokensByDeployer() public {
        bytes32[] memory partitions = new bytes32[](1);
        partitions[0] = bytes32(0);
        address[] memory controllers = new address[](0);

        vm.startPrank(deployer);
        factory.deployToken("Token1", "TK1", 1, controllers, partitions);
        factory.deployToken("Token2", "TK2", 1, controllers, partitions);
        vm.stopPrank();

        address[] memory tokens = factory.getTokensByDeployer(deployer);
        assertEq(tokens.length, 2);
    }
}
