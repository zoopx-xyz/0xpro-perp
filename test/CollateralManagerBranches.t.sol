// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CollateralManagerBranchesTest is Test {
    CollateralManager cm;
    OracleRouter orac;
    SignedPriceOracle spo;
    MockERC20 tok6;
    MockERC20 tok18;

    function setUp() public {
        CollateralManager cmImpl = new CollateralManager();
        cm = CollateralManager(address(new ERC1967Proxy(address(cmImpl), "")));
        OracleRouter orImpl = new OracleRouter();
        orac = OracleRouter(address(new ERC1967Proxy(address(orImpl), "")));
        SignedPriceOracle spoImpl = new SignedPriceOracle();
        spo = SignedPriceOracle(address(new ERC1967Proxy(address(spoImpl), "")));

        cm.initialize(address(this), address(orac));
        orac.initialize(address(this));
        spo.initialize(address(this), address(0), 300);

        tok6 = new MockERC20("T6", "T6", 6);
        tok18 = new MockERC20("T18", "T18", 18);
        orac.registerAdapter(address(tok6), address(spo));
        orac.registerAdapter(address(tok18), address(spo));
        cm.setAssetConfig(address(tok6), true, 9500, address(orac), 6); // 95% LTV
        cm.setAssetConfig(address(tok18), true, 8000, address(orac), 18); // 80% LTV
        spo.setPrice(address(tok6), 2e18, uint64(block.timestamp));
        spo.setPrice(address(tok18), 1e18, uint64(block.timestamp));
    }

    function testDisabledAssetReverts() public {
        // disable and expect revert
        cm.setAssetConfig(address(tok6), false, 9500, address(orac), 6);
        vm.expectRevert("asset disabled");
        cm.assetValueInZUSD(address(tok6), 1);
    }

    function testStalePriceReverts() public {
        vm.warp(block.timestamp + 301);
        vm.expectRevert("stale price");
        cm.assetValueInZUSD(address(tok6), 1000);
    }

    function testDecimalsPathAndLTV() public {
        // 6 decimals token at $2: 1_000_000 units = 1 token -> $2
        uint256 v6 = cm.assetValueInZUSD(address(tok6), 1_000_000);
        assertEq(v6, 2e18);
        uint256 c6 = cm.collateralValueInZUSD(address(tok6), 1_000_000); // 95%
        assertEq(c6, (2e18 * 9500) / 10000);

        // 18 decimals token at $1: 1e18 units -> $1; LTV 80%
        uint256 v18 = cm.assetValueInZUSD(address(tok18), 1e18);
        assertEq(v18, 1e18);
        uint256 c18 = cm.collateralValueInZUSD(address(tok18), 1e18);
        assertEq(c18, 8e17);
    }
}
