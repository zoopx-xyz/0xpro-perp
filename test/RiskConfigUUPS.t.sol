// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskConfig} from "../src/core/RiskConfig.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RiskConfigUUPSTest is Test {
    RiskConfig proxyCfg;
    RiskConfig impl;
    address admin = address(this);

    function setUp() public {
        impl = new RiskConfig();
        bytes memory initData = abi.encodeWithSelector(RiskConfig.initialize.selector, admin);
        proxyCfg = RiskConfig(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testImplementationInitializeReverts() public {
        vm.expectRevert();
        impl.initialize(admin);
    }

    function testUpgradeByAdminSucceedsAndGetters() public {
        RiskConfig newImpl = new RiskConfig();
        proxyCfg.upgradeTo(address(newImpl));
        // set and get market risk
        RiskConfig.MarketRisk memory r = RiskConfig.MarketRisk({
            imrBps: 1000,
            mmrBps: 500,
            liqPenaltyBps: 50,
            makerFeeBps: 1,
            takerFeeBps: 2,
            maxLev: 50
        });
        bytes32 mid = keccak256("BTC-PERP");
        proxyCfg.setMarketRisk(mid, r);
        RiskConfig.MarketRisk memory out = proxyCfg.getMarketRisk(mid);
        assertEq(out.imrBps, 1000);
        assertEq(proxyCfg.getIMRBps(mid), 1000);
        assertEq(proxyCfg.getMMRBps(mid), 500);
        assertEq(proxyCfg.getLiqPenaltyBps(mid), 50);
    }
}
