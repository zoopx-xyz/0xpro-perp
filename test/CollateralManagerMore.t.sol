// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CollateralManagerMoreTest is Test {
    function testGetAssetsList() public {
        CollateralManager cm = CollateralManager(address(new ERC1967Proxy(address(new CollateralManager()), "")));
        OracleRouter orac = OracleRouter(address(new ERC1967Proxy(address(new OracleRouter()), "")));
        SignedPriceOracle spo = SignedPriceOracle(address(new ERC1967Proxy(address(new SignedPriceOracle()), "")));
        cm.initialize(address(this), address(orac));
        orac.initialize(address(this));
        spo.initialize(address(this), address(0), 300);

        MockERC20 t1 = new MockERC20("A","A",6);
        MockERC20 t2 = new MockERC20("B","B",18);
        orac.registerAdapter(address(t1), address(spo));
        orac.registerAdapter(address(t2), address(spo));
        cm.setAssetConfig(address(t1), true, 5000, address(orac), 6);
        cm.setAssetConfig(address(t2), true, 6000, address(orac), 18);
        address[] memory assets = cm.getAssets();
        assertEq(assets.length, 2);
        assertEq(assets[0], address(t1));
        assertEq(assets[1], address(t2));
        // calling setAssetConfig again shouldn't duplicate entries
        cm.setAssetConfig(address(t1), true, 5500, address(orac), 6);
        assets = cm.getAssets();
        assertEq(assets.length, 2);
    }

    function testOnlyRiskAdminCanSetAssetConfig() public {
        CollateralManager cm = CollateralManager(address(new ERC1967Proxy(address(new CollateralManager()), "")));
        OracleRouter orac = OracleRouter(address(new ERC1967Proxy(address(new OracleRouter()), "")));
        cm.initialize(address(this), address(orac));
        address stranger = address(0xBAD);
        vm.prank(stranger);
        vm.expectRevert();
        cm.setAssetConfig(address(0xA), true, 5000, address(orac), 18);
    }
}
