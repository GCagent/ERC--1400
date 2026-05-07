// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC1400TokensChecker
 * @dev Interface for checking token transfer validity
 */
interface IERC1400TokensChecker {
    /**
     * @dev Checks if a transfer can be executed
     * @param token Token contract address
     * @param partition Partition to check
     * @param operator Operator address
     * @param from Sender address
     * @param to Recipient address
     * @param value Amount to transfer
     * @param data Transfer data
     * @param operatorData Operator data
     * @return statusCode ERC-1066 status code
     * @return reasonCode Reason code for the status
     */
    function canTransferByPartition(
        address token,
        bytes32 partition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external view returns (bytes1 statusCode, bytes32 reasonCode);
}

/**
 * @title ERC1400 Transfer Status Codes (ERC-1066)
 * @dev Standard status codes for transfer validation
 */
library ERC1400StatusCodes {
    // Success codes (0x5X)
    bytes1 constant TRANSFER_SUCCESS = 0x50;
    bytes1 constant TRANSFER_VERIFIED = 0x51;

    // Failure codes (0x5X)
    bytes1 constant TRANSFER_FAILURE = 0x50;
    bytes1 constant INSUFFICIENT_BALANCE = 0x52;
    bytes1 constant INSUFFICIENT_ALLOWANCE = 0x53;
    bytes1 constant TRANSFERS_HALTED = 0x54;
    bytes1 constant FUNDS_LOCKED = 0x55;
    bytes1 constant INVALID_SENDER = 0x56;
    bytes1 constant INVALID_RECEIVER = 0x57;
    bytes1 constant INVALID_OPERATOR = 0x58;

    // Application-specific codes (0x5X)
    bytes1 constant TRANSFER_NOT_ALLOWED = 0x59;
    bytes1 constant PARTITION_DOES_NOT_EXIST = 0x5A;
    bytes1 constant GRANULARITY_MISMATCH = 0x5B;
}
