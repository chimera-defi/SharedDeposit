import {isAddress, ZeroAddress} from "ethers";
import {HardhatRuntimeEnvironment} from "hardhat/types";
import Ship from "../../utils/ship";

const GOVERNANCE_ENV_KEYS = ["V2_GOVERNANCE_ADDRESS", "GOVERNANCE_ADDRESS"];
const NODE_OPERATOR_ENV_KEYS = ["V2_NODE_OPERATOR_ADDRESS", "NODE_OPERATOR_ADDRESS"];

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
  return value;
};

export const resolveGovernanceAddress = async (hre: HardhatRuntimeEnvironment, ship: Ship): Promise<string> => {
  if (hre.network.tags.hardhat) {
    return ship.accounts.multiSig.address;
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
