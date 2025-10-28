// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FundingModule} from "../src/core/FundingModule.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract FundingModuleUUPSTest is Test {
    FundingModule proxyFunding;
    FundingModule impl;
    address admin = address(this);

    function setUp() public {
        impl = new FundingModule();
        bytes memory initData = abi.encodeWithSelector(FundingModule.initialize.selector, admin);
        proxyFunding = FundingModule(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testInitializeGrantsRoles() public {
        assertTrue(proxyFunding.hasRole(Constants.DEFAULT_ADMIN, admin));
        assertTrue(proxyFunding.hasRole(Constants.KEEPER, admin));
    }

    function testUpdateFundingIndexViaProxy() public {
        bytes32 marketId = keccak256("BTC-PERP");
        proxyFunding.updateFundingIndex(marketId, 1000);
        assertEq(proxyFunding.getFundingIndex(marketId), 1000);
    }

    function testUpgradeByAdminSucceeds() public {
        FundingModule newImpl = new FundingModule();
        proxyFunding.upgradeTo(address(newImpl));
        // ensure functionality remains
        bytes32 marketId = keccak256("ETH-PERP");
        proxyFunding.updateFundingIndex(marketId, -500);
        assertEq(proxyFunding.getFundingIndex(marketId), -500);
    }

    function testUpgradeByNonAdminReverts() public {
        FundingModule newImpl = new FundingModule();
        vm.prank(address(0xBAD));
        vm.expectRevert();
        proxyFunding.upgradeTo(address(newImpl));
    }

    function testImplementationInitializeReverts() public {
        vm.expectRevert();
        impl.initialize(admin);
    }
}
