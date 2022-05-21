require("@nomiclabs/hardhat-waffle");
require("dotenv").config();

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 module.exports = {
  solidity: {
    version: '0.7.6',
    settings: {
      optimizer: {
        runs: 200,
        enabled: true
      }
    }
  },
  networks: {
    mumbai: {
      url: process.env.MUMBAI_ALCHEMY_KEY,
      accounts: [process.env.PRIVATE_KEY],
    },
    rinkeby: {
      url: process.env.RINKEBY_ALCHEMY_KEY,
      accounts: [process.env.PRIVATE_KEY],
    },
    "optimism-kovan": {
      url: "https://kovan.optimism.io",
      accounts: [process.env.PRIVATE_KEY],
    },
  },
}