// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";

contract OracleTest is Test {
    SignedPriceOracle spo;

    function setUp() public {
        spo = SignedPriceOracle(_deployProxy(address(new SignedPriceOracle())));
        spo.initialize(address(this), address(0), 300);
    }

    function _deployProxy(address impl) internal returns (address) {
        bytes memory code = abi.encodePacked(hex"3d602d80600a3d3981f3", hex"363d3d373d3d3d363d73", bytes20(impl), hex"5af43d82803e903d91602b57fd5bf3");
        address proxy;
        assembly { proxy := create(0, add(code, 0x20), mload(code)) }
        require(proxy != address(0), "proxy fail");
        return proxy;
    }

    function testSetPriceKeeper() public {
        spo.setPrice(address(0xBEEF), 123e18, uint64(block.timestamp));
        (uint256 p, , bool stale) = spo.getPrice(address(0xBEEF));
        assertEq(p, 123e18);
        assertFalse(stale);
    }
}
