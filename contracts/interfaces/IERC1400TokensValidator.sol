// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IERC1400TokensValidator
 * @dev Interface for validating token transfers
 */
interface IERC1400TokensValidator {
    /**
     * @dev Validates a token transfer
     * @param token Address of the token contract
     * @param partition Partition from which tokens are transferred
     * @param operator Address performing the transfer
     * @param from Sender address
     * @param to Recipient address
     * @param value Number of tokens to transfer
     * @param data Information attached to the transfer by the holder
     * @param operatorData Information attached by the operator
     * @return valid Whether the transfer is valid
     * @return reasonCode Reason code if transfer is invalid
     */
    function canValidate(
        address token,
        bytes32 partition,
        address operator,
        address from,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata operatorData
    ) external view returns (bool valid, bytes32 reasonCode);
}
