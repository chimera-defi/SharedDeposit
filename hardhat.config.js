require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("@nomiclabs/hardhat-etherscan");

require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-gas-reporter");
require("hardhat-contract-sizer");
require("hardhat-abi-exporter");
require('solidity-coverage')

require("dotenv").config();

// Environment sourced variables
const GOERLIPK = process.env.GOERLIPK
  ? process.env.GOERLIPK
  : "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"; // default pk 0 from anvil

const ALCHEMY_GOERLI_KEY = process.env.ALCHEMY_GOERLI_KEY
  ? process.env.ALCHEMY_GOERLI_KEY
  : console.log("Please export a ALCHEMY_GOERLI_KEY for alchemy api access");
const GOERLI_RPC_URL = `https://eth-goerli.g.alchemy.com/v2/${ALCHEMY_GOERLI_KEY}`;

const ALCHEMY_KEY = process.env.ALCHEMY_KEY ? process.env.ALCHEMY_KEY : ALCHEMY_GOERLI_KEY;
const MAINNET_RPC_URL = `https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`;

const MAINNET_PRIVATE_KEY = process.env.MAINNET_PRIVATE_KEY ? process.env.MAINNET_PRIVATE_KEY : GOERLIPK;

// Your API key for Etherscan
// Obtain one at https://etherscan.io/
// apiKey: secrets.ETHERSCAN_API,
const ETHERSCAN_API = process.env.ETHERSCAN_API ? process.env.ETHERSCAN_API : false;

// END required user input

const path = require("path");

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
let maxRunsOnEtherscan = 1000000;
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
// final exported hardhat config
config = {
  solidity: {
    compilers: [
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.7.5",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {},
    goerli: {
      url: GOERLI_RPC_URL,
      accounts: [`0x${GOERLIPK}`],
      chainId: chainIds.goerli,
      initialBaseFeePerGas: 1000000000,
    },
    localhost: {
      accounts: [`0x${GOERLIPK}`],
    },
    mainnet: {
      url: MAINNET_RPC_URL,
      accounts: [`0x${MAINNET_PRIVATE_KEY}`],
      chainId: chainIds.mainnet,
    },
  },
  gasReporter: {
    currency: "USD",
    gasPrice: 50,
    enabled: true,
    src: "./contracts",
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  abiExporter: {
    path: "./data/abi",
    clear: true,
    flat: true,
    only: [],
    spacing: 2,
  },
};

if (ETHERSCAN_API) {
  config["etherscan"] = {
    apiKey: {
      mainnet: ETHERSCAN_API,
      goerli: ETHERSCAN_API,
    },
    customChains: [],
  };
}

// imported from https://github.com/boringcrypto/dictator-dao/blob/main/hardhat.config.js

// module.exports = require("@boringcrypto/hardhat-framework").config.hardhat({})
const fs = require("fs");

function getSortedFiles(dependenciesGraph) {
  const tsort = require("tsort");
  const graph = tsort();

  const filesMap = {};
  const resolvedFiles = dependenciesGraph.getResolvedFiles();
  resolvedFiles.forEach(f => (filesMap[f.sourceName] = f));

  for (const [from, deps] of dependenciesGraph.entries()) {
    for (const to of deps) {
      graph.add(to.sourceName, from.sourceName);
    }
  }

  const topologicalSortedNames = graph.sort();

  // If an entry has no dependency it won't be included in the graph, so we
  // add them and then dedup the array
  const withEntries = topologicalSortedNames.concat(resolvedFiles.map(f => f.sourceName));

  const sortedNames = [...new Set(withEntries)];
  return sortedNames.map(n => filesMap[n]);
}

function getFileWithoutImports(resolvedFile) {
  const IMPORT_SOLIDITY_REGEX = /^\s*import(\s+)[\s\S]*?;\s*$/gm;

  return resolvedFile.content.rawContent.replace(IMPORT_SOLIDITY_REGEX, "").trim();
}

subtask("flat:get-flattened-sources", "Returns all contracts and their dependencies flattened")
  .addOptionalParam("files", undefined, undefined, types.any)
  .addOptionalParam("output", undefined, undefined, types.string)
  .setAction(async ({files, output}, {run}) => {
    const dependencyGraph = await run("flat:get-dependency-graph", {files});
    console.log(dependencyGraph);

    let flattened = "";

    if (dependencyGraph.getResolvedFiles().length === 0) {
      return flattened;
    }

    const sortedFiles = getSortedFiles(dependencyGraph);

    let isFirst = true;
    for (const file of sortedFiles) {
      if (!isFirst) {
        flattened += "\n";
      }
      flattened += `// File ${file.getVersionedName()}\n`;
      flattened += `${getFileWithoutImports(file)}\n`;

      isFirst = false;
    }

    // Remove every line started with "// SPDX-License-Identifier:"
    flattened = flattened.replace(/SPDX-License-Identifier:/gm, "License-Identifier:");

    flattened = `// SPDX-License-Identifier: MIXED\n\n${flattened}`;

    // Remove every line started with "pragma experimental ABIEncoderV2;" except the first one
    flattened = flattened.replace(/pragma experimental ABIEncoderV2;\n/gm, (i => m => (!i++ ? m : ""))(0));

    flattened = flattened.trim();
    if (output) {
      console.log("Writing to", output);
      fs.writeFileSync(output, flattened);
      return "";
    }
    return flattened;
  });

subtask("flat:get-dependency-graph")
  .addOptionalParam("files", undefined, undefined, types.any)
  .setAction(async ({files}, {run}) => {
    const sourcePaths =
      files === undefined ? await run("compile:solidity:get-source-paths") : files.map(f => fs.realpathSync(f));

    const sourceNames = await run("compile:solidity:get-source-names", {
      sourcePaths,
    });

    const dependencyGraph = await run("compile:solidity:get-dependency-graph", {sourceNames});

    return dependencyGraph;
  });

task("flat", "Flattens and prints contracts and their dependencies")
  .addOptionalVariadicPositionalParam("files", "The files to flatten", undefined, types.inputFile)
  .addOptionalParam("output", "Specify the output file", undefined, types.string)
  .setAction(async ({files, output}, {run}) => {
    console.log(files, output);
    console.log(
      await run("flat:get-flattened-sources", {
        files,
        output,
      }),
    );
  });

task("flattenAll", "Flatten all files we care about").setAction(async ({}, {run}) => {
  let srcpath = "contracts";
  let files = fs.readdirSync(srcpath).map(file => `${srcpath}/${file}`);
  srcpath = `${srcpath}/governance`;
  files = files.concat(fs.readdirSync(srcpath).map(file => `${srcpath}/${file}`));

  try {
    fs.mkdirSync("flats/contracts/governance", {recursive: true});
  } catch (e) {}

  await Promise.all(
    files.map(async file => {
      if (path.extname(file) == ".sol") {
        await run("flat:get-flattened-sources", {
          files: [file],
          output: `./flats/${file}`,
        });
      }
    }),
  );
});

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

module.exports = config;
