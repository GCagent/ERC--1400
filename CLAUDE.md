# CLAUDE.md — ERC-1400 Security Token Standard

## Project Overview

This repository implements the **ERC-1400 Security Token Standard** — an umbrella framework for issuing, managing, and transferring security tokens on Ethereum and EVM-compatible chains. ERC-1400 combines multiple sub-standards to provide compliant, partition-aware, controller-managed security tokens that are backwards-compatible with ERC-20.

### Sub-Standards

| Standard | Name | Purpose |
|----------|------|---------|
| ERC-1410 | Partially Fungible Token | Partition (tranche) management — groups a holder's balance into `bytes32`-keyed partitions with independent metadata and transfer rules |
| ERC-1594 | Core Security Token | On-chain transfer restriction checking with error signalling (EIP-1066 status codes), off-chain data injection, issuance/redemption semantics |
| ERC-1643 | Document Management | Attach and manage legal/regulatory documents (URIs + document hashes) on-chain |
| ERC-1644 | Controller Operations | Privileged force-transfer and force-redeem by a designated controller address (for regulatory/legal enforcement) |

---

## Repository Structure (Target)

```
ERC--1400/
├── CLAUDE.md                  # This file — AI assistant guide
├── README.md                  # Project readme
├── contracts/
│   ├── ERC1400.sol            # Main token — aggregates all sub-standards
│   ├── interfaces/
│   │   ├── IERC1400.sol       # Combined umbrella interface (extends IERC20, IERC1643)
│   │   ├── IERC1410.sol       # Partition interface
│   │   ├── IERC1594.sol       # Core security token interface
│   │   ├── IERC1643.sol       # Document management interface
│   │   └── IERC1644.sol       # Controller operations interface
│   ├── token/
│   │   ├── ERC1400Raw.sol     # Base layer: certificates, controllers, hooks, migration
│   │   ├── ERC1400Partition.sol # Partition layer on top of Raw
│   │   └── ERC1400ERC20.sol   # ERC-20 backwards compatibility shim
│   ├── extensions/
│   │   ├── ERC1400TokensValidator.sol  # Allowlist, blocklist, pause, certificate validation
│   │   ├── ERC1400TokensChecker.sol    # Read-only canTransfer logic
│   │   └── ERC1400HoldableToken.sol    # Delivery-vs-payment hold escrow (optional)
│   ├── roles/
│   │   ├── MinterRole.sol             # Minter access control
│   │   ├── CertificateSignerRole.sol  # Off-chain signer role
│   │   ├── AllowlistedRole.sol        # KYC whitelist
│   │   └── BlocklistedRole.sol        # AML blacklist
│   ├── registry/
│   │   ├── ERC1820Client.sol          # Helpers to call ERC-1820 registry
│   │   └── ERC1820Implementer.sol     # Implements canImplementInterfaceForAddress
│   └── mocks/                 # Test mocks and helpers
├── test/
│   ├── ERC1400.test.js        # Core integration tests
│   ├── ERC1400Partition.test.js # Partition-specific tests
│   ├── ERC1400Issuance.test.js  # Issue / redeem lifecycle
│   ├── ERC1400Certificate.test.js # Nonce-based and salt-based certificates
│   ├── ERC1400Controller.test.js  # Force-transfer and force-redeem
│   ├── ERC1400Document.test.js    # ERC-1643 document management
│   ├── ERC1400Validator.test.js   # Allowlist, blocklist, pause tests
│   └── helpers/               # Test utilities and fixtures
├── scripts/
│   ├── deploy.js              # Deployment script
│   └── verify.js              # Etherscan verification
├── hardhat.config.js          # Hardhat configuration
├── package.json
├── .solhint.json              # Solidity linter config
├── .prettierrc                # Code formatter config
├── .env.example               # Environment variable template (no secrets)
└── .github/
    └── workflows/
        └── ci.yml             # CI pipeline
```

### Inheritance Hierarchy

The recommended layered architecture (following ConsenSys UniversalToken):

```
ERC1400Raw               ← Base: certificates, controllers, ERC-1820 hooks, migration
    └── ERC1400Partition  ← Partition/tranche system on top of Raw
            └── ERC1400   ← Adds issuance/redemption + document management
                    └── ERC1400ERC20  ← ERC-20 backwards compatibility (decimals = 18)
```

Top-level contract also inherits: `IERC20`, `IERC1400`, `Ownable`, `ERC1820Client`, `ERC1820Implementer`, `MinterRole`

---

## Key Interfaces

### IERC1410 — Partially Fungible Token

```solidity
interface IERC1410 {
    // Balances
    function balanceOf(address _tokenHolder) external view returns (uint256);
    function balanceOfByPartition(bytes32 _partition, address _tokenHolder) external view returns (uint256);
    function partitionsOf(address _tokenHolder) external view returns (bytes32[] memory);
    function totalSupply() external view returns (uint256);

    // Transfers
    function transferByPartition(bytes32 _partition, address _to, uint256 _value, bytes calldata _data) external returns (bytes32);
    function operatorTransferByPartition(bytes32 _partition, address _from, address _to, uint256 _value, bytes calldata _data, bytes calldata _operatorData) external returns (bytes32);
    function canTransferByPartition(address _from, address _to, bytes32 _partition, uint256 _value, bytes calldata _data) external view returns (byte, bytes32, bytes32);

    // Operators
    function authorizeOperator(address _operator) external;
    function revokeOperator(address _operator) external;
    function authorizeOperatorByPartition(bytes32 _partition, address _operator) external;
    function revokeOperatorByPartition(bytes32 _partition, address _operator) external;
    function isOperator(address _operator, address _tokenHolder) external view returns (bool);
    function isOperatorForPartition(bytes32 _partition, address _operator, address _tokenHolder) external view returns (bool);

    // Issuance / Redemption
    function issueByPartition(bytes32 _partition, address _tokenHolder, uint256 _value, bytes calldata _data) external;
    function redeemByPartition(bytes32 _partition, uint256 _value, bytes calldata _data) external;
    function operatorRedeemByPartition(bytes32 _partition, address _tokenHolder, uint256 _value, bytes calldata _operatorData) external;
}
```

### IERC1594 — Core Security Token

```solidity
interface IERC1594 {
    function transferWithData(address _to, uint256 _value, bytes calldata _data) external;
    function transferFromWithData(address _from, address _to, uint256 _value, bytes calldata _data) external;
    function isIssuable() external view returns (bool);
    function issue(address _tokenHolder, uint256 _value, bytes calldata _data) external;
    function redeem(uint256 _value, bytes calldata _data) external;
    function redeemFrom(address _tokenHolder, uint256 _value, bytes calldata _data) external;
    function canTransfer(address _to, uint256 _value, bytes calldata _data) external view returns (bool, byte, bytes32);
    function canTransferFrom(address _from, address _to, uint256 _value, bytes calldata _data) external view returns (bool, byte, bytes32);
}
```

### IERC1643 — Document Management

```solidity
interface IERC1643 {
    function getDocument(bytes32 _name) external view returns (string memory, bytes32, uint256);
    function setDocument(bytes32 _name, string calldata _uri, bytes32 _documentHash) external;
    function removeDocument(bytes32 _name) external;
    function getAllDocuments() external view returns (bytes32[] memory);

    event DocumentUpdated(bytes32 indexed name, string uri, bytes32 documentHash);
    event DocumentRemoved(bytes32 indexed name, string uri, bytes32 documentHash);
}
```

### IERC1644 — Controller Operations

```solidity
interface IERC1644 {
    function isControllable() external view returns (bool);
    function controllerTransfer(address _from, address _to, uint256 _value, bytes calldata _data, bytes calldata _operatorData) external;
    function controllerRedeem(address _tokenHolder, uint256 _value, bytes calldata _data, bytes calldata _operatorData) external;

    event ControllerTransfer(address controller, address indexed from, address indexed to, uint256 value, bytes data, bytes operatorData);
    event ControllerRedemption(address controller, address indexed tokenHolder, uint256 value, bytes data, bytes operatorData);
}
```

---

## Development Environment

### Prerequisites

- **Node.js** >= 18
- **npm** or **yarn**
- **Solidity** ^0.8.20 (via Hardhat)

### Setup

```bash
npm install
```

### Common Commands

```bash
# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test

# Run tests with gas reporting
REPORT_GAS=true npx hardhat test

# Run a specific test file
npx hardhat test test/ERC1400.test.js

# Check test coverage
npx hardhat coverage

# Lint Solidity
npx solhint 'contracts/**/*.sol'

# Format code
npx prettier --write .

# Deploy to a network
npx hardhat run scripts/deploy.js --network <network-name>

# Verify on Etherscan
npx hardhat verify --network <network-name> <contract-address> <constructor-args>
```

---

## Coding Conventions

### Solidity

- **Compiler**: Solidity ^0.8.20 — use built-in overflow checks, no SafeMath needed
- **Style**: Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- **Naming**:
  - Contracts/Interfaces: `PascalCase` (e.g., `ERC1400`, `IERC1410`)
  - Functions/Variables: `camelCase` (e.g., `transferByPartition`, `_tokenHolder`)
  - Constants: `UPPER_SNAKE_CASE` (e.g., `DEFAULT_PARTITION`)
  - Private/internal state variables: prefix with `_` (e.g., `_partitions`)
  - Function parameters: prefix with `_` (e.g., `_to`, `_value`)
- **Interfaces**: Prefix with `I` (e.g., `IERC1410`)
- **Imports**: Use named imports (`import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";`)
- **Visibility**: Always specify visibility explicitly; prefer `external` over `public` for interface-facing functions
- **Events**: Emit events for all state-changing operations
- **Errors**: Use custom errors (`error Unauthorized();`) instead of `require` strings for gas efficiency
- **NatSpec**: Document all public/external functions with `@notice`, `@param`, `@return`

### Testing (JavaScript/TypeScript)

- Use **Hardhat + Chai + Ethers.js** for testing
- Test file naming: `<ContractName>.test.js`
- Structure tests with `describe` blocks per function, `it` blocks per behavior
- Test both success paths and revert conditions
- Use fixtures (`loadFixture`) for deterministic test state

### Security Practices

- **Access control**: Use OpenZeppelin's `Ownable` or `AccessControl` for role management
- **Reentrancy**: Follow checks-effects-interactions pattern; use `ReentrancyGuard` on all hook-calling paths (ERC-1820 hooks introduce external call vectors)
- **Transfer restrictions**: Always enforce compliance checks before executing transfers
- **Controller operations**: Gate behind strict access control — controllers MUST be multisig wallets, never EOAs
- **Partition integrity**: Ensure `balanceOf` always equals the sum of all partition balances for a holder
- **Document hashes**: Validate document hash matches content at URI (off-chain verification)
- **Certificate replay prevention**: Track used nonces and salts per sender to prevent certificate replay attacks
- **Certificate signer rotation**: Certificate signers should rotate keys and use short expiry windows

---

## Architecture Notes

### Partition Model (ERC-1410)

Partitions use `bytes32` keys (e.g., `keccak256("DEFAULT")`, `keccak256("LOCKED")`, `keccak256("VESTING")`). Storage layout:

```solidity
// Core partition storage
bytes32[]                                          internal _totalPartitions;
mapping(bytes32 => uint256)                        internal _indexOfTotalPartitions;    // 1-based
mapping(bytes32 => uint256)                        internal _totalSupplyByPartition;
mapping(address => bytes32[])                      internal _partitionsOf;
mapping(address => mapping(bytes32 => uint256))    internal _indexOfPartitionsOf;       // 1-based
mapping(address => mapping(bytes32 => uint256))    internal _balanceOfByPartition;
bytes32[]                                          internal _defaultPartitions;
```

Key invariant: `balanceOf(holder) == sum of balanceOfByPartition(p, holder) for all p in partitionsOf(holder)`

**Swap-and-pop deletion**: When a partition's balance drops to zero, use the swap-and-pop pattern to remove it from the holder's array (swap with last element, then `pop()`). The 1-based index mapping enables O(1) lookups and deletions.

### Transfer Restriction Flow (ERC-1594)

1. Caller invokes `canTransfer` / `canTransferByPartition` to check validity
2. Returns EIP-1066 status code and a reason `bytes32`
3. `_data` parameter supports off-chain authorization (e.g., signed transfer agent approval)
4. Actual transfer functions enforce the same checks internally

#### ERC-1066 Transfer Status Codes

| Code | Meaning |
|------|---------|
| `0x50` | Transfer failure (generic) |
| `0x51` | Transfer success |
| `0x52` | Insufficient balance |
| `0x53` | Insufficient allowance |
| `0x54` | Transfers halted (contract paused) |
| `0x55` | Funds locked (lockup period) |
| `0x56` | Invalid sender |
| `0x57` | Invalid receiver |
| `0x58` | Invalid operator / transfer agent |
| `0x5f` | Token meta or info |

### Certificate Validation (Off-Chain Compliance)

The `_data` parameter on transfer/issuance/redemption functions carries a compliance certificate — a signed message from a trusted off-chain compliance server. Two modes:

**Nonce-based** (97 bytes appended to `_data`):
- `bytes32 expirationTime` + `uint8 v` + `bytes32 r` + `bytes32 s`
- Contract uses `ecrecover` to validate signer matches a registered `CertificateSignerRole`
- Nonce incremented per sender after use

**Salt-based** (129 bytes):
- `bytes32 salt` + `bytes32 expirationTime` + `uint8 v` + `bytes32 r` + `bytes32 s`
- Salt stored in `_usedCertificateSalt[signer][salt]` to prevent replay

### ERC-1820 Registry Integration

ERC-1400 uses the ERC-1820 pseudo-introspection registry (canonical address on all EVM chains) to:
1. Register the token as implementing `ERC1400Token` and `ERC20Token` interfaces
2. Discover pluggable hook contracts: `ERC1400TokensSender`, `ERC1400TokensRecipient`, `ERC1400TokensValidator`, `ERC1400TokensChecker`
3. Enable upgradeable compliance policies without redeploying the core token

### Controller Model (ERC-1644)

- A designated controller address can force-transfer and force-redeem tokens
- `isControllable()` returns whether the token is currently controllable
- Controller operations emit distinct events for auditability
- Once `isControllable()` returns `false`, this is permanent — controller functions MUST revert
- Controller SHOULD be a multisig (Gnosis Safe), never a raw EOA

### ERC-20 Compatibility

- `transfer`, `transferFrom`, `balanceOf`, `totalSupply`, `approve`, `allowance` all work as expected
- Default partition (set at construction) is used for ERC-20 style transfers
- `Transfer` events are emitted for ERC-20 compatibility alongside partition-specific events
- `decimals` is forced to `18` in the ERC-20 compatibility shim

### Issuance Lifecycle

- `isIssuable()` starts as `true`; once set to `false`, it MUST never return `true` again — issuance is permanently closed
- This is a one-way latch, not a pause/unpause mechanism

### Constructor Pattern

```solidity
constructor(
    string memory name,
    string memory symbol,
    uint256 granularity,         // minimum divisible unit (1 = fully divisible at 18 decimals)
    address[] memory controllers, // use Gnosis Safe addresses in production
    bytes32[] memory defaultPartitions
)
```

---

## Reference Implementations

- [ConsenSys/UniversalToken (ERC1400)](https://github.com/ConsenSys/ERC1400) — Mature reference implementation (Truffle-based)
- [taurushq-io/UniversalTokenERC1400](https://github.com/taurushq-io/UniversalTokenERC1400) — Hardhat-native fork of ConsenSys (Solidity 0.8.7)
- [SecurityTokenStandard/EIP-Spec](https://github.com/SecurityTokenStandard/EIP-Spec) — Original EIP specification documents
- [ethereum/EIPs #1411](https://github.com/ethereum/EIPs/issues/1411) — ERC-1400 proposal discussion

---

## AI Assistant Guidelines

When working on this codebase:

1. **Read before editing** — Always read a file before modifying it. Understand the existing patterns.
2. **Maintain interface compliance** — All implementations must conform to the interfaces defined above. Do not alter function signatures.
3. **Preserve ERC-20 compatibility** — Any changes must not break ERC-20 backwards compatibility.
4. **Test every change** — Write tests for new functionality. Run `npx hardhat test` before considering a task complete.
5. **Security first** — This is a financial contract. Never introduce reentrancy vulnerabilities, unchecked arithmetic in critical paths, or unprotected privileged functions.
6. **Partition invariant** — The sum of all partition balances for a holder must always equal their total `balanceOf`. Any code that modifies balances must maintain this invariant.
7. **Gas awareness** — Partition operations incur extra storage costs (array pushes, nested mappings). Optimize where possible but never at the expense of correctness.
8. **Custom errors over require strings** — Use Solidity custom errors for gas efficiency.
9. **Emit events** — Every state-changing operation must emit an appropriate event.
10. **No secrets in code** — Never commit private keys, mnemonics, or API keys. Use environment variables via `.env` (which must be in `.gitignore`).
