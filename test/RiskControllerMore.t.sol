// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskController} from "../src/risk/RiskController.sol";
import {ICollateralManager} from "../src/core/interfaces/ICollateralManager.sol";
import {Constants} from "../lib/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockCMMore is ICollateralManager {
    mapping(address => AssetConfig) public cfg;
    function setAssetConfig(address asset, bool enabled, uint16 ltvBps, address oracle, uint8 decimals) external {
        cfg[asset] = AssetConfig(enabled, ltvBps, oracle, decimals);
    }
    function assetValueInZUSD(address, uint256) external pure returns (uint256) { return 0; }
    function collateralValueInZUSD(address, uint256) external pure returns (uint256) { return 0; }
    function config(address asset) external view returns (bool enabled, uint16 ltvBps, address oracle, uint8 decimals) {
        AssetConfig memory c = cfg[asset];
        return (c.enabled, c.ltvBps, c.oracle, c.decimals);
    }
}

contract RiskControllerMoreTest is Test {
    RiskController rc;
    RiskController impl;
    MockCMMore cm;
    address admin = address(this);
    address asset = address(0xA);

    function setUp() public {
        cm = new MockCMMore();
        impl = new RiskController();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(RiskController.initialize.selector, admin, address(cm))
        );
        rc = RiskController(address(proxy));
        rc.grantRole(Constants.RISK_ADMIN, admin);
        cm.setAssetConfig(asset, true, 5000, address(0x1234), 18);
    }

    function testRailsNotSetReverts() public {
        vm.expectRevert(bytes("rails not set"));
        rc.updateLtv(asset, 5100);
    }

    function testSetGuardrailsMinGreaterThanMaxReverts() public {
        vm.expectRevert(bytes("min>max"));
        rc.setGuardrails(asset, 6000, 5000, 100, 0);
    }

    function testAccessControlOnGuardrailsAndUpdate() public {
        address stranger = address(0xBADC0DE);
        vm.prank(stranger);
        vm.expectRevert();
        rc.setGuardrails(asset, 3000, 7000, 500, 0);

        rc.setGuardrails(asset, 3000, 7000, 500, 0);
        vm.prank(stranger);
        vm.expectRevert();
        rc.updateLtv(asset, 5500);
    }

    function testUUPSUpgradeAndImplInitializeReverts() public {
        // Upgrade should be authorized by DEFAULT_ADMIN
        RiskController newImpl = new RiskController();
        rc.upgradeTo(address(newImpl));
        // Initializing implementation directly should revert
        vm.expectRevert();
        newImpl.initialize(admin, address(cm));
        // still functional after upgrade
        rc.setGuardrails(asset, 3000, 7000, 500, 0);
        rc.updateLtv(asset, 5200);
        (bool enabled, uint16 ltv,,) = cm.config(asset);
        assertTrue(enabled);
        assertEq(ltv, 5200);
    }

    function testUpdateWithNoStepLimit() public {
        // No step limit (maxStepBps = 0) should skip step-size check
        rc.setGuardrails(asset, 3000, 9000, 0, 0);
        // initial ltv in MockCM is 5000; update to 8900 within bounds without step limit
        rc.updateLtv(asset, 8900);
        (bool enabled, uint16 ltv,,) = cm.config(asset);
        assertTrue(enabled);
        assertEq(ltv, 8900);
    }

    function testCooldownRevertsWhenWithinInterval() public {
        rc.setGuardrails(asset, 3000, 9000, 1000, 3600); // max step 1000, cooldown 1h
        // advance time to allow first update
        vm.warp(block.timestamp + 3601);
        // first update ok
        rc.updateLtv(asset, 5500);
    // immediate next update should revert due to cooldown (message may vary under IR mapping)
    vm.expectRevert();
        rc.updateLtv(asset, 5600);
    }
}
