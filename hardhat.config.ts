import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition-ethers";
import "@openzeppelin/hardhat-upgrades";
import "dotenv/config";

// Load environment variables
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000001";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const POLYGONSCAN_API_KEY = process.env.POLYGONSCAN_API_KEY || "";
const ARBISCAN_API_KEY = process.env.ARBISCAN_API_KEY || "";
const OPTIMISM_API_KEY = process.env.OPTIMISM_API_KEY || "";
const BASESCAN_API_KEY = process.env.BASESCAN_API_KEY || "";
const SNOWTRACE_API_KEY = process.env.SNOWTRACE_API_KEY || "";
const BSCSCAN_API_KEY = process.env.BSCSCAN_API_KEY || "";

// RPC URLs
const MAINNET_RPC_URL = process.env.MAINNET_RPC_URL || "https://eth.llamarpc.com";
const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org";
const GOERLI_RPC_URL = process.env.GOERLI_RPC_URL || "https://rpc.ankr.com/eth_goerli";
const POLYGON_RPC_URL = process.env.POLYGON_RPC_URL || "https://polygon-rpc.com";
const MUMBAI_RPC_URL = process.env.MUMBAI_RPC_URL || "https://rpc-mumbai.maticvigil.com";
const ARBITRUM_RPC_URL = process.env.ARBITRUM_RPC_URL || "https://arb1.arbitrum.io/rpc";
const ARBITRUM_SEPOLIA_RPC_URL = process.env.ARBITRUM_SEPOLIA_RPC_URL || "https://sepolia-rollup.arbitrum.io/rpc";
const OPTIMISM_RPC_URL = process.env.OPTIMISM_RPC_URL || "https://mainnet.optimism.io";
const BASE_RPC_URL = process.env.BASE_RPC_URL || "https://mainnet.base.org";
const BASE_SEPOLIA_RPC_URL = process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org";
const AVALANCHE_RPC_URL = process.env.AVALANCHE_RPC_URL || "https://api.avax.network/ext/bc/C/rpc";
const BSC_RPC_URL = process.env.BSC_RPC_URL || "https://bsc-dataseed.binance.org";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
      evmVersion: "paris",
    },
  },

  networks: {
    // Local Development
    hardhat: {
      chainId: 31337,
      allowUnlimitedContractSize: true,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },

    // Ethereum
    mainnet: {
      url: MAINNET_RPC_URL,
      chainId: 1,
      accounts: [PRIVATE_KEY],
      gasPrice: "auto",
    },
    sepolia: {
      url: SEPOLIA_RPC_URL,
      chainId: 11155111,
      accounts: [PRIVATE_KEY],
    },
    goerli: {
      url: GOERLI_RPC_URL,
      chainId: 5,
      accounts: [PRIVATE_KEY],
    },

    // Polygon
    polygon: {
      url: POLYGON_RPC_URL,
      chainId: 137,
      accounts: [PRIVATE_KEY],
      gasPrice: "auto",
    },
    mumbai: {
      url: MUMBAI_RPC_URL,
      chainId: 80001,
      accounts: [PRIVATE_KEY],
    },

    // Arbitrum
    arbitrum: {
      url: ARBITRUM_RPC_URL,
      chainId: 42161,
      accounts: [PRIVATE_KEY],
    },
    arbitrumSepolia: {
      url: ARBITRUM_SEPOLIA_RPC_URL,
      chainId: 421614,
      accounts: [PRIVATE_KEY],
    },

    // Optimism
    optimism: {
      url: OPTIMISM_RPC_URL,
      chainId: 10,
      accounts: [PRIVATE_KEY],
    },

    // Base
    base: {
      url: BASE_RPC_URL,
      chainId: 8453,
      accounts: [PRIVATE_KEY],
    },
    baseSepolia: {
      url: BASE_SEPOLIA_RPC_URL,
      chainId: 84532,
      accounts: [PRIVATE_KEY],
    },

    // Avalanche
    avalanche: {
      url: AVALANCHE_RPC_URL,
      chainId: 43114,
      accounts: [PRIVATE_KEY],
    },

    // BNB Smart Chain
    bsc: {
      url: BSC_RPC_URL,
      chainId: 56,
      accounts: [PRIVATE_KEY],
    },
  },

  etherscan: {
    apiKey: {
      // Ethereum
      mainnet: ETHERSCAN_API_KEY,
      sepolia: ETHERSCAN_API_KEY,
      goerli: ETHERSCAN_API_KEY,
      // Polygon
      polygon: POLYGONSCAN_API_KEY,
      polygonMumbai: POLYGONSCAN_API_KEY,
      // Arbitrum
      arbitrumOne: ARBISCAN_API_KEY,
      arbitrumSepolia: ARBISCAN_API_KEY,
      // Optimism
      optimisticEthereum: OPTIMISM_API_KEY,
      // Base
      base: BASESCAN_API_KEY,
      baseSepolia: BASESCAN_API_KEY,
      // Avalanche
      avalanche: SNOWTRACE_API_KEY,
      // BSC
      bsc: BSCSCAN_API_KEY,
    },
    customChains: [
      {
        network: "baseSepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org",
        },
      },
      {
        network: "arbitrumSepolia",
        chainId: 421614,
        urls: {
          apiURL: "https://api-sepolia.arbiscan.io/api",
          browserURL: "https://sepolia.arbiscan.io",
        },
      },
    ],
  },

  sourcify: {
    enabled: true,
  },

  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    outputFile: "gas-report.txt",
    noColors: true,
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },

  mocha: {
    timeout: 200000,
  },
};

export default config;
