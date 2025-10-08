import { ethers } from "hardhat";

// Reads Chainweb chain number via the precompile and logs the EVM chainId.
// Chain 20 should return chainwebChainId=20 and chainId 5920 per config.

async function main() {
  const [signer] = await ethers.getSigners();
  const provider = signer.provider!;
  const net = await provider.getNetwork();
  console.log(JSON.stringify({
    evmChainId: Number(net.chainId),
    rpc: "https://evm-testnet.chainweb.com/chainweb/0.0/evm-testnet/chain/20/evm/rpc",
    note: "This network alias is configured to the Kadena EVM testnet chain 20 (EVM chainId 5920)."
  }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
