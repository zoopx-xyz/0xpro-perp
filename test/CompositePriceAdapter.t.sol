// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CompositePriceAdapter} from "../src/oracle/CompositePriceAdapter.sol";
import {IPriceAdapter} from "../src/core/interfaces/IPriceAdapter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockAdapter is IPriceAdapter {
    uint256 public px;
    uint64 public ts;
    bool public stale;

    function set(uint256 p, uint64 t, bool s) external {
        px = p;
        ts = t;
        stale = s;
    }

    function getPrice(address) external view returns (uint256, uint64, bool) {
        return (px, ts, stale);
    }
}

contract CompositePriceAdapterTest is Test {
    CompositePriceAdapter comp;
    MockAdapter primary;
    MockAdapter secondary;
    address admin = address(this);
    address asset = address(0xA);

    function setUp() public {
        CompositePriceAdapter impl = new CompositePriceAdapter();
        comp = CompositePriceAdapter(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeWithSelector(CompositePriceAdapter.initialize.selector, admin, address(0), address(0))
                )
            )
        );
        primary = new MockAdapter();
        secondary = new MockAdapter();
        comp.setPrimary(address(primary));
        comp.setSecondary(address(secondary));
    }

    function testPrimaryFreshNoDeviationPolicy() public {
        primary.set(100e18, 100, false);
        (uint256 p,, bool stale) = comp.getPrice(asset);
        assertEq(p, 100e18);
        assertFalse(stale);
    }

    function testDeviationWithinBoundsUsesPrimary() public {
        comp.setPolicy(asset, true, 100); // 1%
        primary.set(100e18, 100, false);
        secondary.set(101e18, 100, false);
        (uint256 p,, bool stale) = comp.getPrice(asset);
        assertEq(p, 100e18);
        assertFalse(stale);
    }

    function testDeviationTooHighMarksStaleWithoutFallback() public {
        comp.setPolicy(asset, false, 100); // 1%
        primary.set(100e18, 100, false);
        secondary.set(120e18, 100, false);
        (uint256 p,, bool stale) = comp.getPrice(asset);
        assertEq(p, 100e18);
        assertTrue(stale);
    }

    function testFallbackOnStaleUsesSecondary() public {
        comp.setPolicy(asset, true, 0);
        primary.set(0, 0, true);
        secondary.set(88e18, 99, false);
        (uint256 p, uint64 t, bool stale) = comp.getPrice(asset);
        assertEq(p, 88e18);
        assertEq(t, 99);
        assertFalse(stale);
    }

    function testDeviationTooHighWithFallbackEnabledUsesSecondary() public {
        // Primary fresh but deviates too much; fallbackOnStale is true so we still take secondary per implementation
        comp.setPolicy(asset, true, 100); // 1%
        primary.set(100e18, 100, false);
        secondary.set(120e18, 101, false);
        (uint256 p, uint64 t, bool stale) = comp.getPrice(asset);
        assertEq(p, 120e18);
        assertEq(t, 101);
        assertFalse(stale);
    }

    function testSecondaryStaleFallbackUsesSecondaryResult() public {
        // With deviation policy set and secondary stale, implementation still falls back to secondary per current logic
        comp.setPolicy(asset, true, 100); // 1%
        primary.set(100e18, 100, false);
        secondary.set(150e18, 90, true); // stale secondary
        (uint256 p,, bool stale) = comp.getPrice(asset);
        assertEq(p, 150e18);
        assertTrue(stale);
    }

    function testDeviationTooHighWithZeroSecondaryReturnsSecondaryZero() public {
        // Secondary returns zero and not stale; deviation path skips check (sPx==0) and falls back to secondary
        comp.setPolicy(asset, true, 100); // 1%
        primary.set(100e18, 100, false);
        secondary.set(0, 95, false); // unusable for deviation check
        (uint256 p, uint64 t, bool stale) = comp.getPrice(asset);
        assertEq(p, 0);
        assertEq(t, 95);
        // stale=false because secondary reported not stale
        assertFalse(stale);
    }

    function testPrimaryStaleNoFallbackMarksStale_A() public {
        // Primary stale and fallback disabled => return primary stale
        comp.setPolicy(asset, false, 0);
        primary.set(123e18, 77, true);
        (uint256 p, uint64 t, bool stale) = comp.getPrice(asset);
        assertEq(p, 123e18);
        assertEq(t, 77);
        assertTrue(stale);
    }

    function testPrimaryStaleNoFallbackMarksStale_B() public {
        // Primary stale and no fallback allowed -> return primary and stale=true
        comp.setPolicy(asset, false, 0);
        primary.set(123e18, 55, true);
        (uint256 p, uint64 t, bool stale) = comp.getPrice(asset);
        assertEq(p, 123e18);
        assertEq(t, 55);
        assertTrue(stale);
    }

    function testDeviationTooHighNoFallbackAndSecondaryZeroMarksStale() public {
        // Primary fresh but deviation policy set; secondary returns zero so deviation check skipped.
        // With fallback disabled, function should return primary but mark stale because maxDeviationBps > 0.
        comp.setPolicy(asset, false, 100); // 1%
        primary.set(100e18, 100, false);
        secondary.set(0, 95, false); // unusable for deviation check
        (uint256 p,, bool stale) = comp.getPrice(asset);
        assertEq(p, 100e18);
        assertTrue(stale);
    }
}
