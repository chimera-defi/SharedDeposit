import {HardhatRuntimeEnvironment} from "hardhat/types";
import Ship from "../../utils/ship";
import {MockBeaconDeposit__factory, StakingRouter} from "../../types";
import {makeEth1WithdrawalCredentials} from "./withdrawalCredentials";

export function readMintCapWei(
  hre: HardhatRuntimeEnvironment,
  envKeys: string[],
  isLocal: boolean,
  label: string,
): bigint {
  let value: string | undefined;
  for (const key of envKeys) {
    const v = process.env[key];
    if (!v || v.trim().length === 0) continue;
    value = v.trim();
    break;
  }
  if (!value && !isLocal) {
    throw new Error(
      `Missing ${label} mint cap. Set one of ${envKeys.join(", ")} for non-local deployments.`,
    );
  }
  return value ? hre.ethers.parseEther(value) : 0n;
}

export async function resolveBeaconDeposit(hre: HardhatRuntimeEnvironment, ship: Ship): Promise<string> {
  const networkName = hre.network.name;

  switch (networkName) {
    case "mainnet":
    case "hoodi":
      return "0x00000000219ab540356cBB839Cbe05303d7705Fa";
    case "holesky":
      return "0x4242424242424242424242424242424242424242";
    default: {
      const {contract: mockBeacon} = await ship.deploy(MockBeaconDeposit__factory, {
        aliasName: "MockBeaconDepositV2",
        from: ship.accounts.deployer,
        log: true,
      });
      return mockBeacon.target as string;
    }
  }
}

export function getGovernanceSigner(ship: Ship): any {
  return ship.accounts.multiSig ?? ship.accounts.deployer;
}

export function assertGovernanceSigner(ship: Ship, gov: string): void {
  const govSigner = getGovernanceSigner(ship);
  if (govSigner.address.toLowerCase() !== gov.toLowerCase()) {
    throw new Error(
      `Governance signer mismatch: signer=${govSigner.address} resolvedGov=${gov}. ` +
        "Set governance env/config so the current GOV signer executes module wiring.",
    );
  }
}

export async function grantNodeOperatorRole(
  module: {NODE_OPERATOR(): Promise<string>; hasRole(role: string, account: string): Promise<boolean>; connect(signer: any): any},
  govSigner: any,
  nodeOperator: string,
  logLabel: string,
): Promise<void> {
  const NODE_OPERATOR = await module.NODE_OPERATOR();
  if (!(await module.hasRole(NODE_OPERATOR, nodeOperator))) {
    console.log(`  Granting NODE_OPERATOR to ${nodeOperator} on ${logLabel}...`);
    await module.connect(govSigner).grantRole(NODE_OPERATOR, nodeOperator);
  }
}

export async function allowlistModuleCodeHash(
  router: StakingRouter,
  moduleType: bigint,
  moduleCodeHash: string,
  govSigner: any,
  logLabel: string,
): Promise<void> {
  if (!(await router.moduleCodeHashAllowed(moduleType, moduleCodeHash))) {
    console.log(`  Allowlisting ${logLabel} code hash (${moduleCodeHash})...`);
    await router.connect(govSigner).setModuleCodeHashAllowed(moduleType, moduleCodeHash, true);
  }
}

export async function enableCodeHashAllowlistEnforcement(
  router: StakingRouter,
  govSigner: any,
): Promise<void> {
  if (!(await router.enforceModuleCodeHashAllowlist())) {
    console.log("  Enabling module code-hash allowlist enforcement...");
    await router.connect(govSigner).setEnforceModuleCodeHashAllowlist(true);
  }
}

export async function registerOrUpdateModule(
  router: StakingRouter,
  govSigner: any,
  moduleId: string,
  moduleAddress: string,
  mintCapWei: bigint,
  logLabel: string,
  options?: {setDefault?: boolean; verify?: boolean},
): Promise<void> {
  const existing = await router.modules(moduleId);
  if (existing.addr === "0x0000000000000000000000000000000000000000") {
    console.log(`  Registering ${logLabel} (${moduleId}) with router (cap=${mintCapWei})...`);
    await router.connect(govSigner).registerModule(moduleId, moduleAddress, mintCapWei);
    if (options?.setDefault) {
      console.log("  Setting as default module...");
      await router.connect(govSigner).setDefaultModule(moduleId);
    }
    if (options?.verify) {
      const registered = await router.modules(moduleId);
      if (registered.addr.toLowerCase() !== moduleAddress.toLowerCase()) {
        throw new Error(`${logLabel} registration verification failed: on-chain addr=${registered.addr}`);
      }
      console.log("  Registration verified.");
    }
  } else if (existing.mintCapEth !== mintCapWei) {
    console.log(`  Updating ${logLabel} mint cap to ${mintCapWei}...`);
    await router.connect(govSigner).setMintCap(moduleId, mintCapWei);
  }
}

export async function wireWithdrawalCredentials(
  module: {expectedWithdrawalCredentials(): Promise<string>; connect(signer: any): any},
  govSigner: any,
  withdrawalQueueAddress: string,
): Promise<void> {
  const expectedCreds = makeEth1WithdrawalCredentials(withdrawalQueueAddress);
  if ((await module.expectedWithdrawalCredentials()).toLowerCase() !== expectedCreds.toLowerCase()) {
    console.log(`  Setting expected withdrawal credentials (${expectedCreds})...`);
    await module.connect(govSigner).setExpectedWithdrawalCredentials(expectedCreds);
  }
}
