// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StorkPriceAdapter} from "../src/oracle/StorkPriceAdapter.sol";
import {IStork} from "../src/oracle/external/stork/IStork.sol";
import {StorkStructs} from "../src/oracle/external/stork/StorkStructs.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract MockStorkExtended is IStork {
    bool public shouldRevert;
    int256 public value;
    uint64 public timestamp;

    function set(int256 v, uint64 t, bool rv) external {
        value = v;
        timestamp = t;
        shouldRevert = rv;
    }

    function getTemporalNumericValueV1(bytes32) external view returns (StorkStructs.TemporalNumericValue memory) {
        if (shouldRevert) revert("stale");
        return StorkStructs.TemporalNumericValue({value: value, timestamp: timestamp});
    }

    function getTemporalNumericValueUnsafeV1(bytes32)
        external
        view
        returns (StorkStructs.TemporalNumericValue memory)
    {
        if (shouldRevert) revert("stale");
        return StorkStructs.TemporalNumericValue({value: value, timestamp: timestamp});
    }
}

contract StorkPriceAdapterBranchTest is Test {
    StorkPriceAdapter adapter;
    MockStorkExtended stork;
    address admin = address(this);
    address asset1 = address(0xA1);
    address asset2 = address(0xA2);

    function setUp() public {
        stork = new MockStorkExtended();
        StorkPriceAdapter impl = new StorkPriceAdapter();
        adapter = StorkPriceAdapter(
            address(
                new ERC1967Proxy(
                    address(impl), abi.encodeWithSelector(StorkPriceAdapter.initialize.selector, admin, address(stork))
                )
            )
        );
    }

    function testInitializeGrantsAdminRole() public {
        // Deploy a fresh instance to test initialization
        StorkPriceAdapter impl = new StorkPriceAdapter();
        address newAdmin = address(0x999);
        StorkPriceAdapter freshAdapter = StorkPriceAdapter(
            address(
                new ERC1967Proxy(
                    address(impl),
                    abi.encodeWithSelector(StorkPriceAdapter.initialize.selector, newAdmin, address(stork))
                )
            )
        );

        assertTrue(freshAdapter.hasRole(Constants.DEFAULT_ADMIN, newAdmin));
        assertEq(address(freshAdapter.stork()), address(stork));
    }

    function testDecimals18NoNormalization() public {
        // Test dec == 18 branch where no normalization is needed
        bytes32 fid = keccak256("ETH");
        adapter.setFeed(asset1, fid, 18);
        stork.set(3000_000000000000000000, 200, false); // 3000 * 1e18

        (uint256 p, uint64 ts, bool stale) = adapter.getPrice(asset1);
        assertEq(p, 3000e18);
        assertEq(ts, 200);
        assertFalse(stale);
    }

    function testDecimalsGreaterThan18() public {
        // Test dec > 18 branch where we divide
        bytes32 fid = keccak256("PRECISION");
        adapter.setFeed(asset1, fid, 24); // 6 more decimals than 18
        stork.set(5000_000000_000000000000_000000, 300, false); // 5000 * 1e24

        (uint256 p, uint64 ts, bool stale) = adapter.getPrice(asset1);
        assertEq(p, 5000e18); // Should be divided by 1e6
        assertEq(ts, 300);
        assertFalse(stale);
    }

    function testDecimalsLessThan18() public {
        // Test dec < 18 branch where we multiply
        bytes32 fid = keccak256("BTC");
        adapter.setFeed(asset1, fid, 8); // 10 less decimals than 18
        stork.set(60000_00000000, 400, false); // 60,000 * 1e8

        (uint256 p, uint64 ts, bool stale) = adapter.getPrice(asset1);
        assertEq(p, 60000e18); // Should be multiplied by 1e10
        assertEq(ts, 400);
        assertFalse(stale);
    }

    function testZeroPrice() public {
        bytes32 fid = keccak256("ZERO");
        adapter.setFeed(asset1, fid, 18);
        stork.set(0, 500, false); // Zero price but not stale

        (uint256 p, uint64 ts, bool stale) = adapter.getPrice(asset1);
        assertEq(p, 0);
        assertEq(ts, 500);
        assertFalse(stale);
    }

    function testMultipleAssetFeeds() public {
        bytes32 fid1 = keccak256("ASSET1");
        bytes32 fid2 = keccak256("ASSET2");

        adapter.setFeed(asset1, fid1, 8);
        adapter.setFeed(asset2, fid2, 18);

        // Check that feeds are independent
        assertEq(adapter.feedIdOf(asset1), fid1);
        assertEq(adapter.feedIdOf(asset2), fid2);
        assertEq(adapter.feedDecimals(fid1), 8);
        assertEq(adapter.feedDecimals(fid2), 18);
    }

    function testSetFeedOverwrite() public {
        bytes32 fid1 = keccak256("FEED1");
        bytes32 fid2 = keccak256("FEED2");

        // Set initial feed
        vm.expectEmit(true, true, false, true);
        emit StorkPriceAdapter.FeedSet(asset1, fid1, 8);
        adapter.setFeed(asset1, fid1, 8);

        // Overwrite with new feed
        vm.expectEmit(true, true, false, true);
        emit StorkPriceAdapter.FeedSet(asset1, fid2, 18);
        adapter.setFeed(asset1, fid2, 18);

        // Verify overwrite
        assertEq(adapter.feedIdOf(asset1), fid2);
        assertEq(adapter.feedDecimals(fid2), 18);
    }

    function testOnlyAdminCanSetStork() public {
        address newStork = address(0xBEEF);

        // Should work for admin
        adapter.setStork(newStork);
        assertEq(address(adapter.stork()), newStork);

        // Should fail for non-admin
        vm.prank(address(0xBAD));
        vm.expectRevert();
        adapter.setStork(address(0xCAFE));
    }

    function testOnlyAdminCanSetFeed() public {
        bytes32 fid = keccak256("ADMIN_ONLY");

        // Should fail for non-admin
        vm.prank(address(0xBAD));
        vm.expectRevert();
        adapter.setFeed(asset1, fid, 18);
    }

    function testConstructorDisablesInitializers() public {
        StorkPriceAdapter impl = new StorkPriceAdapter();

        // Trying to initialize implementation directly should revert
        vm.expectRevert();
        impl.initialize(address(0x123), address(stork));
    }

    function testInitializeTwiceReverts() public {
        // Creating a fresh adapter should not allow double initialization
        StorkPriceAdapter impl = new StorkPriceAdapter();
        StorkPriceAdapter freshAdapter = StorkPriceAdapter(
            address(
                new ERC1967Proxy(
                    address(impl), abi.encodeWithSelector(StorkPriceAdapter.initialize.selector, admin, address(stork))
                )
            )
        );

        // Try to initialize again - should revert
        vm.expectRevert();
        freshAdapter.initialize(address(0x999), address(stork));
    }
}
