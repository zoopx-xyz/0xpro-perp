// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarketFactory} from "../src/core/MarketFactory.sol";
import {Constants} from "../lib/Constants.sol";

contract MarketFactoryExtendedTest is Test {
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

    function testInitializeGrantsAdminRole() public {
        // Deploy a fresh instance to test initialization
        MarketFactory freshFactory = MarketFactory(_deployProxy(address(new MarketFactory())));
        address admin = address(0x456);

        freshFactory.initialize(admin);

        // Check that admin role was granted correctly
        assertTrue(freshFactory.hasRole(Constants.DEFAULT_ADMIN, admin));
    }

    function testInitializeCanOnlyBeCalledOnce() public {
        // Try to initialize again - should revert
        vm.expectRevert();
        factory.initialize(address(0x789));
    }

    function testCreateMarketWithDifferentParams() public {
        bytes32 marketId = keccak256("AVAX-PERP");
        MarketFactory.MarketParams memory params =
            MarketFactory.MarketParams({base: address(0xABC), baseDecimals: 6, quoteDecimals: 8});

        vm.expectEmit(true, true, true, true);
        emit MarketFactory.MarketCreated(marketId, address(0xABC), 6, 8);

        factory.createMarket(marketId, address(0xABC), 6, 8, params);

        (address base, uint8 bd, uint8 qd) = factory.markets(marketId);
        assertEq(base, address(0xABC));
        assertEq(bd, 6);
        assertEq(qd, 8);
    }

    function testCreateMarketOverwrite() public {
        bytes32 marketId = keccak256("DOT-PERP");

        // Create first market
        MarketFactory.MarketParams memory params1 =
            MarketFactory.MarketParams({base: address(0x111), baseDecimals: 10, quoteDecimals: 18});
        factory.createMarket(marketId, address(0x111), 10, 18, params1);

        // Overwrite with different market
        MarketFactory.MarketParams memory params2 =
            MarketFactory.MarketParams({base: address(0x222), baseDecimals: 12, quoteDecimals: 6});

        vm.expectEmit(true, true, true, true);
        emit MarketFactory.MarketCreated(marketId, address(0x222), 12, 6);

        factory.createMarket(marketId, address(0x222), 12, 6, params2);

        // Verify the market was overwritten
        (address base, uint8 bd, uint8 qd) = factory.markets(marketId);
        assertEq(base, address(0x222));
        assertEq(bd, 12);
        assertEq(qd, 6);
    }

    function testConstructorDisablesInitializers() public {
        // The constructor should have disabled initializers
        MarketFactory impl = new MarketFactory();

        // Trying to initialize implementation directly should revert
        vm.expectRevert();
        impl.initialize(address(0x123));
    }
}
