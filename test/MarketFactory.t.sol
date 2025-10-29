// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketFactory} from "../src/core/MarketFactory.sol";

contract MarketFactoryTest is Test {
    MarketFactory factory;

    function setUp() public {
        factory = MarketFactory(_deployProxy(address(new MarketFactory())));
        factory.initialize(address(this));
    }

    function _deployProxy(address impl) internal returns (address) {
        bytes memory code = abi.encodePacked(
            hex"3d602d80600a3d3981f3", hex"363d3d373d3d3d363d73", bytes20(impl), hex"5af43d82803e903d91602b57fd5bf3"
        );
        address proxy;
        assembly {
            proxy := create(0, add(code, 0x20), mload(code))
        }
        require(proxy != address(0), "proxy fail");
        return proxy;
    }

    function testCreateMarket() public {
        bytes32 id = keccak256("BTC-PERP");
        MarketFactory.MarketParams memory p =
            MarketFactory.MarketParams({base: address(0xBEEF), baseDecimals: 8, quoteDecimals: 18});
        vm.expectEmit(true, true, true, true);
        emit MarketFactory.MarketCreated(id, address(0xBEEF), 8, 18);
        factory.createMarket(id, address(0xBEEF), 8, 18, p);
        (address base, uint8 bd, uint8 qd) = factory.markets(id);
        assertEq(base, address(0xBEEF));
        assertEq(bd, 8);
        assertEq(qd, 18);
    }

    function testCreateMarketOnlyAdmin() public {
        bytes32 id = keccak256("ETH-PERP");
        MarketFactory.MarketParams memory p =
            MarketFactory.MarketParams({base: address(0xCAFE), baseDecimals: 18, quoteDecimals: 18});
        vm.prank(address(0xBAD));
        vm.expectRevert();
        factory.createMarket(id, address(0xCAFE), 18, 18, p);
    }

    function testNonAdminCannotUpgrade() public {
        address newImpl = address(0x123);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        factory.upgradeToAndCall(newImpl, "");
    }

    function testMarketsMapping() public {
        bytes32 id = keccak256("SOL-PERP");
        MarketFactory.MarketParams memory p =
            MarketFactory.MarketParams({base: address(0x999), baseDecimals: 9, quoteDecimals: 6});
        factory.createMarket(id, address(0x999), 9, 6, p);
        (address base, uint8 bd, uint8 qd) = factory.markets(id);
        assertEq(base, address(0x999));
        assertEq(bd, 9);
        assertEq(qd, 6);
    }
}
