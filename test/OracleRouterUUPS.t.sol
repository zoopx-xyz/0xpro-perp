// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {IPriceAdapter} from "../src/core/interfaces/IPriceAdapter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract MockPriceAdapter is IPriceAdapter {
    uint256 public p;
    bool public stale;

    constructor(uint256 _p, bool _s) {
        p = _p;
        stale = _s;
    }

    function getPrice(address) external view returns (uint256 priceX1e18, uint64 ts, bool isStale) {
        return (p, uint64(block.timestamp), stale);
    }
}

contract OracleRouterUUPSTest is Test {
    OracleRouter router;
    OracleRouter impl;
    address admin = address(this);

    function setUp() public {
        impl = new OracleRouter();
        bytes memory initData = abi.encodeWithSelector(OracleRouter.initialize.selector, admin);
        router = OracleRouter(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testRegisterAndGetters() public {
        MockPriceAdapter m = new MockPriceAdapter(123e18, false);
        address asset = address(0xA);
        router.registerAdapter(asset, address(m));
        (uint256 px, bool stale) = router.getPriceInZUSD(asset);
        assertEq(px, 123e18);
        assertFalse(stale);
        (px, stale) = router.getPriceAndStale(asset);
        assertEq(px, 123e18);
        assertFalse(stale);
    }

    function testRegisterTwoAssetsAndReRegister() public {
        // Register two different adapters for two assets and re-register one
        MockPriceAdapter m1 = new MockPriceAdapter(11e18, false);
        MockPriceAdapter m2 = new MockPriceAdapter(22e18, true);
        address a1 = address(0xA1);
        address a2 = address(0xA2);
        router.registerAdapter(a1, address(m1));
        router.registerAdapter(a2, address(m2));
        // Re-register a1 with m2 to exercise assignment path again
        router.registerAdapter(a1, address(m2));
        (uint256 p1, bool s1) = router.getPriceInZUSD(a1);
        (uint256 p2, bool s2) = router.getPriceAndStale(a2);
        assertEq(p1, 22e18);
        assertTrue(s2); // m2 is stale=true
            // both getters exercised across two assets
    }

    function testNoAdapterReverts() public {
        address asset = address(0xB);
        vm.expectRevert(bytes("no adapter"));
        router.getPriceInZUSD(asset);
        vm.expectRevert(bytes("no adapter"));
        router.getPriceAndStale(asset);
    }

    function testUUPSUpgradeAndImplInitializeReverts() public {
        OracleRouter newImpl = new OracleRouter();
        router.upgradeTo(address(newImpl));
        vm.expectRevert();
        newImpl.initialize(admin);
        // still functional after upgrade
        MockPriceAdapter m = new MockPriceAdapter(42e18, true);
        address asset = address(0xC);
        router.registerAdapter(asset, address(m));
        (uint256 px, bool stale) = router.getPriceInZUSD(asset);
        assertEq(px, 42e18);
        assertTrue(stale);
    }
}
