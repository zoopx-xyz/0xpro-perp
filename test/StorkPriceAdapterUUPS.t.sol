// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StorkPriceAdapter} from "../src/oracle/StorkPriceAdapter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StorkPriceAdapterUUPSTest is Test {
    StorkPriceAdapter ad;
    StorkPriceAdapter impl;

    function setUp() public {
        impl = new StorkPriceAdapter();
        ad = StorkPriceAdapter(address(new ERC1967Proxy(address(impl), "")));
        ad.initialize(address(this), address(0xDEADBEEF));
    }

    function testUpgradeAndImplementationInitializeReverts() public {
        StorkPriceAdapter newImpl = new StorkPriceAdapter();
        ad.upgradeTo(address(newImpl));
        vm.expectRevert();
        newImpl.initialize(address(this), address(0xDEADBEEF));
    }
}
