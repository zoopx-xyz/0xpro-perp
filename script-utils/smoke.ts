import { ethers } from "ethers";
import fs from "fs";

async function main() {
  const DEPLOY_JSON = process.env.DEPLOY_JSON || "";
  if (!DEPLOY_JSON) {
    throw new Error("DEPLOY_JSON env var required (path to deployments JSON)");
  }
  const RPC = process.env.RPC_URL || "";
  if (!RPC) throw new Error("RPC_URL missing in env");
  const pkRaw = (process.env.RELAYER_PRIVATE_KEY || "").trim();
  const pk = pkRaw ? (pkRaw.startsWith("0x") ? pkRaw : `0x${pkRaw}`) : "";
  if (!pk) throw new Error("RELAYER_PRIVATE_KEY missing in env");

  const deploy = JSON.parse(fs.readFileSync(DEPLOY_JSON, "utf8"));
  const provider = new ethers.JsonRpcProvider(RPC);
  const wallet = new ethers.Wallet(pk, provider);
  console.log("Using", await wallet.getAddress());

  const abiERC20 = [
    "function decimals() view returns (uint8)",
    "function balanceOf(address) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)"
  ];
  const abiVault = [
    "function deposit(address asset, uint256 amount, bool isolated, bytes32 marketId)",
    "function accountEquityZUSD(address user) view returns (int256)"
  ];
  const abiEngine = [
    "function registerMarket(bytes32,address,uint8,string)",
    "function openPosition(bytes32,bool,uint256,uint256)",
    "function closePosition(bytes32)",
    "function getPosition(address,bytes32) view returns (int256)",
    "function getPositionMarginRatioBps(address,bytes32) view returns (uint256)"
  ];
  const abiOracleRouter = [
    "function getPriceInZUSD(address) view returns (uint256,bool)"
  ];

  const zUsd = new ethers.Contract(deploy.tokens.zUSD, abiERC20, wallet);
  const vault = new ethers.Contract(deploy.proxies.MarginVaultV2, abiVault, wallet);
  const engine = new ethers.Contract(deploy.proxies.PerpEngine, abiEngine, wallet);
  const router = new ethers.Contract(deploy.proxies.OracleRouter, abiOracleRouter, wallet);

  const BTC = deploy.tokens.mBTC;
  const BTC_PERP = ethers.id("BTC-PERP");

  // 1) Sanity checks
  const [zDec, markInfo] = await Promise.all([
    zUsd.decimals(),
    router.getPriceInZUSD(BTC)
  ]);
  const [mark, stale] = markInfo as [bigint, boolean];
  console.log("zUSD decimals=", zDec, "BTC mark=", mark.toString(), "stale=", stale);
  if (stale) throw new Error("stale price, update oracle before smoke test");

  // 2) Deposit some zUSD into vault (cross)
  const depositToken = 1_000n * 10n ** BigInt(zDec); // 1000 zUSD
  // Ensure balance
  const bal = (await zUsd.balanceOf(wallet.address)) as bigint;
  if (bal < depositToken) throw new Error(`Not enough zUSD balance: have ${bal}, need ${depositToken}`);
  // Approve and deposit
  const approveTx = await zUsd.approve(vault.target as string, depositToken);
  await approveTx.wait();
  const depTx = await vault.deposit(zUsd.target as string, depositToken, false, ethers.ZeroHash);
  await depTx.wait();
  console.log("Deposited", depositToken.toString(), "zUSD to vault");

  // 3) Open a small 2x long on BTC-PERP using 100 zUSD collateral
  const collateral = 100n * 10n ** BigInt(zDec);
  const lev = 2n;
  const openTx = await engine.openPosition(BTC_PERP, true, collateral, lev);
  await openTx.wait();
  console.log("Opened 2x long BTC with 100 zUSD collateral");

  // 4) Read position + margin ratio
  const pos = await engine.getPosition(wallet.address, BTC_PERP);
  const mr = await engine.getPositionMarginRatioBps(wallet.address, BTC_PERP);
  console.log("Position size(base)=", pos.toString(), "MR bps=", mr.toString());

  // 5) Close position
  const closeTx = await engine.closePosition(BTC_PERP);
  await closeTx.wait();
  console.log("Closed position");

  // 6) Check equity
  const eq = await vault.accountEquityZUSD(wallet.address);
  console.log("Account equity z18=", eq.toString());
}

main().catch((e) => { console.error(e); process.exit(1); });
