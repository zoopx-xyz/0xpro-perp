import { execSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const addressMapFile = path.join(root, "5920.json");

function sh(cmd: string) {
  console.log(`$ ${cmd}`);
  execSync(cmd, { stdio: "inherit" });
}

function main() {
  if (!fs.existsSync(addressMapFile)) {
    throw new Error(`Address map not found: ${addressMapFile}`);
  }
  const map = JSON.parse(fs.readFileSync(addressMapFile, "utf8"));
  const network = "kadena_chain20"; // explicit network alias for EVM chain 20

  // Verify proxies with known FQN
  const proxyFqn = "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy";
  for (const [name, addr] of Object.entries<string>(map.proxies || {})) {
    try {
      // Constructor args for our proxies were [impl, 0x], but we don't have impls here; fall back to broadcast script if needed.
      // We'll skip constructor args here (Blockscout often handles proxies by code match); otherwise use verify-all.ts.
  sh(`npx hardhat verify --network ${network} --contract ${proxyFqn} ${addr}`);
    } catch (e) {
      console.warn(`Warn: proxy ${name} at ${addr} verify failed/skipped: ${(e as Error).message}`);
    }
  }

  // Tokens and any direct impls can be verified without extra data.
  for (const [name, addr] of Object.entries<string>(map.tokens || {})) {
    try {
  sh(`npx hardhat verify --network ${network} ${addr}`);
    } catch (e) {
      console.warn(`Warn: token ${name} at ${addr} verify failed/skipped: ${(e as Error).message}`);
    }
  }
}

main();
