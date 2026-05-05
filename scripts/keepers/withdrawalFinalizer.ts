/**
 * withdrawalFinalizer — keeper that finalizes pending withdrawal-queue requests.
 *
 * Polls WithdrawalQueueV2 for the open range [lastFinalizedRequestId+1,
 * nextRequestId-1], sums the ethAmount required, and submits `finalize()` with
 * the matching ETH from the GUARDIAN wallet. Returns excess ETH automatically
 * (the queue refunds anything beyond the required total).
 *
 * Usage:
 *   npx ts-node scripts/keepers/withdrawalFinalizer.ts
 *   npx ts-node scripts/keepers/withdrawalFinalizer.ts --dry-run
 *   npx ts-node scripts/keepers/withdrawalFinalizer.ts --watch [--interval=120]
 *
 * Required env vars:
 *   RPC_URL                JSON-RPC endpoint
 *   QUEUE_ADDRESS          WithdrawalQueueV2 deployment address
 *   GUARDIAN_PRIVATE_KEY   Private key of GUARDIAN role-holder
 *
 * Optional env vars:
 *   MAX_BATCH_SIZE         Largest batch to finalize per call (default 50)
 *   MIN_BATCH_SIZE         Minimum number of pending requests required to act (default 1)
 *   MAX_RETRIES            Default 5
 *   BACKOFF_MS             Default 5000 (doubled on each retry)
 */
import {ethers} from "ethers";

const QUEUE_ABI = [
  "function nextRequestId() view returns (uint256)",
  "function lastFinalizedRequestId() view returns (uint256)",
  "function getRequest(uint256) view returns (tuple(address owner, uint256 stShares, uint256 ethAmount, bool finalized, bool claimed))",
  "function finalize(uint256 lastRequestId) payable",
];

interface Config {
  rpcUrl: string;
  queueAddress: string;
  privateKey: string;
  dryRun: boolean;
  watch: boolean;
  intervalSec: number;
  maxBatchSize: number;
  minBatchSize: number;
  maxRetries: number;
  initialBackoffMs: number;
}

function loadConfig(): Config {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const watch = args.includes("--watch");
  const intervalArg = args.find(a => a.startsWith("--interval="));
  const intervalSec = intervalArg ? parseInt(intervalArg.split("=")[1], 10) : 120;

  const required = (name: string): string => {
    const v = process.env[name];
    if (!v) throw new Error(`Missing required env var ${name}`);
    return v;
  };

  return {
    rpcUrl: required("RPC_URL"),
    queueAddress: required("QUEUE_ADDRESS"),
    privateKey: required("GUARDIAN_PRIVATE_KEY"),
    dryRun,
    watch,
    intervalSec,
    maxBatchSize: parseInt(process.env.MAX_BATCH_SIZE ?? "50", 10),
    minBatchSize: parseInt(process.env.MIN_BATCH_SIZE ?? "1", 10),
    maxRetries: parseInt(process.env.MAX_RETRIES ?? "5", 10),
    initialBackoffMs: parseInt(process.env.BACKOFF_MS ?? "5000", 10),
  };
}

async function sleep(ms: number) {
  return new Promise(r => setTimeout(r, ms));
}

async function finalizeOnce(cfg: Config) {
  const provider = new ethers.JsonRpcProvider(cfg.rpcUrl);
  const wallet = new ethers.Wallet(cfg.privateKey, provider);
  const queue = new ethers.Contract(cfg.queueAddress, QUEUE_ABI, wallet);

  const lastFinalized: bigint = await queue.lastFinalizedRequestId();
  const next: bigint = await queue.nextRequestId();

  const fromId = lastFinalized + 1n;
  const lastId = next - 1n;
  if (lastId < fromId) {
    console.log(`[finalize] queue empty (next=${next}, lastFinalized=${lastFinalized})`);
    return;
  }

  const pending = lastId - fromId + 1n;
  if (pending < BigInt(cfg.minBatchSize)) {
    console.log(`[finalize] only ${pending} pending (< MIN_BATCH_SIZE=${cfg.minBatchSize}); skipping`);
    return;
  }

  const batchEnd = fromId + BigInt(Math.min(cfg.maxBatchSize, Number(pending))) - 1n;
  console.log(`[finalize] finalizing requests [${fromId}, ${batchEnd}]`);

  let totalEth = 0n;
  for (let id = fromId; id <= batchEnd; id += 1n) {
    const req = await queue.getRequest(id);
    if (req.finalized) {
      console.warn(`[finalize] request ${id} already finalized; skipping`);
      continue;
    }
    totalEth += req.ethAmount;
  }
  console.log(`[finalize] total ETH required: ${ethers.formatEther(totalEth)}`);

  const balance: bigint = await provider.getBalance(wallet.address);
  if (balance < totalEth) {
    throw new Error(
      `[finalize] guardian balance ${ethers.formatEther(balance)} ETH < required ${ethers.formatEther(totalEth)} ETH`
    );
  }

  if (cfg.dryRun) {
    console.log(`[finalize] --dry-run: would finalize(${batchEnd}) with ${ethers.formatEther(totalEth)} ETH`);
    return;
  }

  let attempt = 0;
  let backoff = cfg.initialBackoffMs;
  while (attempt < cfg.maxRetries) {
    try {
      const tx = await queue.finalize(batchEnd, {value: totalEth});
      console.log(`[finalize] tx submitted: ${tx.hash}`);
      const rcpt = await tx.wait();
      console.log(`[finalize] confirmed in block ${rcpt?.blockNumber}`);
      return;
    } catch (err) {
      attempt += 1;
      console.error(`[finalize] attempt ${attempt} failed:`, (err as Error).message);
      if (attempt >= cfg.maxRetries) throw err;
      await sleep(backoff);
      backoff *= 2;
    }
  }
}

async function main() {
  const cfg = loadConfig();

  if (!cfg.watch) {
    await finalizeOnce(cfg);
    return;
  }

  console.log(`[finalize] watch mode (poll every ${cfg.intervalSec}s)`);
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      await finalizeOnce(cfg);
    } catch (err) {
      console.error("[finalize] cycle error:", (err as Error).message);
    }
    await sleep(cfg.intervalSec * 1000);
  }
}

main().catch(err => {
  console.error("[finalize] fatal:", err);
  process.exit(1);
});
