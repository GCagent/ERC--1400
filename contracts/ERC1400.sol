// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1400} from "./interfaces/IERC1400.sol";
import {IERC1400TokensValidator} from "./interfaces/IERC1400TokensValidator.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title ERC1400 Security Token
 * @dev Implementation of the ERC-1400 security token standard with UUPS upgradeability
 * @notice This contract implements partitioned tokens with operator management and controller functions
 */
contract ERC1400 is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IERC1400
{
    // ============ Constants ============

    bytes32 public constant DEFAULT_PARTITION = bytes32(0);

    // ============ Storage ============

    /// @dev Token granularity (smallest transferable unit)
    uint256 private _granularity;

    /// @dev Whether the token is issuable
    bool private _isIssuable;

    /// @dev Whether the token is controllable
    bool private _isControllable;

    /// @dev List of controllers
    address[] private _controllers;

    /// @dev Controller status mapping
    mapping(address => bool) private _isController;

    /// @dev Default partitions for issuance
    bytes32[] private _defaultPartitions;

    /// @dev Total supply by partition
    mapping(bytes32 => uint256) private _totalSupplyByPartition;

    /// @dev Token holder partition balances: holder => partition => balance
    mapping(address => mapping(bytes32 => uint256)) private _balancesByPartition;

    /// @dev Token holder partitions: holder => partitions array
    mapping(address => bytes32[]) private _partitionsOf;

    /// @dev Partition index tracking: holder => partition => index in array
    mapping(address => mapping(bytes32 => uint256)) private _partitionIndex;

    /// @dev Whether holder has partition: holder => partition => bool
    mapping(address => mapping(bytes32 => bool)) private _hasPartition;

    /// @dev Global operators: holder => operator => authorized
    mapping(address => mapping(address => bool)) private _operators;

    /// @dev Partition operators: holder => partition => operator => authorized
    mapping(address => mapping(bytes32 => mapping(address => bool))) private _operatorsByPartition;

    /// @dev Documents: name => Document struct
    mapping(bytes32 => Document) private _documents;

    /// @dev Document names array
    bytes32[] private _documentNames;

    /// @dev Document exists mapping
    mapping(bytes32 => bool) private _documentExists;

    /// @dev Token validator contract
    IERC1400TokensValidator private _tokenValidator;

    // ============ Structs ============

    struct Document {
        string uri;
        bytes32 documentHash;
        uint256 timestamp;
    }

    // ============ Errors ============

    error InvalidGranularity();
    error InvalidPartition();
    error InsufficientBalance();
    error InvalidOperator();
    error NotController();
    error NotIssuable();
    error NotControllable();
    error InvalidRecipient();
    error InvalidSender();
    error TransferValidationFailed(bytes32 reason);
    error DocumentNotFound();
    error ZeroAddress();
    error SelfAuthorization();

    // ============ Modifiers ============

    modifier onlyController() {
        if (!_isController[msg.sender]) revert NotController();
        _;
    }

    modifier isValidPartition(bytes32 partition) {
        _;
    }

    modifier respectsGranularity(uint256 value) {
        if (value % _granularity != 0) revert InvalidGranularity();
        _;
    }

    // ============ Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the ERC1400 token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param granularity_ Token granularity
     * @param controllers_ Initial controllers
     * @param defaultPartitions_ Default partitions
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 granularity_,
        address[] memory controllers_,
        bytes32[] memory defaultPartitions_
    ) public initializer {
        if (granularity_ == 0) revert InvalidGranularity();

        __ERC20_init(name_, symbol_);
        __Ownable_init(msg.sender);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _granularity = granularity_;
        _isIssuable = true;
        _isControllable = true;

        // Set default partitions
        if (defaultPartitions_.length > 0) {
            _defaultPartitions = defaultPartitions_;
        } else {
            _defaultPartitions.push(DEFAULT_PARTITION);
        }

        // Set controllers
        for (uint256 i = 0; i < controllers_.length; i++) {
            _addController(controllers_[i]);
        }
    }

    // ============ ERC20 Overrides ============

    /**
     * @dev Returns the number of decimals (always 18 for ERC1400)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-transfer}. Uses default partition.
     */
    function transfer(
        address to,
        uint256 value
    ) public override whenNotPaused returns (bool) {
        _transferByPartition(
            _defaultPartitions[0],
            msg.sender,
            to,
            value,
            "",
            ""
        );
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}. Uses default partition.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override whenNotPaused returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, value);
        _transferByPartition(_defaultPartitions[0], from, to, value, "", "");
        return true;
    }

    // ============ IERC1400 Implementation ============

    /// @inheritdoc IERC1400
    function granularity() external view override returns (uint256) {
        return _granularity;
    }

    /// @inheritdoc IERC1400
    function balanceOfByPartition(
        bytes32 partition,
        address tokenHolder
    ) external view override returns (uint256) {
        return _balancesByPartition[tokenHolder][partition];
    }

    /// @inheritdoc IERC1400
    function partitionsOf(
        address tokenHolder
    ) external view override returns (bytes32[] memory) {
        return _partitionsOf[tokenHolder];
    }

    /// @inheritdoc IERC1400
    function totalSupplyByPartition(
        bytes32 partition
    ) external view override returns (uint256) {
        return _totalSupplyByPartition[partition];
    }

    /// @inheritdoc IERC1400
    function transferByPartition(
        bytes32 partition,
        address to,
        uint256 value,
        bytes calldata data
    ) external override whenNotPaused nonReentrant returns (bytes32) {
        return _transferByPartition(partition, msg.sender, to, value, data, "");
    }

    /// @inheritdoc IERC1400
    function operatorTransferByPartition(
        bytes32 partition,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external override whenNotPaused nonReentrant returns (bytes32) {
        if (!_isOperatorForPartition(partition, msg.sender, from)) {
            revert InvalidOperator();
        }
        return _transferByPartition(partition, from, to, value, data, operatorData);
    }

    // ============ Operator Management ============

    /// @inheritdoc IERC1400
    function isOperator(
        address operator,
        address tokenHolder
    ) external view override returns (bool) {
        return _isOperator(operator, tokenHolder);
    }

    /// @inheritdoc IERC1400
    function isOperatorForPartition(
        bytes32 partition,
        address operator,
        address tokenHolder
    ) external view override returns (bool) {
        return _isOperatorForPartition(partition, operator, tokenHolder);
    }

    /// @inheritdoc IERC1400
    function authorizeOperator(address operator) external override {
        if (operator == msg.sender) revert SelfAuthorization();
        _operators[msg.sender][operator] = true;
    }

    /// @inheritdoc IERC1400
    function revokeOperator(address operator) external override {
        _operators[msg.sender][operator] = false;
    }

    /// @inheritdoc IERC1400
    function authorizeOperatorByPartition(
        bytes32 partition,
        address operator
    ) external override {
        if (operator == msg.sender) revert SelfAuthorization();
        _operatorsByPartition[msg.sender][partition][operator] = true;
        emit AuthorizedOperatorByPartition(partition, operator, msg.sender);
    }

    /// @inheritdoc IERC1400
    function revokeOperatorByPartition(
        bytes32 partition,
        address operator
    ) external override {
        _operatorsByPartition[msg.sender][partition][operator] = false;
        emit RevokedOperatorByPartition(partition, operator, msg.sender);
    }

    // ============ Controller Operations ============

    /// @inheritdoc IERC1400
    function isControllable() external view override returns (bool) {
        return _isControllable;
    }

    /// @inheritdoc IERC1400
    function controllers() external view override returns (address[] memory) {
        return _controllers;
    }

    /// @inheritdoc IERC1400
    function controllerTransfer(
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external override onlyController whenNotPaused {
        if (!_isControllable) revert NotControllable();
        _transferByPartition(_defaultPartitions[0], from, to, value, data, operatorData);
    }

    /// @inheritdoc IERC1400
    function controllerRedeem(
        address tokenHolder,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external override onlyController whenNotPaused {
        if (!_isControllable) revert NotControllable();
        _redeemByPartition(_defaultPartitions[0], tokenHolder, value, data, operatorData);
    }

    // ============ Issuance / Redemption ============

    /// @inheritdoc IERC1400
    function isIssuable() external view override returns (bool) {
        return _isIssuable;
    }

    /// @inheritdoc IERC1400
    function issue(
        address tokenHolder,
        uint256 value,
        bytes calldata data
    ) external override onlyOwner whenNotPaused {
        _issueByPartition(_defaultPartitions[0], tokenHolder, value, data);
    }

    /// @inheritdoc IERC1400
    function issueByPartition(
        bytes32 partition,
        address tokenHolder,
        uint256 value,
        bytes calldata data
    ) external override onlyOwner whenNotPaused {
        _issueByPartition(partition, tokenHolder, value, data);
    }

    /// @inheritdoc IERC1400
    function redeem(
        uint256 value,
        bytes calldata data
    ) external override whenNotPaused nonReentrant {
        _redeemByPartition(_defaultPartitions[0], msg.sender, value, data, "");
    }

    /// @inheritdoc IERC1400
    function redeemByPartition(
        bytes32 partition,
        uint256 value,
        bytes calldata data
    ) external override whenNotPaused nonReentrant {
        _redeemByPartition(partition, msg.sender, value, data, "");
    }

    /// @inheritdoc IERC1400
    function operatorRedeemByPartition(
        bytes32 partition,
        address tokenHolder,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external override whenNotPaused nonReentrant {
        if (!_isOperatorForPartition(partition, msg.sender, tokenHolder)) {
            revert InvalidOperator();
        }
        _redeemByPartition(partition, tokenHolder, value, data, operatorData);
    }

    // ============ Transfer Validity ============

    /// @inheritdoc IERC1400
    function canTransfer(
        address to,
        uint256 value,
        bytes calldata data
    ) external view override returns (bytes1 statusCode, bytes32 reasonCode) {
        return _canTransfer(_defaultPartitions[0], msg.sender, to, value, data);
    }

    /// @inheritdoc IERC1400
    function canTransferFrom(
        address from,
        address to,
        uint256 value,
        bytes calldata data
    ) external view override returns (bytes1 statusCode, bytes32 reasonCode) {
        return _canTransfer(_defaultPartitions[0], from, to, value, data);
    }

    /// @inheritdoc IERC1400
    function canTransferByPartition(
        address from,
        address to,
        bytes32 partition,
        uint256 value,
        bytes calldata data
    ) external view override returns (bytes1 statusCode, bytes32 reasonCode, bytes32 partition_) {
        (statusCode, reasonCode) = _canTransfer(partition, from, to, value, data);
        partition_ = partition;
    }

    // ============ Document Management ============

    /// @inheritdoc IERC1400
    function getDocument(
        bytes32 documentName
    ) external view override returns (string memory uri, bytes32 documentHash, uint256 timestamp) {
        if (!_documentExists[documentName]) revert DocumentNotFound();
        Document storage doc = _documents[documentName];
        return (doc.uri, doc.documentHash, doc.timestamp);
    }

    /// @inheritdoc IERC1400
    function setDocument(
        bytes32 documentName,
        string calldata uri,
        bytes32 documentHash
    ) external override onlyOwner {
        if (!_documentExists[documentName]) {
            _documentNames.push(documentName);
            _documentExists[documentName] = true;
        }
        _documents[documentName] = Document({
            uri: uri,
            documentHash: documentHash,
            timestamp: block.timestamp
        });
        emit DocumentUpdated(documentName, uri, documentHash);
    }

    /// @inheritdoc IERC1400
    function removeDocument(bytes32 documentName) external override onlyOwner {
        if (!_documentExists[documentName]) revert DocumentNotFound();

        Document storage doc = _documents[documentName];
        emit DocumentRemoved(documentName, doc.uri, doc.documentHash);

        delete _documents[documentName];
        _documentExists[documentName] = false;

        // Remove from array (swap and pop)
        for (uint256 i = 0; i < _documentNames.length; i++) {
            if (_documentNames[i] == documentName) {
                _documentNames[i] = _documentNames[_documentNames.length - 1];
                _documentNames.pop();
                break;
            }
        }
    }

    /// @inheritdoc IERC1400
    function getAllDocuments() external view override returns (bytes32[] memory) {
        return _documentNames;
    }

    // ============ Admin Functions ============

    /**
     * @dev Adds a controller
     * @param controller Address to add as controller
     */
    function addController(address controller) external onlyOwner {
        _addController(controller);
    }

    /**
     * @dev Removes a controller
     * @param controller Address to remove as controller
     */
    function removeController(address controller) external onlyOwner {
        if (!_isController[controller]) revert NotController();
        _isController[controller] = false;

        for (uint256 i = 0; i < _controllers.length; i++) {
            if (_controllers[i] == controller) {
                _controllers[i] = _controllers[_controllers.length - 1];
                _controllers.pop();
                break;
            }
        }
        emit ControllerRemoved(controller);
    }

    /**
     * @dev Sets whether the token is issuable
     * @param issuable_ New issuable status
     */
    function setIssuable(bool issuable_) external onlyOwner {
        _isIssuable = issuable_;
    }

    /**
     * @dev Sets whether the token is controllable
     * @param controllable_ New controllable status
     */
    function setControllable(bool controllable_) external onlyOwner {
        _isControllable = controllable_;
        emit ControllableUpdated(controllable_);
    }

    /**
     * @dev Sets the token validator
     * @param validator Address of the validator contract
     */
    function setTokenValidator(address validator) external onlyOwner {
        _tokenValidator = IERC1400TokensValidator(validator);
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Returns the default partitions
     */
    function getDefaultPartitions() external view returns (bytes32[] memory) {
        return _defaultPartitions;
    }

    /**
     * @dev Sets the default partitions
     * @param partitions New default partitions
     */
    function setDefaultPartitions(bytes32[] calldata partitions) external onlyOwner {
        _defaultPartitions = partitions;
    }

    // ============ Internal Functions ============

    function _addController(address controller) internal {
        if (controller == address(0)) revert ZeroAddress();
        if (!_isController[controller]) {
            _isController[controller] = true;
            _controllers.push(controller);
            emit ControllerAdded(controller);
        }
    }

    function _isOperator(
        address operator,
        address tokenHolder
    ) internal view returns (bool) {
        return operator == tokenHolder ||
               _operators[tokenHolder][operator] ||
               _isController[operator];
    }

    function _isOperatorForPartition(
        bytes32 partition,
        address operator,
        address tokenHolder
    ) internal view returns (bool) {
        return _isOperator(operator, tokenHolder) ||
               _operatorsByPartition[tokenHolder][partition][operator];
    }

    function _transferByPartition(
        bytes32 partition,
        address from,
        address to,
        uint256 value,
        bytes memory data,
        bytes memory operatorData
    ) internal respectsGranularity(value) returns (bytes32) {
        if (to == address(0)) revert InvalidRecipient();
        if (from == address(0)) revert InvalidSender();
        if (_balancesByPartition[from][partition] < value) revert InsufficientBalance();

        // Validate transfer if validator is set
        if (address(_tokenValidator) != address(0)) {
            (bool valid, bytes32 reason) = _tokenValidator.canValidate(
                address(this),
                partition,
                msg.sender,
                from,
                to,
                value,
                data,
                operatorData
            );
            if (!valid) revert TransferValidationFailed(reason);
        }

        // Update partition balances
        _balancesByPartition[from][partition] -= value;
        _balancesByPartition[to][partition] += value;

        // Update ERC20 balances
        _update(from, to, value);

        // Add partition to recipient if needed
        _addPartitionToHolder(to, partition);

        // Remove partition from sender if balance is zero
        if (_balancesByPartition[from][partition] == 0) {
            _removePartitionFromHolder(from, partition);
        }

        emit TransferByPartition(partition, msg.sender, from, to, value, data, operatorData);

        return partition;
    }

    function _issueByPartition(
        bytes32 partition,
        address tokenHolder,
        uint256 value,
        bytes memory data
    ) internal respectsGranularity(value) {
        if (!_isIssuable) revert NotIssuable();
        if (tokenHolder == address(0)) revert InvalidRecipient();

        // Update partition balances
        _balancesByPartition[tokenHolder][partition] += value;
        _totalSupplyByPartition[partition] += value;

        // Mint ERC20 tokens
        _mint(tokenHolder, value);

        // Add partition to holder if needed
        _addPartitionToHolder(tokenHolder, partition);

        emit IssuedByPartition(partition, msg.sender, tokenHolder, value, data, "");
        emit Issued(msg.sender, tokenHolder, value, data);
    }

    function _redeemByPartition(
        bytes32 partition,
        address tokenHolder,
        uint256 value,
        bytes memory data,
        bytes memory operatorData
    ) internal respectsGranularity(value) {
        if (tokenHolder == address(0)) revert InvalidSender();
        if (_balancesByPartition[tokenHolder][partition] < value) revert InsufficientBalance();

        // Update partition balances
        _balancesByPartition[tokenHolder][partition] -= value;
        _totalSupplyByPartition[partition] -= value;

        // Burn ERC20 tokens
        _burn(tokenHolder, value);

        // Remove partition from holder if balance is zero
        if (_balancesByPartition[tokenHolder][partition] == 0) {
            _removePartitionFromHolder(tokenHolder, partition);
        }

        emit RedeemedByPartition(partition, msg.sender, tokenHolder, value, data, operatorData);
        emit Redeemed(msg.sender, tokenHolder, value, data);
    }

    function _addPartitionToHolder(address holder, bytes32 partition) internal {
        if (!_hasPartition[holder][partition]) {
            _partitionIndex[holder][partition] = _partitionsOf[holder].length;
            _partitionsOf[holder].push(partition);
            _hasPartition[holder][partition] = true;
        }
    }

    function _removePartitionFromHolder(address holder, bytes32 partition) internal {
        if (_hasPartition[holder][partition]) {
            uint256 index = _partitionIndex[holder][partition];
            uint256 lastIndex = _partitionsOf[holder].length - 1;

            if (index != lastIndex) {
                bytes32 lastPartition = _partitionsOf[holder][lastIndex];
                _partitionsOf[holder][index] = lastPartition;
                _partitionIndex[holder][lastPartition] = index;
            }

            _partitionsOf[holder].pop();
            delete _partitionIndex[holder][partition];
            _hasPartition[holder][partition] = false;
        }
    }

    function _canTransfer(
        bytes32 partition,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal view returns (bytes1 statusCode, bytes32 reasonCode) {
        // Check paused
        if (paused()) {
            return (0x54, bytes32("TRANSFERS_HALTED"));
        }

        // Check zero address
        if (to == address(0)) {
            return (0x57, bytes32("INVALID_RECEIVER"));
        }

        // Check balance
        if (_balancesByPartition[from][partition] < value) {
            return (0x52, bytes32("INSUFFICIENT_BALANCE"));
        }

        // Check granularity
        if (value % _granularity != 0) {
            return (0x5B, bytes32("GRANULARITY_MISMATCH"));
        }

        // Check with validator if set
        if (address(_tokenValidator) != address(0)) {
            (bool valid, bytes32 reason) = _tokenValidator.canValidate(
                address(this),
                partition,
                msg.sender,
                from,
                to,
                value,
                data,
                ""
            );
            if (!valid) {
                return (0x59, reason);
            }
        }

        return (0x51, bytes32("TRANSFER_VERIFIED"));
    }

    // ============ UUPS Upgrade ============

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Storage Gap ============

    uint256[50] private __gap;
}
