import {getAddress} from "ethers";

const ETH1_WITHDRAWAL_PREFIX = "0x010000000000000000000000";

export const makeEth1WithdrawalCredentials = (withdrawalAddress: string): string => {
  const normalized = getAddress(withdrawalAddress);
  return `${ETH1_WITHDRAWAL_PREFIX}${normalized.slice(2).toLowerCase()}`;
};
