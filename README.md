# ERC-1400 Security Token

A comprehensive implementation of the ERC-1400 security token standard with UUPS upgradeability, multiple deployment options, and extensive test coverage.

## Features

- **ERC-1400 Compliant**: Full implementation of the security token standard
- **ERC-20 Compatible**: Works with existing DeFi protocols and wallets
- **Partition Support**: Token partitions for different share classes/tranches
- **Operator Management**: Global and partition-level operator authorization
- **Controller Functions**: Forced transfers and redemptions for regulatory compliance
- **Document Management**: On-chain document registry (prospectus, whitepaper, etc.)
- **Whitelist Validation**: KYC/AML compliance through transfer validation
- **UUPS Upgradeable**: Secure upgrade pattern for future improvements
- **Factory Pattern**: Deploy multiple tokens from a single factory
- **CREATE2 Deterministic**: Predictable contract addresses across networks

## Project Structure

```
├── contracts/
│   ├── ERC1400.sol              # Core token implementation
│   ├── ERC1400Whitelist.sol     # Whitelist validator
│   ├── ERC1400Factory.sol       # Factory for deploying tokens
│   └── interfaces/
│       ├── IERC1400.sol         # Main interface
│       ├── IERC1400TokensValidator.sol
│       └── IERC1400TokensChecker.sol
├── ignition/modules/            # Hardhat Ignition deployment modules
├── script/                      # Foundry deployment scripts
├── test/
│   ├── ERC1400.test.ts         # Hardhat tests
│   ├── ERC1400Whitelist.test.ts
│   ├── ERC1400Factory.test.ts
│   └── foundry/                # Foundry tests
└── ...config files
```

## Quick Start

### Prerequisites

- Node.js >= 18
- npm or yarn
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (optional)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd ERC--1400

# Install dependencies
npm install

# Copy environment file
cp .env.example .env
# Edit .env with your configuration
```

### Compile

```bash
# Hardhat
npm run compile

# Foundry
forge build
```

### Test

```bash
# Hardhat tests
npm run test

# With coverage
npm run test:coverage

# With gas reporting
npm run test:gas

# Foundry tests
forge test

# Foundry with verbosity
forge test -vvv
```

## Deployment Options

### 1. Local Development

```bash
# Start local node
npm run node

# Deploy to localhost
npm run deploy:local
```

### 2. Testnet Deployment

```bash
# Sepolia
npm run deploy:sepolia

# Mumbai (Polygon testnet)
npm run deploy:mumbai

# Arbitrum Sepolia
npx hardhat ignition deploy ignition/modules/ERC1400Module.ts --network arbitrumSepolia
```

### 3. Mainnet Deployment

```bash
# Ethereum Mainnet
npm run deploy:mainnet

# Polygon
npm run deploy:polygon

# Arbitrum One
npm run deploy:arbitrum

# Base
npm run deploy:base

# Optimism
npm run deploy:optimism
```

### 4. Foundry Deployment

```bash
# Deploy to Sepolia
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify

# Deploy factory only
forge script script/Deploy.s.sol:DeployFactoryOnly --rpc-url sepolia --broadcast

# Deploy via existing factory
FACTORY_ADDRESS=0x... forge script script/Deploy.s.sol:DeployTokenViaFactory --rpc-url sepolia --broadcast

# Deterministic deployment
FACTORY_ADDRESS=0x... DEPLOYMENT_SALT=0x... forge script script/Deploy.s.sol:DeployDeterministic --rpc-url sepolia --broadcast
```

## Supported Networks

| Network | Chain ID | Type |
|---------|----------|------|
| Ethereum Mainnet | 1 | Production |
| Sepolia | 11155111 | Testnet |
| Polygon | 137 | Production |
| Mumbai | 80001 | Testnet |
| Arbitrum One | 42161 | Production |
| Arbitrum Sepolia | 421614 | Testnet |
| Optimism | 10 | Production |
| Base | 8453 | Production |
| Base Sepolia | 84532 | Testnet |
| Avalanche | 43114 | Production |
| BSC | 56 | Production |

## Contract Verification

After deployment, verify your contracts:

```bash
# Hardhat
npx hardhat verify --network <network> <contract-address> <constructor-args>

# Foundry (automatic with --verify flag)
forge script script/Deploy.s.sol --rpc-url <network> --broadcast --verify
```

## Usage Examples

### Deploy a Token via Factory

```solidity
// Get factory instance
ERC1400Factory factory = ERC1400Factory(factoryAddress);

// Configure token
string memory name = "Security Token";
string memory symbol = "SEC";
uint256 granularity = 1;
address[] memory controllers = new address[](1);
controllers[0] = msg.sender;
bytes32[] memory partitions = new bytes32[](1);
partitions[0] = bytes32(0);

// Deploy
address token = factory.deployToken(name, symbol, granularity, controllers, partitions);
```

### Issue Tokens

```solidity
ERC1400 token = ERC1400(tokenAddress);

// Issue to default partition
token.issue(recipient, amount, "");

// Issue to specific partition
bytes32 partition = keccak256("SERIES_A");
token.issueByPartition(partition, recipient, amount, "");
```

### Transfer with Partitions

```solidity
// Standard ERC-20 transfer (uses default partition)
token.transfer(recipient, amount);

// Partition-specific transfer
token.transferByPartition(partition, recipient, amount, "");
```

### Setup Whitelist Validation

```solidity
// Deploy whitelist
address validator = factory.deployWhitelistValidator(true);

// Connect to token
token.setTokenValidator(validator);

// Add addresses to whitelist
ERC1400Whitelist whitelist = ERC1400Whitelist(validator);
whitelist.addToWhitelist(address1);
whitelist.batchAddToWhitelist([address2, address3, address4]);
```

## Security Considerations

1. **Multisig Admin**: Use Gnosis Safe for owner/admin functions
2. **Timelock**: Add timelock for sensitive operations
3. **Audit**: Get professional audit before mainnet deployment
4. **Upgrades**: Test upgrades thoroughly on testnet first
5. **Controllers**: Carefully manage controller addresses
6. **Whitelist**: Implement proper KYC/AML processes

## Gas Optimization

Run gas reports:

```bash
REPORT_GAS=true npm run test
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Resources

- [ERC-1400 Standard](https://github.com/ethereum/EIPs/issues/1411)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)
- [Hardhat Documentation](https://hardhat.org/docs)
- [Foundry Book](https://book.getfoundry.sh/)
