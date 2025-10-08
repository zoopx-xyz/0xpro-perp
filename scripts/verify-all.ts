import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

// This script verifies deployed contracts on Kadena Chainweb EVM Testnet chain 20 via Blockscout.
// It parses Foundry broadcast artifacts and the address map (5920.json), then calls hardhat-verify.

type BroadcastTx = {
  transactionType: string;
  contractName?: string;
  contractAddress?: string;
  arguments?: any[];
};

const root = process.cwd();
const broadcastFile = path.join(root, "broadcast/Deploy.s.sol/5920/run-latest.json");
const addressMapFile = path.join(root, "5920.json");

function sh(cmd: string) {
  console.log(`$ ${cmd}`);
  execSync(cmd, { stdio: "inherit" });
}

function main() {
  const network = "kadena_chain20"; // explicit network alias for EVM chain 20
  if (!fs.existsSync(broadcastFile)) {
    throw new Error(`Broadcast file not found: ${broadcastFile}`);
  }
  const broadcast = JSON.parse(fs.readFileSync(broadcastFile, "utf8"));
  const txs: BroadcastTx[] = broadcast.transactions || [];

  const impls = txs.filter((t) => t.transactionType === "CREATE" && t.contractName && !t.contractName.includes("ERC1967Proxy"));
  const proxies = txs.filter((t) => t.contractName === "ERC1967Proxy");

  console.log(`Found ${impls.length} implementations and ${proxies.length} proxies in broadcast.`);

  // Verify implementations first (no constructor args for upgradeable impls & mocks have args captured).
  for (const t of impls) {
    if (!t.contractAddress) continue;
    const addr = t.contractAddress;
    const args = t.arguments || [];
    try {
      if (args.length > 0) {
        // Verify with constructor args when present (e.g., MockERC20s)
        const argsJsonPath = path.join(root, ".tmp.verify.args.json");
        fs.writeFileSync(argsJsonPath, JSON.stringify(args));
        sh(`npx hardhat verify --network ${network} ${addr} --constructor-args ${argsJsonPath}`);
        fs.unlinkSync(argsJsonPath);
      } else {
        sh(`npx hardhat verify --network ${network} ${addr}`);
      }
    } catch (err) {
      console.warn(`Warn: verify impl ${t.contractName} at ${addr} failed/skipped: ${(err as Error).message}`);
    }
  }

  // Verify proxies by pointing to the ERC1967Proxy bytecode with constructor args [impl, data]
  for (const p of proxies) {
    if (!p.contractAddress) continue;
    const addr = p.contractAddress;
    const args = p.arguments || [];
    try {
      const argsJsonPath = path.join(root, ".tmp.verify.proxy.args.json");
      fs.writeFileSync(argsJsonPath, JSON.stringify(args));
      // Use the canonical OZ FQN per docs to help the verifier pick the right bytecode
      const proxyFqn = "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy";
  sh(`npx hardhat verify --network ${network} --contract ${proxyFqn} ${addr} --constructor-args ${argsJsonPath}`);
      fs.unlinkSync(argsJsonPath);
    } catch (err) {
      console.warn(`Warn: verify proxy at ${addr} failed/skipped: ${(err as Error).message}`);
    }
  }

  if (fs.existsSync(addressMapFile)) {
    const map = JSON.parse(fs.readFileSync(addressMapFile, "utf8"));
    // Convenience: print explorer URLs
    const browserURL = `http://chain-20.evm-testnet-blockscout.chainweb.com`;
    console.log("Explorer links:");
    for (const [k, v] of Object.entries(map.tokens || {})) {
      console.log(`- ${k}: ${browserURL}/address/${v}`);
    }
    for (const [k, v] of Object.entries(map.proxies || {})) {
      console.log(`- ${k}: ${browserURL}/address/${v}`);
    }
  }
}

main();
