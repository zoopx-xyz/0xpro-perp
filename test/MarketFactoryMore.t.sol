// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketFactory} from "../src/core/MarketFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MarketFactoryMoreTest is Test {
    MarketFactory factory;
    address admin = address(this);

    function setUp() public {
        MarketFactory impl = new MarketFactory();
        factory = MarketFactory(address(new ERC1967Proxy(address(impl), abi.encodeWithSelector(MarketFactory.initialize.selector, admin))));
    }

    function testOnlyAdminCanCreateMarket() public {
        bytes32 id = keccak256("SOL-PERP");
        MarketFactory.MarketParams memory p = MarketFactory.MarketParams({base: address(0xABCD), baseDecimals: 9, quoteDecimals: 18});
        vm.prank(address(0xBAD));
        vm.expectRevert();
        factory.createMarket(id, p.base, p.baseDecimals, p.quoteDecimals, p);
    }
}
