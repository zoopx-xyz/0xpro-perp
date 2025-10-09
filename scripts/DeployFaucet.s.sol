// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {MultiTokenFaucet} from "../src/faucet/MultiTokenFaucet.sol";

contract DeployFaucet is Script {
    function run() external {
        vm.startBroadcast();
        address owner = msg.sender;

        MultiTokenFaucet faucet = new MultiTokenFaucet(owner);
        console.log("Faucet:", address(faucet));

        // Load token addresses from env
        address mETH = vm.envAddress("METH");
        address mWETH = vm.envAddress("MWETH");
        address mBTC = vm.envAddress("MBTC");
        address mWBTC = vm.envAddress("MWBTC");
        address mSOL = vm.envAddress("MSOL");
        address mKDA = vm.envAddress("MKDA");
        address mPOL = vm.envAddress("MPOL");
        address mZPX = vm.envAddress("MZPX");
        address mUSDC = vm.envAddress("MUSDC");
        address mUSDT = vm.envAddress("MUSDT");
        address mPYUSD = vm.envAddress("MPYUSD");
        address mUSD1 = vm.envAddress("MUSD1");

        // 24h cooldown
        faucet.setCooldown(1 days);

        // Configure drops in base units
        faucet.setDrops(
            _asArray(mETH, mWETH, mBTC, mWBTC, mSOL, mKDA, mPOL, mZPX, mUSDC, mUSDT, mPYUSD, mUSD1),
            _asAmounts(
                5e17,               // mETH  0.5 (18d)
                5e17,               // mWETH 0.5 (18d)
                1_000_000,          // mBTC  0.01 (8d)
                1_000_000,          // mWBTC 0.01 (8d)
                10_000_000_000,     // mSOL  10   (9d)
                5_000_000_000_000,  // mKDA  5000 (12d)
                5_000e18,           // mPOL  5000 (18d)
                5_000e18,           // mZPX  5000 (18d)
                2_000_000_000,      // mUSDC 2000 (6d)
                2_000_000_000,      // mUSDT 2000 (6d)
                2_000_000_000,      // mPYUSD 2000 (6d)
                2_000e18            // mUSD1 2000 (18d)
            ),
            _allEnabled()
        );

        vm.stopBroadcast();
    }

    function _asArray(address a,address b,address c,address d,address e,address f,address g,address h,address i,address j,address k,address l)
        internal pure returns (address[] memory arr)
    {
        arr = new address[](12);
        arr[0]=a;arr[1]=b;arr[2]=c;arr[3]=d;arr[4]=e;arr[5]=f;arr[6]=g;arr[7]=h;arr[8]=i;arr[9]=j;arr[10]=k;arr[11]=l;
    }

    function _asAmounts(
        uint256 a,uint256 b,uint256 c,uint256 d,uint256 e,uint256 f,uint256 g,uint256 h,uint256 i,uint256 j,uint256 k,uint256 l
    ) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](12);
        arr[0]=a;arr[1]=b;arr[2]=c;arr[3]=d;arr[4]=e;arr[5]=f;arr[6]=g;arr[7]=h;arr[8]=i;arr[9]=j;arr[10]=k;arr[11]=l;
    }

    function _allEnabled() internal pure returns (bool[] memory arr) {
        arr = new bool[](12);
        for (uint256 i=0;i<12;i++) arr[i] = true;
    }
}
