// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CompositePriceAdapter} from "../src/oracle/CompositePriceAdapter.sol";
import {IPriceAdapter} from "../src/core/interfaces/IPriceAdapter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockAdapterUUPS is IPriceAdapter {
    function getPrice(address) external view returns (uint256, uint64, bool) {
        return (1e18, uint64(block.timestamp), false);
    }
}

contract CompositePriceAdapterUUPSTest is Test {
    CompositePriceAdapter comp;
    CompositePriceAdapter impl;

    function setUp() public {
        impl = new CompositePriceAdapter();
        bytes memory init =
            abi.encodeWithSelector(CompositePriceAdapter.initialize.selector, address(this), address(0), address(0));
        comp = CompositePriceAdapter(address(new ERC1967Proxy(address(impl), init)));
    }

    function testUpgradeAndImplementationInitializeReverts() public {
        CompositePriceAdapter newImpl = new CompositePriceAdapter();
        comp.upgradeTo(address(newImpl));
        vm.expectRevert();
        newImpl.initialize(address(this), address(0), address(0));
        // still functional: set primary/secondary and fetch
        MockAdapterUUPS a1 = new MockAdapterUUPS();
        MockAdapterUUPS a2 = new MockAdapterUUPS();
        comp.setPrimary(address(a1));
        comp.setSecondary(address(a2));
        (uint256 p,, bool stale) = comp.getPrice(address(0xA));
        assertEq(p, 1e18);
        assertFalse(stale);
    }
}
