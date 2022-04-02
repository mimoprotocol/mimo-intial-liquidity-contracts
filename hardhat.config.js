require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();
require("hardhat-abi-exporter");
require("hardhat-contract-sizer");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("solidity-coverage");

module.exports = {
  solidity: "0.8.6",
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_PROJECT_ID || ""}`,
        blockNumber: 14237619
      }
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${
        process.env.ALCHEMY_PROJECT_ID || ""
      }`,
      accounts: process.env.DEPLOY_PRIVATE_KEY
        ? [process.env.DEPLOY_PRIVATE_KEY]
        : [],
      gas: 2100000,
      gasPrice: 8000000000,
      saveDeployments: true,
    },
    iotex_test: {
        url: 'https://babel-api.testnet.iotex.io',
        accounts: [`0x${process.env.DEPLOY_PRIVATE_KEY}`],
        chainId: 4690,
    }
  },
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
  contractSizer: {
    strict: true,
  },
  namedAccounts: {
    deployer: 0,
    dev: 1,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};
