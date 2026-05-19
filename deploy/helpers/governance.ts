import {getAddress, isAddress, ZeroAddress} from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";

const GOVERNANCE_ENV_KEYS = ["V2_GOVERNANCE_ADDRESS"];
const NODE_OPERATOR_ENV_KEYS = ["V2_NODE_OPERATOR_ADDRESS"];
const OPERATOR_ENV_KEYS = ["V2_OPERATOR_ADDRESS"];
const ORACLE_SUBMITTER_ENV_KEYS = ["V2_ORACLE_SUBMITTERS"];

const readEnv = (keys: string[]): string | undefined => {
  for (const key of keys) {
    const value = process.env[key];
    if (value && value.trim().length > 0) {
      return value.trim();
    }
  }
  return undefined;
};

const assertAddress = (label: string, value: string): string => {
  if (!isAddress(value) || value.toLowerCase() === ZeroAddress.toLowerCase()) {
    throw new Error(`${label} must be a non-zero EVM address. Received: ${value}`);
  }
  return getAddress(value);
};

const parseAddressList = (value: string): string[] => {
  return value
    .split(",")
    .map(v => v.trim())
    .filter(Boolean)
    .map(addr => assertAddress("Oracle submitter address", addr));
};

const uniqueAddresses = (addresses: string[]): string[] => {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const address of addresses) {
    const lower = address.toLowerCase();
    if (seen.has(lower)) continue;
    seen.add(lower);
    out.push(address);
  }
  return out;
};

export const resolveGovernanceAddress = async (hre: HardhatRuntimeEnvironment, ship: Ship): Promise<string> => {
  if (hre.network.tags.hardhat || hre.network.name === "localhost") {
    return (ship.accounts.multiSig ?? ship.accounts.deployer).address;
  }

  const configured = readEnv(GOVERNANCE_ENV_KEYS);
  if (!configured) {
    throw new Error(
      `Missing governance address. Set one of ${GOVERNANCE_ENV_KEYS.join(", ")} when deploying outside hardhat.`,
    );
  }

  return assertAddress("Governance address", configured);
};

export const resolveNodeOperatorAddress = (governance: string): string => {
  const configured = readEnv(NODE_OPERATOR_ENV_KEYS);
  if (!configured) {
    return governance;
  }

  return assertAddress("Node operator address", configured);
};

export const resolveOperatorAddress = (hre: HardhatRuntimeEnvironment, governance: string): string => {
  const configured = readEnv(OPERATOR_ENV_KEYS);
  if (configured) {
    return assertAddress("Operator address", configured);
  }

  if (hre.network.tags.hardhat || hre.network.name === "localhost") {
    return governance;
  }

  throw new Error(
    `Missing operator address. Set one of ${OPERATOR_ENV_KEYS.join(", ")} when deploying outside hardhat.`,
  );
};

export const resolveOracleSubmitterAddresses = (
  hre: HardhatRuntimeEnvironment,
  ship: Ship,
): string[] => {
  const configured = ORACLE_SUBMITTER_ENV_KEYS.flatMap(key => {
    const value = process.env[key];
    if (!value || value.trim().length === 0) return [];
    return parseAddressList(value);
  });

  if (configured.length > 0) {
    return uniqueAddresses(configured);
  }

  if (hre.network.tags.hardhat || hre.network.name === "localhost") {
    return [ship.accounts.deployer.address];
  }

  throw new Error(
    `Missing oracle submitter configuration. Set one of ${ORACLE_SUBMITTER_ENV_KEYS.join(", ")} when deploying outside hardhat.`,
  );
};

// hardhat-deploy recursively loads files under `deploy/`; keep this helper non-executable.
const noop: DeployFunction = async () => {};
noop.skip = async () => true;
export default noop;
