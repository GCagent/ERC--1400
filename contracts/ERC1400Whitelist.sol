// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1400TokensValidator} from "./interfaces/IERC1400TokensValidator.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title ERC1400Whitelist
 * @dev Whitelist-based validator for ERC1400 transfers
 * @notice Validates transfers based on whitelist status of sender and receiver
 */
contract ERC1400Whitelist is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IERC1400TokensValidator
{
    // ============ Storage ============

    /// @dev Whitelist status: address => whitelisted
    mapping(address => bool) private _whitelist;

    /// @dev Whitelist managers
    mapping(address => bool) private _whitelistManagers;

    /// @dev Whether whitelist is active
    bool private _whitelistActive;

    // ============ Events ============

    event AddedToWhitelist(address indexed account, address indexed addedBy);
    event RemovedFromWhitelist(address indexed account, address indexed removedBy);
    event WhitelistManagerAdded(address indexed manager);
    event WhitelistManagerRemoved(address indexed manager);
    event WhitelistStatusUpdated(bool active);

    // ============ Errors ============

    error NotWhitelistManager();
    error AlreadyWhitelisted();
    error NotWhitelisted();
    error ZeroAddress();

    // ============ Modifiers ============

    modifier onlyWhitelistManager() {
        if (!_whitelistManagers[msg.sender] && msg.sender != owner()) {
            revert NotWhitelistManager();
        }
        _;
    }

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the whitelist validator
     * @param whitelistActive_ Whether whitelist is active
     */
    function initialize(bool whitelistActive_) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _whitelistActive = whitelistActive_;
    }

    // ============ IERC1400TokensValidator Implementation ============

    /**
     * @inheritdoc IERC1400TokensValidator
     */
    function canValidate(
        address /* token */,
        bytes32 /* partition */,
        address /* operator */,
        address from,
        address to,
        uint256 /* value */,
        bytes calldata /* data */,
        bytes calldata /* operatorData */
    ) external view override returns (bool valid, bytes32 reasonCode) {
        if (!_whitelistActive) {
            return (true, bytes32("WHITELIST_INACTIVE"));
        }

        // Allow minting (from = address(0))
        if (from == address(0)) {
            if (!_whitelist[to]) {
                return (false, bytes32("RECEIVER_NOT_WHITELISTED"));
            }
            return (true, bytes32("TRANSFER_VALID"));
        }

        // Allow burning (to = address(0))
        if (to == address(0)) {
            if (!_whitelist[from]) {
                return (false, bytes32("SENDER_NOT_WHITELISTED"));
            }
            return (true, bytes32("TRANSFER_VALID"));
        }

        // Check both parties are whitelisted
        if (!_whitelist[from]) {
            return (false, bytes32("SENDER_NOT_WHITELISTED"));
        }
        if (!_whitelist[to]) {
            return (false, bytes32("RECEIVER_NOT_WHITELISTED"));
        }

        return (true, bytes32("TRANSFER_VALID"));
    }

    // ============ Whitelist Management ============

    /**
     * @dev Adds an address to the whitelist
     * @param account Address to add
     */
    function addToWhitelist(address account) external onlyWhitelistManager {
        if (account == address(0)) revert ZeroAddress();
        if (_whitelist[account]) revert AlreadyWhitelisted();

        _whitelist[account] = true;
        emit AddedToWhitelist(account, msg.sender);
    }

    /**
     * @dev Adds multiple addresses to the whitelist
     * @param accounts Addresses to add
     */
    function batchAddToWhitelist(address[] calldata accounts) external onlyWhitelistManager {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] != address(0) && !_whitelist[accounts[i]]) {
                _whitelist[accounts[i]] = true;
                emit AddedToWhitelist(accounts[i], msg.sender);
            }
        }
    }

    /**
     * @dev Removes an address from the whitelist
     * @param account Address to remove
     */
    function removeFromWhitelist(address account) external onlyWhitelistManager {
        if (!_whitelist[account]) revert NotWhitelisted();

        _whitelist[account] = false;
        emit RemovedFromWhitelist(account, msg.sender);
    }

    /**
     * @dev Removes multiple addresses from the whitelist
     * @param accounts Addresses to remove
     */
    function batchRemoveFromWhitelist(address[] calldata accounts) external onlyWhitelistManager {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (_whitelist[accounts[i]]) {
                _whitelist[accounts[i]] = false;
                emit RemovedFromWhitelist(accounts[i], msg.sender);
            }
        }
    }

    /**
     * @dev Checks if an address is whitelisted
     * @param account Address to check
     * @return Whether the address is whitelisted
     */
    function isWhitelisted(address account) external view returns (bool) {
        return _whitelist[account];
    }

    // ============ Manager Management ============

    /**
     * @dev Adds a whitelist manager
     * @param manager Manager address to add
     */
    function addWhitelistManager(address manager) external onlyOwner {
        if (manager == address(0)) revert ZeroAddress();
        _whitelistManagers[manager] = true;
        emit WhitelistManagerAdded(manager);
    }

    /**
     * @dev Removes a whitelist manager
     * @param manager Manager address to remove
     */
    function removeWhitelistManager(address manager) external onlyOwner {
        _whitelistManagers[manager] = false;
        emit WhitelistManagerRemoved(manager);
    }

    /**
     * @dev Checks if an address is a whitelist manager
     * @param manager Address to check
     * @return Whether the address is a manager
     */
    function isWhitelistManager(address manager) external view returns (bool) {
        return _whitelistManagers[manager];
    }

    // ============ Admin Functions ============

    /**
     * @dev Sets whether the whitelist is active
     * @param active New active status
     */
    function setWhitelistActive(bool active) external onlyOwner {
        _whitelistActive = active;
        emit WhitelistStatusUpdated(active);
    }

    /**
     * @dev Returns whether the whitelist is active
     */
    function isWhitelistActive() external view returns (bool) {
        return _whitelistActive;
    }

    // ============ UUPS Upgrade ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Storage Gap ============

    uint256[50] private __gap;
}
