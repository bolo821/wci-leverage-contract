require('dotenv').config();
const { PRIVATE_KEY, PROJECT_ID } = process.env;

const HDWalletProvider = require('@truffle/hdwallet-provider');

module.exports = {
  networks: {
    development: {
     host: "127.0.0.1",     // Localhost (default: none)
     port: 8545,            // Standard Ethereum port (default: none)
     network_id: "*",       // Any network (default: none)
    },
    goerli: {
      provider: () =>
      new HDWalletProvider({
        privateKeys: [PRIVATE_KEY],
        providerOrUrl:
          'https://goerli.infura.io/v3/' + PROJECT_ID,
      }),
      network_id: 5,
      confirmations: 2,
      timeoutBlocks: 400,
      skipDryRun: true,
    },
    main: {
      provider: () =>
      new HDWalletProvider({
        privateKeys: [PRIVATE_KEY],
        providerOrUrl:
          'https://mainnet.infura.io/v3/' + infuraProjectId,
      }),
      network_id: 1,
      confirmations: 2,
      timeoutBlocks: 400,
      skipDryRun: true,
    },
    polygon: {
      provider: () =>
        new HDWalletProvider({
          privateKeys: [PRIVATE_KEY],
          providerOrUrl:
            'https://polygon-mainnet.infura.io/v3/' + infuraProjectId,
        }),
      network_id: 137,
      confirmations: 2,
      timeoutBlocks: 400,
      skipDryRun: true,
      chainId: 137,
    },
  },

  // Set default mocha options here, use special reporters, etc.
  mocha: {
    // timeout: 100000
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.17", // Fetch exact version from solc-bin (default: truffle's version)
      docker: false,        // Use "0.5.1" you've installed locally with docker (default: false)
      settings: {          // See the solidity docs for advice about optimization and evmVersion
       optimizer: {
         enabled: true,
         runs: 200
       },
       evmVersion: "byzantium"
      }
    }
  }
};
