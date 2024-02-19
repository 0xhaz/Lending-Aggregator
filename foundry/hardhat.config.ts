import "@nomicfoundation/hardhat-toolbox";
import "@tenderly/hardhat-tenderly";
import "hardhat-abi-exporter";
import "hardhat-preprocessor";
import "hardhat-deploy";

import * as fs from "fs";
import { HardhatUserConfig } from "hardhat/config";

const deployerPath = "./deployer.json";

/**
 * Tasks
 */
import { mnemonic } from "./hardhat-tasks/getWallet";}

/**
 * Configuration
 */
const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.15",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      }
    ]
  },
  networks: {
    localhost: {
      live: false,
      saveDeployments: true,
      deploy: [`deploy/networks/${getTestDeployNetwork()}`]
    }
  }
};

export default config;
