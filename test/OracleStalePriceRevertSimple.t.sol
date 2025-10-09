// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/SignedPriceOracle.sol";
import "../src/core/OracleRouter.sol";
import "../src/core/PerpEngine.sol";
import "../src/core/interfaces/IPerpEngine.sol";
import "../lib/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OracleStalePriceRevertSimpleTest is Test {
    SignedPriceOracle oracle;
    OracleRouter router;

    address admin = address(0x123);
    address keeper = address(0x456);
    address signer = address(0xabc);
    address mockBTC = address(0xdef);

    uint256 constant MAX_STALE = 300; // 5 minutes

    function setUp() public {
        vm.startPrank(admin);

        // Deploy via proxies to respect upgradeable initialize patterns
        SignedPriceOracle oracleImpl = new SignedPriceOracle();
        oracle = SignedPriceOracle(address(new ERC1967Proxy(address(oracleImpl), "")));
        oracle.initialize(admin, signer, uint64(MAX_STALE));

        OracleRouter routerImpl = new OracleRouter();
        router = OracleRouter(address(new ERC1967Proxy(address(routerImpl), "")));
        router.initialize(admin);
        router.registerAdapter(mockBTC, address(oracle));

        // Grant roles
        oracle.grantRole(Constants.PRICE_KEEPER, keeper);

        // Set initial price (fresh)
        vm.warp(1000);
        oracle.setPrice(mockBTC, 50000e18, uint64(block.timestamp));

        vm.stopPrank();
    }

    function testSetMaxStaleByPriceKeeper() public {
        vm.prank(keeper);
        oracle.setMaxStale(600); // 10 minutes
        assertEq(oracle.getMaxStale(), 600);
    }

    function test_RevertWhen_SetMaxStaleByNonKeeper() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        oracle.setMaxStale(600);
    }

    function testGetPriceAndStale() public {
        // Fresh price
        (uint256 price, bool isStale) = router.getPriceAndStale(mockBTC);
        assertEq(price, 50000e18);
        assertFalse(isStale);

        // Make price stale
        vm.warp(block.timestamp + MAX_STALE + 1);
        (price, isStale) = router.getPriceAndStale(mockBTC);
        assertEq(price, 50000e18);
        assertTrue(isStale);
    }

    function testRefreshPriceMakesFreshAgain() public {
        // Make price stale
        vm.warp(block.timestamp + MAX_STALE + 1);

        (, bool isStale) = router.getPriceAndStale(mockBTC);
        assertTrue(isStale);

        // Refresh price
        vm.prank(keeper);
        oracle.setPrice(mockBTC, 51000e18, uint64(block.timestamp));

        // Should be fresh now
        (uint256 price, bool isStaleAfter) = router.getPriceAndStale(mockBTC);
        assertEq(price, 51000e18);
        assertFalse(isStaleAfter);
    }

    function testMaxStaleZeroMeansPriceNeverStale() public {
        // Set max stale to 0 (special case: never stale)
        vm.prank(keeper);
        oracle.setMaxStale(0);

        // Even after long time, should not be stale
        vm.warp(block.timestamp + 365 days);

        (, bool isStale) = router.getPriceAndStale(mockBTC);
        assertFalse(isStale);
    }

    function testEmptyPriceIsStale() public {
        // Register new asset without setting price
        address mockETH = address(0x888);

        vm.prank(admin);
        router.registerAdapter(mockETH, address(oracle));

        // Should be stale (timestamp = 0)
        (, bool isStale) = router.getPriceAndStale(mockETH);
        assertTrue(isStale);
    }
}
