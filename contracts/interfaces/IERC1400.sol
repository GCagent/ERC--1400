// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC1400 Security Token Standard
 * @dev Interface for the ERC-1400 security token standard
 * @notice Combines ERC-20 compatibility with partition-based token management
 */
interface IERC1400 {
    // ============ Events ============

    /// @notice Emitted when tokens are transferred by partition
    event TransferByPartition(
        bytes32 indexed fromPartition,
        address operator,
        address indexed from,
        address indexed to,
        uint256 value,
        bytes data,
        bytes operatorData
    );

    /// @notice Emitted when tokens change partition
    event ChangedPartition(
        bytes32 indexed fromPartition,
        bytes32 indexed toPartition,
        uint256 value
    );

    /// @notice Emitted when an operator is authorized for a partition
    event AuthorizedOperatorByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed tokenHolder
    );

    /// @notice Emitted when an operator is revoked for a partition
    event RevokedOperatorByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed tokenHolder
    );

    /// @notice Emitted when a controller is added
    event ControllerAdded(address indexed controller);

    /// @notice Emitted when a controller is removed
    event ControllerRemoved(address indexed controller);

    /// @notice Emitted when tokens are issued
    event Issued(
        address indexed operator,
        address indexed to,
        uint256 value,
        bytes data
    );

    /// @notice Emitted when tokens are redeemed
    event Redeemed(
        address indexed operator,
        address indexed from,
        uint256 value,
        bytes data
    );

    /// @notice Emitted when tokens are issued by partition
    event IssuedByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed to,
        uint256 value,
        bytes data,
        bytes operatorData
    );

    /// @notice Emitted when tokens are redeemed by partition
    event RedeemedByPartition(
        bytes32 indexed partition,
        address indexed operator,
        address indexed from,
        uint256 value,
        bytes data,
        bytes operatorData
    );

    /// @notice Emitted on document updates
    event DocumentUpdated(
        bytes32 indexed name,
        string uri,
        bytes32 documentHash
    );

    /// @notice Emitted when document is removed
    event DocumentRemoved(
        bytes32 indexed name,
        string uri,
        bytes32 documentHash
    );

    /// @notice Emitted when controllable status changes
    event ControllableUpdated(bool indexed controllable);

    // ============ Token Information ============

    /// @notice Returns the name of the token
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token
    function symbol() external view returns (string memory);

    /// @notice Returns the total supply of the token
    function totalSupply() external view returns (uint256);

    /// @notice Returns the balance of a token holder
    function balanceOf(address tokenHolder) external view returns (uint256);

    /// @notice Returns the granularity of the token
    function granularity() external view returns (uint256);

    // ============ Partition Management ============

    /// @notice Returns the balance of a token holder for a specific partition
    function balanceOfByPartition(
        bytes32 partition,
        address tokenHolder
    ) external view returns (uint256);

    /// @notice Returns all partitions of a token holder
    function partitionsOf(
        address tokenHolder
    ) external view returns (bytes32[] memory);

    /// @notice Returns the total supply for a specific partition
    function totalSupplyByPartition(
        bytes32 partition
    ) external view returns (uint256);

    // ============ Transfers ============

    /// @notice Transfers tokens by partition
    function transferByPartition(
        bytes32 partition,
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bytes32);

    /// @notice Operator transfer by partition
    function operatorTransferByPartition(
        bytes32 partition,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external returns (bytes32);

    // ============ Operator Management ============

    /// @notice Checks if an operator is authorized for a token holder
    function isOperator(
        address operator,
        address tokenHolder
    ) external view returns (bool);

    /// @notice Checks if an operator is authorized for a partition
    function isOperatorForPartition(
        bytes32 partition,
        address operator,
        address tokenHolder
    ) external view returns (bool);

    /// @notice Authorizes an operator for all partitions
    function authorizeOperator(address operator) external;

    /// @notice Revokes an operator for all partitions
    function revokeOperator(address operator) external;

    /// @notice Authorizes an operator for a specific partition
    function authorizeOperatorByPartition(
        bytes32 partition,
        address operator
    ) external;

    /// @notice Revokes an operator for a specific partition
    function revokeOperatorByPartition(
        bytes32 partition,
        address operator
    ) external;

    // ============ Controller Operations ============

    /// @notice Checks if the token is controllable
    function isControllable() external view returns (bool);

    /// @notice Returns all controllers
    function controllers() external view returns (address[] memory);

    /// @notice Controller forced transfer
    function controllerTransfer(
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external;

    /// @notice Controller forced redemption
    function controllerRedeem(
        address tokenHolder,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external;

    // ============ Issuance / Redemption ============

    /// @notice Checks if the token is issuable
    function isIssuable() external view returns (bool);

    /// @notice Issues tokens to an address
    function issue(
        address tokenHolder,
        uint256 value,
        bytes calldata data
    ) external;

    /// @notice Issues tokens to a specific partition
    function issueByPartition(
        bytes32 partition,
        address tokenHolder,
        uint256 value,
        bytes calldata data
    ) external;

    /// @notice Redeems tokens from the caller
    function redeem(uint256 value, bytes calldata data) external;

    /// @notice Redeems tokens from a specific partition
    function redeemByPartition(
        bytes32 partition,
        uint256 value,
        bytes calldata data
    ) external;

    /// @notice Operator redeems tokens by partition
    function operatorRedeemByPartition(
        bytes32 partition,
        address tokenHolder,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external;

    // ============ Transfer Validity ============

    /// @notice Checks if a transfer can be executed
    function canTransfer(
        address to,
        uint256 value,
        bytes calldata data
    ) external view returns (bytes1 statusCode, bytes32 reasonCode);

    /// @notice Checks if a transfer from can be executed
    function canTransferFrom(
        address from,
        address to,
        uint256 value,
        bytes calldata data
    ) external view returns (bytes1 statusCode, bytes32 reasonCode);

    /// @notice Checks if a transfer by partition can be executed
    function canTransferByPartition(
        address from,
        address to,
        bytes32 partition,
        uint256 value,
        bytes calldata data
    ) external view returns (bytes1 statusCode, bytes32 reasonCode, bytes32 partition_);

    // ============ Document Management ============

    /// @notice Gets a document by name
    function getDocument(
        bytes32 documentName
    ) external view returns (string memory uri, bytes32 documentHash, uint256 timestamp);

    /// @notice Sets a document
    function setDocument(
        bytes32 documentName,
        string calldata uri,
        bytes32 documentHash
    ) external;

    /// @notice Removes a document
    function removeDocument(bytes32 documentName) external;

    /// @notice Returns all document names
    function getAllDocuments() external view returns (bytes32[] memory);
}
