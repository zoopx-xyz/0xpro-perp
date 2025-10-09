// Simple log watcher example for OrderFilled events using viem (preferred) or ethers fallback.
// Run with: node scripts/log_watch_example.js <RPC_URL> <ENGINE_ADDRESS>
// Outputs normalized JSON for frontend ingestion.

import { createPublicClient, http, parseAbiItem } from 'viem';
import { getAddress } from 'viem';

async function main() {
  const [,, rpcUrlArg, engineArg] = process.argv;
  if (!rpcUrlArg || !engineArg) {
    console.error('Usage: node scripts/log_watch_example.js <RPC_URL> <ENGINE_ADDRESS>');
    process.exit(1);
  }
  const rpcUrl = rpcUrlArg;
  const engine = getAddress(engineArg);

  const abiOrderFilled = parseAbiItem('event OrderFilled(address indexed account, bytes32 indexed marketId, bytes32 indexed fillId, bool isBuy, uint128 size, uint128 priceZ, uint128 feeZ, int128 fundingZ, int256 positionAfter)');

  const client = createPublicClient({ transport: http(rpcUrl) });

  console.log('Listening for OrderFilled events on', engine);

  client.watchEvent({
    address: engine,
    event: abiOrderFilled,
    onLogs: (logs) => {
      for (const l of logs) {
        const { account, marketId, fillId, isBuy, size, priceZ, feeZ, fundingZ, positionAfter } = l.args;
        const normalized = {
          txHash: l.transactionHash,
          blockNumber: l.blockNumber,
          account,
          marketId: marketId,
          fillId: fillId,
          side: isBuy ? 'BUY' : 'SELL',
          size: size.toString(),
          priceZ: priceZ.toString(),
          feeZ: feeZ.toString(),
          fundingZ: fundingZ.toString(),
          positionAfter: positionAfter.toString(),
          isoTimestamp: new Date().toISOString()
        };
        console.log(JSON.stringify(normalized));
      }
    }
  });
}

main().catch(e => { console.error(e); process.exit(1); });
