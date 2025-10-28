// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketFactory} from "../src/core/MarketFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract MarketFactoryUUPSTest is Test {
    MarketFactory proxyFactory;
    MarketFactory impl;
    address admin = address(this);

    function setUp() public {
        impl = new MarketFactory();
        bytes memory initData = abi.encodeWithSelector(MarketFactory.initialize.selector, admin);
        proxyFactory = MarketFactory(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testInitializeGrantsAdminRole() public {
        assertTrue(proxyFactory.hasRole(Constants.DEFAULT_ADMIN, admin));
    }

    function testCreateMarketThroughUUPSProxy() public {
        bytes32 id = keccak256("ARB-PERP");
        MarketFactory.MarketParams memory p = MarketFactory.MarketParams({base: address(0xABCD), baseDecimals: 18, quoteDecimals: 6});
        
        vm.expectEmit(true, true, true, true);
        emit MarketFactory.MarketCreated(id, address(0xABCD), 18, 6);
        proxyFactory.createMarket(id, address(0xABCD), 18, 6, p);
        
        (address base, uint8 bd, uint8 qd) = proxyFactory.markets(id);
        assertEq(base, address(0xABCD));
        assertEq(bd, 18);
        assertEq(qd, 6);
    }

    function testUpgradeByAdminSucceeds() public {
        // deploy a new implementation
        MarketFactory newImpl = new MarketFactory();
        // call upgrade via proxy as admin; should pass and hit _authorizeUpgrade
        proxyFactory.upgradeTo(address(newImpl));

        // After upgrade, functionality should still work
        bytes32 id = keccak256("OP-PERP");
        MarketFactory.MarketParams memory p = MarketFactory.MarketParams({base: address(0xD00D), baseDecimals: 8, quoteDecimals: 18});
        proxyFactory.createMarket(id, address(0xD00D), 8, 18, p);
        (address base,,) = proxyFactory.markets(id);
        assertEq(base, address(0xD00D));
    }

    function testUpgradeByNonAdminReverts() public {
        MarketFactory newImpl = new MarketFactory();
        vm.prank(address(0xBAD));
        vm.expectRevert();
        proxyFactory.upgradeTo(address(newImpl));
    }

    function testInitializeImplementationReverts() public {
        // initializing the implementation directly should revert since constructor disables it
        vm.expectRevert();
        impl.initialize(admin);
    }
}
