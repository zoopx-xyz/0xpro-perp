import "@nomicfoundation/hardhat-toolbox";
import "@kadena/hardhat-chainweb";
import "dotenv/config";
import { HardhatUserConfig } from "hardhat/config";

const DEPLOYER_PRIVATE_KEY = process.env.DEPLOYER_PRIVATE_KEY || process.env.RELAYER_PRIVATE_KEY || "";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true
    }
  },
  defaultNetwork: "hardhat",
  defaultChainweb: "testnet",
  chainweb: {
    hardhat: { chains: 2 },
    testnet: {
      type: "external",
      // IMPORTANT: "chains" is the number of chains created for this Chainweb config,
      // not the chain number. We set it to 1 to create a single target chain, and use the
      // offsets below to make that single chain be Chainweb chain number 20 (EVM chainId 5920).
      chains: 1,
      accounts: DEPLOYER_PRIVATE_KEY ? [DEPLOYER_PRIVATE_KEY] : undefined,
      chainIdOffset: 5920,
      chainwebChainIdOffset: 20,
      externalHostUrl: "https://evm-testnet.chainweb.com/chainweb/0.0/evm-testnet",
      etherscan: {
        apiKey: "abc", // Any non-empty string works for Blockscout
        apiURLTemplate: "http://chain-{cid}.evm-testnet-blockscout.chainweb.com/api/",
        browserURLTemplate: "http://chain-{cid}.evm-testnet-blockscout.chainweb.com"
      }
    }
  },
  networks: {
    kadena_chain20: {
      url: "https://evm-testnet.chainweb.com/chainweb/0.0/evm-testnet/chain/20/evm/rpc",
      chainId: 5920,
      accounts: DEPLOYER_PRIVATE_KEY ? [DEPLOYER_PRIVATE_KEY] : []
    }
  },
  etherscan: {
    apiKey: {
      kadena_chain20: "abc"
    },
    customChains: [
      {
        network: "kadena_chain20",
        chainId: 5920,
        urls: {
          apiURL: "http://chain-20.evm-testnet-blockscout.chainweb.com/api",
          browserURL: "http://chain-20.evm-testnet-blockscout.chainweb.com"
        }
      }
    ]
  },
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  }
};

export default config;
