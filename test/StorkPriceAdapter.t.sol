// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StorkPriceAdapter} from "../src/oracle/StorkPriceAdapter.sol";
import {IStork} from "../src/oracle/external/stork/IStork.sol";
import {StorkStructs} from "../src/oracle/external/stork/StorkStructs.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockStork is IStork {
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

contract StorkPriceAdapterTest is Test {
    StorkPriceAdapter adapter;
    MockStork stork;
    address admin = address(this);
    address asset = address(0xA);

    function setUp() public {
        stork = new MockStork();
        StorkPriceAdapter impl = new StorkPriceAdapter();
        adapter = StorkPriceAdapter(
            address(
                new ERC1967Proxy(
                    address(impl), abi.encodeWithSelector(StorkPriceAdapter.initialize.selector, admin, address(stork))
                )
            )
        );
    }

    function testSetFeedAndGetPriceNormalization() public {
        // feed decimals 8 -> normalize to 1e18
        bytes32 fid = keccak256("BTC");
        adapter.setFeed(asset, fid, 8);
        stork.set(50000_00000000, 100, false); // 50,000 * 1e8
        (uint256 p, uint64 ts, bool stale) = adapter.getPrice(asset);
        assertEq(p, 50_000e18);
        assertEq(ts, 100);
        assertFalse(stale);
    }

    function testRevertOnNoFeed() public {
        vm.expectRevert(bytes("no feed"));
        adapter.getPrice(asset);
    }

    function testStaleReturnsZeroAndStale() public {
        bytes32 fid = keccak256("ETH");
        adapter.setFeed(asset, fid, 18);
        stork.set(0, 0, true);
        (uint256 p, uint64 ts, bool stale) = adapter.getPrice(asset);
        assertEq(p, 0);
        assertEq(ts, 0);
        assertTrue(stale);
    }

    function testNegativePriceReverts() public {
        bytes32 fid = keccak256("SOL");
        adapter.setFeed(asset, fid, 18);
        stork.set(-1, 1, false);
        vm.expectRevert(bytes("neg price"));
        adapter.getPrice(asset);
    }

    function testSetStorkUpdatesAndEmits() public {
        address newStork = address(0xDEAD);
        vm.expectEmit(true, false, false, true);
        emit StorkPriceAdapter.StorkSet(newStork);
        adapter.setStork(newStork);
    }

    function testSetFeedBadArgs() public {
        vm.expectRevert(bytes("bad args"));
        adapter.setFeed(address(0), keccak256("feed"), 18);
        vm.expectRevert(bytes("bad args"));
        adapter.setFeed(asset, bytes32(0), 18);
    }
}
