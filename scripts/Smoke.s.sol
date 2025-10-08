// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {PerpEngine} from "../src/core/PerpEngine.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";

contract Smoke is Script {
    using stdJson for string;

    function _startsWith0x(string memory s) internal pure returns (bool) {
        bytes memory b = bytes(s);
        return b.length >= 2 && b[0] == '0' && (b[1] == 'x' || b[1] == 'X');
    }

    function _strip0x(string memory s) internal pure returns (string memory) {
        if (_startsWith0x(s)) {
            bytes memory b = bytes(s);
            bytes memory out = new bytes(b.length - 2);
            for (uint256 i = 2; i < b.length; i++) out[i - 2] = b[i];
            return string(out);
        }
        return s;
    }

    function _leftPadTo64(string memory hexNoPrefix) internal pure returns (string memory) {
        bytes memory src = bytes(hexNoPrefix);
        require(src.length <= 64, "pk too long");
        if (src.length == 64) return hexNoPrefix;
        uint256 pad = 64 - src.length;
        bytes memory out = new bytes(64);
        for (uint256 i = 0; i < pad; i++) out[i] = '0';
        for (uint256 j = 0; j < src.length; j++) out[pad + j] = src[j];
        return string(out);
    }

    function _normalizePkHex(string memory pkEnv) internal pure returns (string memory) {
        string memory no0x = _strip0x(pkEnv);
        string memory padded = _leftPadTo64(no0x);
        return string.concat("0x", padded);
    }

    function run() external {
        // Load addresses from deployments/5920.json
        string memory path = string.concat(vm.projectRoot(), "/deployments/5920.json");
        string memory json = vm.readFile(path);

        address zUsd = json.readAddress(".tokens.zUSD");
        address mBTC = json.readAddress(".tokens.mBTC");
        address vault = json.readAddress(".proxies.MarginVaultV2");
        address engine = json.readAddress(".proxies.PerpEngine");
        address router = json.readAddress(".proxies.OracleRouter");
        address spo = json.readAddress(".proxies.SignedPriceOracle");

    // Read PK from env (RELAYER_PRIVATE_KEY): accept with or without 0x and with or without leading zeros
    string memory pkStr = vm.envString("RELAYER_PRIVATE_KEY");
    string memory pkHex = _normalizePkHex(pkStr);
    bytes memory pkBytes = vm.parseBytes(pkHex);
    require(pkBytes.length == 32, "bad pk length");
    uint256 pkNum;
    assembly { pkNum := mload(add(pkBytes, 32)) }
    vm.startBroadcast(pkNum);

        // 1) Ensure BTC price is fresh (update via keeper if stale)
        (uint256 mark, bool stale) = OracleRouter(router).getPriceInZUSD(mBTC);
        if (stale || mark == 0) {
            // set a default fresh price if none; adjust if desired
            uint256 newPx = 60_000e18;
            SignedPriceOracle(spo).setPrice(mBTC, newPx, uint64(block.timestamp));
            (mark, stale) = OracleRouter(router).getPriceInZUSD(mBTC);
            console.log("Refreshed BTC price to:", mark);
        } else {
            console.log("BTC price (z18):", mark);
        }

        // 2) Deposit 1000 zUSD into vault (cross)
        uint8 zDec = 6; // MockzUSD uses 6 decimals
        uint256 depositAmt = 1_000 * (10 ** zDec);
        IERC20(zUsd).approve(vault, depositAmt);
        MarginVaultV2(vault).deposit(zUsd, depositAmt, false, bytes32(0));
        console.log("Deposited zUSD:", depositAmt);

        // 3) Open a 2x long BTC-PERP with 100 zUSD collateral
        bytes32 BTC_PERP = keccak256("BTC-PERP");
        uint256 collateral = 100 * (10 ** zDec);
        PerpEngine(engine).openPosition(BTC_PERP, true, collateral, 2);
        console.log("Opened 2x long BTC-PERP using 100 zUSD");

        // 4) Read position and margin ratio
    address sender = vm.addr(pkNum);
    int256 pos = PerpEngine(engine).getPosition(sender, BTC_PERP);
    uint256 mr = PerpEngine(engine).getPositionMarginRatioBps(sender, BTC_PERP);
        console.log("Position size (base units):", uint256(pos > 0 ? pos : -pos));
        console.log("Margin Ratio (bps):", mr);

        // 5) Close position
        PerpEngine(engine).closePosition(BTC_PERP);
        console.log("Closed position");

        // 6) Equity check (z18)
    int256 eq = MarginVaultV2(vault).accountEquityZUSD(sender);
        console.log("Account equity (z18):", uint256(eq >= 0 ? eq : -eq));

        vm.stopBroadcast();
    }
}
