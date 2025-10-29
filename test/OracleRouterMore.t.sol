// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {IPriceAdapter} from "../src/core/interfaces/IPriceAdapter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockPA2 is IPriceAdapter {
    uint256 p;
    bool s;

    constructor(uint256 _p, bool _s) {
        p = _p;
        s = _s;
    }

    function getPrice(address) external view returns (uint256 priceX1e18, uint64 ts, bool isStale) {
        return (p, uint64(block.timestamp), s);
    }
}

contract OracleRouterMoreTest is Test {
    OracleRouter router;

    function setUp() public {
        router = OracleRouter(address(new ERC1967Proxy(address(new OracleRouter()), "")));
        router.initialize(address(this));
    }

    function testRegisterTwoAdaptersAndFetchBothGetters() public {
        address a1 = address(0xA1);
        address a2 = address(0xA2);
        MockPA2 m1 = new MockPA2(111e18, false);
        MockPA2 m2 = new MockPA2(222e18, true);
        router.registerAdapter(a1, address(m1));
        router.registerAdapter(a2, address(m2));
        (uint256 p1, bool s1) = router.getPriceInZUSD(a1);
        assertEq(p1, 111e18);
        assertFalse(s1);
        (uint256 p2, bool s2) = router.getPriceAndStale(a2);
        assertEq(p2, 222e18);
        assertTrue(s2);
    }

    function testOnlyAdminCannotRegisterAdapter() public {
        address asset = address(0xDAD);
        MockPA2 m = new MockPA2(1e18, false);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        router.registerAdapter(asset, address(m));
    }
}
