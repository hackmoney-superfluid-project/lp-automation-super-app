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
      url: process.env.ALCHEMY_KEY,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
}