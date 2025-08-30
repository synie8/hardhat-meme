require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  mocha: {
    timeout: 500000,
  },
  networks: {
    hardhat: {
      chainId: 31337
    },
    sepolia: {
      url: SEPOLIA_URL,
      accounts: [PRIVATE_KEY,PRIVATE_KEY_1],
      // http: {
      //   proxy: "http://127.0.0.1:7890" 
      // }
    }
  },
  etherscan: {
      apiKey: ETHERSCAN_API_KEY
  },
  namedAccounts: {
    firstAccount: {
      default: 0
    },
    secondAccount: {
      default: 1
    },
  },
};
