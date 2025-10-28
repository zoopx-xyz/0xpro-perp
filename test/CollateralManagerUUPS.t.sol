// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CollateralManagerUUPSTest is Test {
    CollateralManager cm;
    CollateralManager impl;
    OracleRouter router;

    function setUp() public {
        impl = new CollateralManager();
        router = OracleRouter(address(new ERC1967Proxy(address(new OracleRouter()), "")));
        router.initialize(address(this));
        bytes memory init = abi.encodeWithSelector(CollateralManager.initialize.selector, address(this), address(router));
        cm = CollateralManager(address(new ERC1967Proxy(address(impl), init)));
    }

    function testUpgradeAndImplementationInitializeReverts() public {
        CollateralManager newImpl = new CollateralManager();
        cm.upgradeTo(address(newImpl));
        vm.expectRevert();
        newImpl.initialize(address(this), address(router));
        // still functional
        cm.setAssetConfig(address(0xA), true, 5000, address(router), 18);
    }
}
