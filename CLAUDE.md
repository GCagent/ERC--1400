# CLAUDE.md — ERC-1400 Security Token Standard

## Project Overview

This repository implements the **ERC-1400 Security Token Standard** — an umbrella framework for issuing and managing security tokens on Ethereum-compatible blockchains. ERC-1400 composes several sub-standards that together provide partitioned (tranche-based) token balances, on-chain document management, controller operations, and transfer restriction enforcement.

### Sub-Standards

| Standard | Name | Purpose |
|----------|------|---------|
| ERC-1410 | Partially Fungible Token | Partition/tranche-based balances — tokens within each partition are fungible but distinct across partitions |
| ERC-1594 | Core Security Token | Issuance, redemption, and transfer validation with on-chain/off-chain checks (`canTransfer`) |
| ERC-1643 | Document Management | Attach, update, and remove URI-based documents (e.g., prospectus, legal agreements) to the token contract |
| ERC-1644 | Controller Operations | Privileged force-transfer and force-redemption for regulatory compliance (court orders, lost keys) |

The token is ERC-20 compatible — it implements `transfer`, `balanceOf`, `totalSupply`, etc. — but adds security-token-specific behaviour on top.

---

## Repository Structure

```
ERC--1400/
├── CLAUDE.md              # This file — AI assistant guide
├── README.md              # Project README
├── contracts/             # Solidity smart contracts
│   ├── ERC1400.sol        # Main security token contract
│   ├── interfaces/        # ERC-1400 interfaces
│   │   ├── IERC1400.sol   # Aggregated interface (extends IERC20 + IERC1643)
│   │   ├── IERC1410.sol   # Partially Fungible Token interface
│   │   ├── IERC1594.sol   # Core Security Token interface
│   │   ├── IERC1643.sol   # Document Management interface
│   │   └── IERC1644.sol   # Controller Operations interface
│   ├── extensions/        # Optional extensions
│   │   ├── Whitelistable.sol        # KYC/AML address allowlist
│   │   ├── TransferRestrictor.sol   # Pluggable restriction logic
│   │   └── CertificateValidator.sol # ECDSA off-chain cert validation
│   └── mocks/             # Test helper contracts
├── test/                  # Test files (Hardhat/Foundry)
├── scripts/               # Deployment and operational scripts
├── hardhat.config.ts      # Hardhat configuration (if using Hardhat)
├── foundry.toml           # Foundry configuration (if using Foundry)
└── package.json           # Node.js dependencies
```

> **Note:** This project is in early development. Some directories and files listed above may not yet exist.

---

## Key Concepts

### Partitions (Tranches)

Tokens are divided into **partitions** (also called tranches). Each partition is identified by a `bytes32` key and represents a distinct class of tokens (e.g., `locked`, `vested`, `classA`, `classB`). A holder's total balance is the sum of their balances across all partitions.

Common real-world partition uses:
- `LOCKED` / `UNLOCKED` — vesting or lock-up periods
- `CLASS_A` / `CLASS_B` — different share classes with distinct voting rights
- Domestic / international investor tranches — different regulatory holding periods

The **default partition** is typically `bytes32(0)`. The ERC-20 `transfer` function operates on the default partition.

```solidity
function balanceOfByPartition(bytes32 partition, address holder) external view returns (uint256);
function partitionsOf(address holder) external view returns (bytes32[] memory);
function transferByPartition(bytes32 partition, address to, uint256 value, bytes calldata data) external returns (bytes32);
function operatorTransferByPartition(bytes32 partition, address from, address to, uint256 value, bytes calldata data, bytes calldata operatorData) external returns (bytes32);
```

### Transfer Restrictions

Security tokens must enforce transfer restrictions (investor accreditation, jurisdiction limits, lock-up periods). The `canTransfer` family of functions returns a status code (ESC — Ethereum Status Code, ERC-1066) indicating whether a transfer would succeed:

```solidity
function canTransfer(address to, uint256 value, bytes calldata data) external view returns (bytes1 statusCode, bytes32 reasonCode);
function canTransferByPartition(bytes32 partition, address to, uint256 value, bytes calldata data) external view returns (bytes1 statusCode, bytes32 reasonCode, bytes32 destinationPartition);
```

Common ESC codes (ERC-1066, `0x5_` range):
- `0x50` — Transfer failure (generic)
- `0x51` — Transfer success
- `0x52` — Insufficient balance
- `0x53` — Insufficient allowance
- `0x54` — Transfers halted (paused)
- `0x55` — Funds locked (lockup period)
- `0x56` — Invalid sender
- `0x57` — Invalid receiver
- `0x58` — Invalid operator

### Certificate-Based Transfer Validation

The `bytes calldata data` parameter in transfer functions supports **off-chain certificate injection** — the primary mechanism for keeping sensitive KYC data off-chain:

1. An off-chain compliance server validates transfer parameters against KYC/AML databases
2. It signs a certificate encoding `(functionSelector, parameters, expiryDate, nonce)`
3. The token holder submits the signed certificate as `data` in the transfer call
4. The on-chain contract uses `ecrecover` (via OpenZeppelin's `ECDSA` library) to verify the certificate signer is an authorized compliance role

This pattern avoids storing PII on-chain while providing cryptographic proof of compliance.

### Controller Operations

A designated controller address (typically a multisig or governance contract) can force-transfer or force-redeem tokens. This is necessary for legal compliance scenarios (court orders, asset recovery, regulatory seizure). Controller operations emit distinct events and should be used sparingly.

```solidity
function isControllable() external view returns (bool);
function controllerTransfer(address from, address to, uint256 value, bytes calldata data, bytes calldata operatorData) external;
function controllerRedeem(address tokenHolder, uint256 value, bytes calldata data, bytes calldata operatorData) external;
```

**Security:** The controller must never be an EOA — use a multisig (e.g., Gnosis Safe). Consider timelocks on controller actions. `isControllable()` returning `false` is irreversible by convention.

### Document Management

The contract can store references to off-chain documents (legal agreements, prospectuses) via URI + document hash pairs:

```solidity
function setDocument(bytes32 name, string calldata uri, bytes32 documentHash) external;
function getDocument(bytes32 name) external view returns (string memory uri, bytes32 documentHash, uint256 timestamp);
function removeDocument(bytes32 name) external;
function getAllDocuments() external view returns (bytes32[] memory);
```

Typical documents: offering memorandum, transfer restriction legend, shareholder agreement. Actual files live off-chain (IPFS or HTTPS); when a document changes, updating the `documentHash` on-chain creates an immutable audit trail.

---

### Typical Contract Architecture

```solidity
contract ERC1400 is IERC1400, ERC20, Ownable, Pausable, ReentrancyGuard, AccessControl {
    // Roles
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    // Default partition
    bytes32 public constant DEFAULT_PARTITION = bytes32(0);

    // Partition storage
    mapping(address => bytes32[]) internal _partitionsOf;
    mapping(bytes32 => mapping(address => uint256)) internal _balanceOfByPartition;
    bytes32[] internal _totalPartitions;
    mapping(bytes32 => uint256) internal _totalSupplyByPartition;

    // Document storage (ERC-1643)
    mapping(bytes32 => Document) internal _documents;
    bytes32[] internal _documentNames;

    // Flags
    bool internal _isControllable;
    bool internal _isIssuable;
}
```

### Key Invariants

These invariants **must** hold at all times. Breaking them is a critical bug:

1. `balanceOf(holder) == Σ balanceOfByPartition(p, holder)` for all `p` in `partitionsOf(holder)`
2. `totalSupply() == Σ _totalSupplyByPartition[p]` for all `p` in `_totalPartitions`
3. No transfer path (including operator transfers) bypasses `canTransfer` validation — only controller operations are exempt, and they emit `ControllerTransfer` instead of `Transfer`
4. Partitions with zero balance should be removed from `partitionsOf` to keep the array clean
5. `isIssuable()` returning `false` is irreversible — once issuance is closed, it cannot be re-opened

---

## Development Setup

### Prerequisites

- **Node.js** >= 18.x
- **Solidity** compiler 0.8.x (managed by tooling)
- **Git**

### Using Hardhat (recommended for this project)

```bash
npm install                  # Install dependencies
npx hardhat compile          # Compile contracts
npx hardhat test             # Run tests
npx hardhat test --grep "partition"  # Run specific tests
npx hardhat coverage         # Generate coverage report
```

### Using Foundry (alternative)

```bash
forge build                  # Compile contracts
forge test                   # Run tests
forge test -vvv              # Run tests with verbose output
forge coverage               # Generate coverage report
```

---

## Testing Conventions

- **Unit tests** should cover every public/external function in each contract
- Test files mirror the contract structure: `contracts/ERC1400.sol` → `test/ERC1400.test.ts` (Hardhat) or `test/ERC1400.t.sol` (Foundry)
- Use descriptive `describe`/`it` blocks (Hardhat) or clearly named test functions prefixed with `test_` (Foundry)
- Always test:
  - Happy path transfers and partition operations
  - Transfer restriction enforcement (rejected transfers with correct ESC codes)
  - Controller operations (force transfer, force redeem) including authorization checks
  - Document management (set, get, remove, list)
  - Edge cases: zero amounts, self-transfers, empty partitions, unauthorized callers
  - Event emissions for all state-changing operations

### Running Tests

```bash
# Hardhat
npx hardhat test

# Foundry
forge test
```

---

## Coding Conventions

### Solidity

- **Solidity version:** `pragma solidity ^0.8.20;` (or latest stable 0.8.x)
- **Style:** Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- **Naming:**
  - Contracts: `PascalCase` (e.g., `ERC1400`, `TransferRestrictor`)
  - Functions: `camelCase` (e.g., `transferByPartition`, `canTransfer`)
  - Constants: `UPPER_SNAKE_CASE` (e.g., `DEFAULT_PARTITION`)
  - Events: `PascalCase` (e.g., `TransferByPartition`, `DocumentUpdated`)
  - Internal/private state variables: prefix with `_` (e.g., `_partitions`, `_controllers`)
- **Imports:** Use named imports (`import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";`)
- **Access control:** Use OpenZeppelin's `Ownable` or `AccessControl` for role-based permissions
- **Error handling:** Prefer custom errors over `require` strings for gas efficiency:
  ```solidity
  error InvalidPartition(bytes32 partition);
  error TransferRestricted(bytes1 statusCode);
  ```
- **NatSpec:** Document all public/external functions with `@notice`, `@param`, `@return`, and `@dev` where helpful

### TypeScript (Tests & Scripts)

- Use TypeScript for all Hardhat tests and scripts
- Use `ethers.js` v6 (bundled with Hardhat) for contract interactions
- Use `chai` + `@nomicfoundation/hardhat-chai-matchers` for assertions

---

## Security Considerations

ERC-1400 contracts handle regulated financial instruments. Keep these principles in mind:

1. **Transfer restrictions are critical** — never allow a code path that bypasses `canTransfer` checks
2. **Controller powers must be tightly scoped** — controller operations should emit events and be auditable
3. **Partition integrity** — ensure partition balances always sum to the holder's total balance
4. **Reentrancy protection** — use OpenZeppelin's `ReentrancyGuard` on state-changing external functions
5. **Integer overflow** — Solidity 0.8.x has built-in overflow checks; do not use `unchecked` blocks for balance arithmetic
6. **Access control** — issuance, redemption, and controller operations must be restricted to authorized roles
7. **Upgrade safety** — if using proxy patterns (UUPS/Transparent), ensure storage layout compatibility
8. **Audit** — all contracts should be professionally audited before mainnet deployment
9. **Static analysis** — run Slither or Mythril before any deployment to catch common vulnerabilities

---

## Reference Implementations

When developing, refer to these established implementations:

- **ConsenSys/UniversalToken** (`github.com/Consensys/UniversalToken`) — The canonical ERC-1400 reference implementation. Uses certificate-based transfer validation and ERC-1820 interface hooks. Archived March 2025 — reference only, not actively maintained. License: Apache-2.0.
- **taurushq-io/UniversalTokenERC1400** (`github.com/taurushq-io/UniversalTokenERC1400`) — Hardhat-compatible fork of ConsenSys UniversalToken. Solidity 0.8.7, OpenZeppelin 4.7.3. Note: OpenZeppelin must be pinned at 4.7.3 (4.8.x+ has breaking interface changes when used with this codebase).
- **SecurityTokenStandard/EIP-Spec** (`github.com/SecurityTokenStandard/EIP-Spec`) — Canonical specification repository with EIP markdown docs and reference Solidity interfaces.
- **OpenZeppelin Contracts** — Base contracts for ERC-20, AccessControl, Pausable, ReentrancyGuard, ECDSA, and EIP712.

---

## Common Tasks for AI Assistants

### When implementing new features:
1. Read existing interfaces first (`IERC1400.sol` and sub-interfaces)
2. Ensure ERC-20 backward compatibility is maintained
3. Verify partition balance invariants (sum of partition balances == total balance)
4. Add comprehensive tests covering happy path, reverts, and edge cases
5. Check that events are emitted for all state changes

### When reviewing or modifying contracts:
1. Verify transfer restriction logic is not bypassed
2. Check controller operation authorization
3. Ensure custom errors are used consistently
4. Validate NatSpec documentation is present and accurate
5. Confirm test coverage for any modified code paths

### When debugging:
1. Check ESC (status code) returns from `canTransfer` functions
2. Verify partition existence and balances
3. Inspect event logs for transfer and controller operations
4. Use Hardhat's `console.log` or Foundry's `console2.log` for in-contract debugging

---

## Git Workflow

- **Main branch:** `master`
- **Feature branches:** `claude/<feature-description>-<session-id>` or `feature/<description>`
- Write clear, descriptive commit messages
- Keep commits atomic — one logical change per commit
- Run tests before pushing: `npx hardhat test` or `forge test`
