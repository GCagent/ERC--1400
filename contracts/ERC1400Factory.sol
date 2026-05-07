// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1400} from "./ERC1400.sol";
import {ERC1400Whitelist} from "./ERC1400Whitelist.sol";

/**
 * @title ERC1400Factory
 * @dev Factory contract for deploying ERC1400 security tokens
 * @notice Supports both regular and CREATE2 deterministic deployments
 */
contract ERC1400Factory is Ownable {
    // ============ Storage ============

    /// @dev Implementation contract for ERC1400
    address public erc1400Implementation;

    /// @dev Implementation contract for Whitelist Validator
    address public whitelistImplementation;

    /// @dev Deployed tokens registry
    address[] public deployedTokens;

    /// @dev Token address to deployer mapping
    mapping(address => address) public tokenDeployer;

    /// @dev Deployer to tokens mapping
    mapping(address => address[]) public deployerTokens;

    // ============ Events ============

    event TokenDeployed(
        address indexed token,
        address indexed deployer,
        string name,
        string symbol,
        bool deterministic
    );

    event ValidatorDeployed(
        address indexed validator,
        address indexed token,
        address indexed deployer
    );

    event ImplementationUpdated(
        address indexed oldImplementation,
        address indexed newImplementation,
        string implementationType
    );

    // ============ Errors ============

    error InvalidImplementation();
    error TokenAlreadyExists();
    error DeploymentFailed();

    // ============ Constructor ============

    constructor(
        address _erc1400Implementation,
        address _whitelistImplementation
    ) Ownable(msg.sender) {
        if (_erc1400Implementation == address(0)) revert InvalidImplementation();
        erc1400Implementation = _erc1400Implementation;
        whitelistImplementation = _whitelistImplementation;
    }

    // ============ Deployment Functions ============

    /**
     * @dev Deploys a new ERC1400 token with UUPS proxy
     * @param name Token name
     * @param symbol Token symbol
     * @param granularity Token granularity
     * @param controllers Initial controllers
     * @param defaultPartitions Default partitions
     * @return tokenAddress Address of the deployed token proxy
     */
    function deployToken(
        string memory name,
        string memory symbol,
        uint256 granularity,
        address[] memory controllers,
        bytes32[] memory defaultPartitions
    ) external returns (address tokenAddress) {
        bytes memory initData = abi.encodeWithSelector(
            ERC1400.initialize.selector,
            name,
            symbol,
            granularity,
            controllers,
            defaultPartitions
        );

        ERC1967Proxy proxy = new ERC1967Proxy(erc1400Implementation, initData);
        tokenAddress = address(proxy);

        _registerToken(tokenAddress, msg.sender);

        emit TokenDeployed(tokenAddress, msg.sender, name, symbol, false);

        return tokenAddress;
    }

    /**
     * @dev Deploys a new ERC1400 token with CREATE2 for deterministic address
     * @param name Token name
     * @param symbol Token symbol
     * @param granularity Token granularity
     * @param controllers Initial controllers
     * @param defaultPartitions Default partitions
     * @param salt Salt for CREATE2
     * @return tokenAddress Address of the deployed token proxy
     */
    function deployTokenDeterministic(
        string memory name,
        string memory symbol,
        uint256 granularity,
        address[] memory controllers,
        bytes32[] memory defaultPartitions,
        bytes32 salt
    ) external returns (address tokenAddress) {
        bytes memory initData = abi.encodeWithSelector(
            ERC1400.initialize.selector,
            name,
            symbol,
            granularity,
            controllers,
            defaultPartitions
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(erc1400Implementation, initData)
        );

        tokenAddress = Create2.deploy(0, salt, proxyBytecode);
        if (tokenAddress == address(0)) revert DeploymentFailed();

        _registerToken(tokenAddress, msg.sender);

        emit TokenDeployed(tokenAddress, msg.sender, name, symbol, true);

        return tokenAddress;
    }

    /**
     * @dev Deploys a whitelist validator for a token
     * @param whitelistActive Whether whitelist is active
     * @return validatorAddress Address of the deployed validator
     */
    function deployWhitelistValidator(
        bool whitelistActive
    ) external returns (address validatorAddress) {
        if (whitelistImplementation == address(0)) revert InvalidImplementation();

        bytes memory initData = abi.encodeWithSelector(
            ERC1400Whitelist.initialize.selector,
            whitelistActive
        );

        ERC1967Proxy proxy = new ERC1967Proxy(whitelistImplementation, initData);
        validatorAddress = address(proxy);

        emit ValidatorDeployed(validatorAddress, address(0), msg.sender);

        return validatorAddress;
    }

    // ============ Prediction Functions ============

    /**
     * @dev Computes the address of a token deployed with CREATE2
     * @param name Token name
     * @param symbol Token symbol
     * @param granularity Token granularity
     * @param controllers Initial controllers
     * @param defaultPartitions Default partitions
     * @param salt Salt for CREATE2
     * @return Address where the token would be deployed
     */
    function computeTokenAddress(
        string memory name,
        string memory symbol,
        uint256 granularity,
        address[] memory controllers,
        bytes32[] memory defaultPartitions,
        bytes32 salt
    ) external view returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            ERC1400.initialize.selector,
            name,
            symbol,
            granularity,
            controllers,
            defaultPartitions
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(erc1400Implementation, initData)
        );

        return Create2.computeAddress(salt, keccak256(proxyBytecode));
    }

    // ============ Registry Functions ============

    /**
     * @dev Returns all deployed tokens
     * @return Array of token addresses
     */
    function getAllTokens() external view returns (address[] memory) {
        return deployedTokens;
    }

    /**
     * @dev Returns the number of deployed tokens
     * @return Number of tokens
     */
    function getTokenCount() external view returns (uint256) {
        return deployedTokens.length;
    }

    /**
     * @dev Returns all tokens deployed by a specific address
     * @param deployer Deployer address
     * @return Array of token addresses
     */
    function getTokensByDeployer(address deployer) external view returns (address[] memory) {
        return deployerTokens[deployer];
    }

    // ============ Admin Functions ============

    /**
     * @dev Updates the ERC1400 implementation
     * @param newImplementation New implementation address
     */
    function setERC1400Implementation(address newImplementation) external onlyOwner {
        if (newImplementation == address(0)) revert InvalidImplementation();
        address oldImpl = erc1400Implementation;
        erc1400Implementation = newImplementation;
        emit ImplementationUpdated(oldImpl, newImplementation, "ERC1400");
    }

    /**
     * @dev Updates the Whitelist implementation
     * @param newImplementation New implementation address
     */
    function setWhitelistImplementation(address newImplementation) external onlyOwner {
        address oldImpl = whitelistImplementation;
        whitelistImplementation = newImplementation;
        emit ImplementationUpdated(oldImpl, newImplementation, "Whitelist");
    }

    // ============ Internal Functions ============

    function _registerToken(address token, address deployer) internal {
        deployedTokens.push(token);
        tokenDeployer[token] = deployer;
        deployerTokens[deployer].push(token);
    }
}
