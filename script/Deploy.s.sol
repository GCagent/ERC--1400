// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1400} from "../contracts/ERC1400.sol";
import {ERC1400Whitelist} from "../contracts/ERC1400Whitelist.sol";
import {ERC1400Factory} from "../contracts/ERC1400Factory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployScript
 * @dev Foundry deployment script for ERC1400 contracts
 * @notice Supports multiple deployment modes and networks
 *
 * Usage:
 *   # Deploy to local network
 *   forge script script/Deploy.s.sol --rpc-url localhost --broadcast
 *
 *   # Deploy to Sepolia
 *   forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
 *
 *   # Deploy to mainnet (dry run first)
 *   forge script script/Deploy.s.sol --rpc-url mainnet
 *   forge script script/Deploy.s.sol --rpc-url mainnet --broadcast --verify
 */
contract DeployScript is Script {
    // Deployment configuration
    struct DeployConfig {
        string tokenName;
        string tokenSymbol;
        uint256 granularity;
        bool deployFactory;
        bool deployDirect;
        bool whitelistActive;
        address[] controllers;
        bytes32[] defaultPartitions;
    }

    // Deployed contract addresses
    struct DeployedContracts {
        address erc1400Implementation;
        address whitelistImplementation;
        address factory;
        address tokenProxy;
        address whitelistProxy;
    }

    function run() external returns (DeployedContracts memory deployed) {
        // Load configuration from environment or use defaults
        DeployConfig memory config = _loadConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementations
        deployed.erc1400Implementation = address(new ERC1400());
        console2.log("ERC1400 Implementation:", deployed.erc1400Implementation);

        deployed.whitelistImplementation = address(new ERC1400Whitelist());
        console2.log("Whitelist Implementation:", deployed.whitelistImplementation);

        if (config.deployFactory) {
            // Deploy factory
            deployed.factory = address(
                new ERC1400Factory(
                    deployed.erc1400Implementation,
                    deployed.whitelistImplementation
                )
            );
            console2.log("Factory:", deployed.factory);
        }

        if (config.deployDirect) {
            // Deploy token proxy directly
            bytes memory initData = abi.encodeWithSelector(
                ERC1400.initialize.selector,
                config.tokenName,
                config.tokenSymbol,
                config.granularity,
                config.controllers,
                config.defaultPartitions
            );

            deployed.tokenProxy = address(
                new ERC1967Proxy(deployed.erc1400Implementation, initData)
            );
            console2.log("Token Proxy:", deployed.tokenProxy);

            // Deploy whitelist proxy
            bytes memory whitelistInitData = abi.encodeWithSelector(
                ERC1400Whitelist.initialize.selector,
                config.whitelistActive
            );

            deployed.whitelistProxy = address(
                new ERC1967Proxy(deployed.whitelistImplementation, whitelistInitData)
            );
            console2.log("Whitelist Proxy:", deployed.whitelistProxy);
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("Deployment complete!");

        return deployed;
    }

    function _loadConfig() internal view returns (DeployConfig memory config) {
        // Try to load from environment, fall back to defaults
        config.tokenName = vm.envOr("TOKEN_NAME", string("Security Token"));
        config.tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("SEC"));
        config.granularity = vm.envOr("GRANULARITY", uint256(1));
        config.deployFactory = vm.envOr("DEPLOY_FACTORY", true);
        config.deployDirect = vm.envOr("DEPLOY_DIRECT", true);
        config.whitelistActive = vm.envOr("WHITELIST_ACTIVE", true);

        // Default partition
        config.defaultPartitions = new bytes32[](1);
        config.defaultPartitions[0] = bytes32(0);

        // Controllers can be added via environment if needed
        config.controllers = new address[](0);

        return config;
    }
}

/**
 * @title DeployFactoryOnly
 * @dev Deploys only the factory and implementations
 */
contract DeployFactoryOnly is Script {
    function run() external returns (address factory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        address erc1400Impl = address(new ERC1400());
        address whitelistImpl = address(new ERC1400Whitelist());

        factory = address(new ERC1400Factory(erc1400Impl, whitelistImpl));

        vm.stopBroadcast();

        console2.log("ERC1400 Implementation:", erc1400Impl);
        console2.log("Whitelist Implementation:", whitelistImpl);
        console2.log("Factory:", factory);

        return factory;
    }
}

/**
 * @title DeployTokenViaFactory
 * @dev Deploys a new token using an existing factory
 */
contract DeployTokenViaFactory is Script {
    function run() external returns (address token) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");

        string memory tokenName = vm.envOr("TOKEN_NAME", string("Security Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("SEC"));
        uint256 granularity = vm.envOr("GRANULARITY", uint256(1));

        bytes32[] memory defaultPartitions = new bytes32[](1);
        defaultPartitions[0] = bytes32(0);

        address[] memory controllers = new address[](0);

        vm.startBroadcast(deployerPrivateKey);

        ERC1400Factory factory = ERC1400Factory(factoryAddress);
        token = factory.deployToken(
            tokenName,
            tokenSymbol,
            granularity,
            controllers,
            defaultPartitions
        );

        vm.stopBroadcast();

        console2.log("New Token:", token);
        return token;
    }
}

/**
 * @title DeployDeterministic
 * @dev Deploys a token with CREATE2 for deterministic address
 */
contract DeployDeterministic is Script {
    function run() external returns (address token) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        bytes32 salt = vm.envBytes32("DEPLOYMENT_SALT");

        string memory tokenName = vm.envOr("TOKEN_NAME", string("Security Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("SEC"));
        uint256 granularity = vm.envOr("GRANULARITY", uint256(1));

        bytes32[] memory defaultPartitions = new bytes32[](1);
        defaultPartitions[0] = bytes32(0);

        address[] memory controllers = new address[](0);

        ERC1400Factory factory = ERC1400Factory(factoryAddress);

        // Compute address first
        address predictedAddress = factory.computeTokenAddress(
            tokenName,
            tokenSymbol,
            granularity,
            controllers,
            defaultPartitions,
            salt
        );
        console2.log("Predicted Address:", predictedAddress);

        vm.startBroadcast(deployerPrivateKey);

        token = factory.deployTokenDeterministic(
            tokenName,
            tokenSymbol,
            granularity,
            controllers,
            defaultPartitions,
            salt
        );

        vm.stopBroadcast();

        console2.log("Deployed Token:", token);
        require(token == predictedAddress, "Address mismatch");

        return token;
    }
}
