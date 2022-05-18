require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("dotenv").config();

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.13"
      },
      {
        version: "0.7.6"
      }
    ]
  },
  networks: {
    mumbai: {
      url: process.env.ALCHEMY_KEY,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};

