// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskController} from "../src/risk/RiskController.sol";
import {ICollateralManager} from "../src/core/interfaces/ICollateralManager.sol";
import {Constants} from "../lib/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockCM is ICollateralManager {
    mapping(address => AssetConfig) public cfg;
    function setAssetConfig(address asset, bool enabled, uint16 ltvBps, address oracle, uint8 decimals) external {
        cfg[asset] = AssetConfig(enabled, ltvBps, oracle, decimals);
    }
    function assetValueInZUSD(address, uint256) external view returns (uint256) { return 0; }
    function collateralValueInZUSD(address, uint256) external view returns (uint256) { return 0; }
    function config(address asset) external view returns (bool enabled, uint16 ltvBps, address oracle, uint8 decimals) {
        AssetConfig memory c = cfg[asset];
        return (c.enabled, c.ltvBps, c.oracle, c.decimals);
    }
}

contract RiskControllerTest is Test {
    RiskController rc;
    MockCM cm;
    address admin = address(this);
    address asset = address(0xA);

    function setUp() public {
    cm = new MockCM();
    RiskController impl = new RiskController();
    rc = RiskController(address(new ERC1967Proxy(address(impl), abi.encodeWithSelector(RiskController.initialize.selector, admin, address(cm)))));
        // grant risk admin to this test
        rc.grantRole(Constants.RISK_ADMIN, admin);
        // initial config
    cm.setAssetConfig(asset, true, 5000, address(0x1234), 18);
    }

    function testUpdateWithinRailsAndCooldown() public {
        // Allow first update immediately by setting minInterval=0
        rc.setGuardrails(asset, 3000, 8000, 1000, 0);
        rc.updateLtv(asset, 5500);
        // Now enforce cooldown by updating minInterval to 3600 while preserving lastUpdate
        rc.setGuardrails(asset, 3000, 8000, 1000, 3600);
        vm.expectRevert(bytes("cooldown"));
        rc.updateLtv(asset, 5600);
        vm.warp(block.timestamp + 3600);
        rc.updateLtv(asset, 5600);
    (,, address oracle, uint8 dec) = cm.config(asset);
        // Verify config set via CM
        (bool enabled, uint16 ltv,,) = cm.config(asset);
        assertTrue(enabled);
        assertEq(ltv, 5600);
    assertEq(oracle, address(0x1234));
        assertEq(dec, 18);
    }

    function testBoundsAndStepEnforced() public {
        rc.setGuardrails(asset, 3000, 6000, 200, 0);
        // below min
        vm.expectRevert(bytes("bounds"));
        rc.updateLtv(asset, 2500);
        // above max
        vm.expectRevert(bytes("bounds"));
        rc.updateLtv(asset, 7000);
    // step too large from 5000 -> 5200 ok, 5600 revert
    rc.updateLtv(asset, 5200);
        vm.expectRevert(bytes("step too large"));
        rc.updateLtv(asset, 5600);
    }
}
