import 'hardhat-typechain'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'
import '@openzeppelin/hardhat-upgrades'

import secrets from './secrets';

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 500000
          }
        }
      },
      {
        version: "0.7.5",
        settings: {
          optimizer: {
            enabled: true,
            runs: 500000
          }
        }
      }
    ]
  },
  networks: {
    goerli: {
      url: secrets.INFURA_GOERLI,
      accounts: secrets.GOERLI_PRIVATE_KEY
        ? [`0x${secrets.GOERLI_PRIVATE_KEY}`] : undefined
    }
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: secrets.ETHERSCAN_API
  }
}
