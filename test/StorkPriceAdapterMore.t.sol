// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StorkPriceAdapter} from "../src/oracle/StorkPriceAdapter.sol";
import {IStork} from "../src/oracle/external/stork/IStork.sol";
import {StorkStructs} from "../src/oracle/external/stork/StorkStructs.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockStork2 is IStork {
    int256 public value;
    uint64 public timestamp;

    function set(int256 v, uint64 t) external {
        value = v;
        timestamp = t;
    }

    function getTemporalNumericValueV1(bytes32) external view returns (StorkStructs.TemporalNumericValue memory) {
        return StorkStructs.TemporalNumericValue({value: value, timestamp: timestamp});
    }

    function getTemporalNumericValueUnsafeV1(bytes32)
        external
        view
        returns (StorkStructs.TemporalNumericValue memory)
    {
        return StorkStructs.TemporalNumericValue({value: value, timestamp: timestamp});
    }
}

contract StorkPriceAdapterMoreTest is Test {
    StorkPriceAdapter adapter;
    MockStork2 stork;
    address admin = address(this);
    address asset = address(0xA);

    function setUp() public {
        stork = new MockStork2();
        StorkPriceAdapter impl = new StorkPriceAdapter();
        adapter = StorkPriceAdapter(
            address(
                new ERC1967Proxy(
                    address(impl), abi.encodeWithSelector(StorkPriceAdapter.initialize.selector, admin, address(stork))
                )
            )
        );
    }

    function testSetStorkAndBadArgs() public {
        adapter.setStork(address(stork));
        // bad args: zero asset or zero feedId
        vm.expectRevert(bytes("bad args"));
        adapter.setFeed(address(0), bytes32("X"), 18);
        vm.expectRevert(bytes("bad args"));
        adapter.setFeed(asset, bytes32(0), 18);
    }
}
