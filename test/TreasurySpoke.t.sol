// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasurySpoke} from "../src/core/TreasurySpoke.sol";
import {MockzUSD} from "../src/tokens/MockzUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract TreasurySpokeTest is Test {
    TreasurySpoke treas;
    MockzUSD z;
    address admin = address(this);
    address treasurer = address(0x123);
    address splitter = address(0x456);

    function setUp() public {
        z = new MockzUSD();
        TreasurySpoke impl = new TreasurySpoke();
        treas = TreasurySpoke(address(new ERC1967Proxy(address(impl), "")));
        treas.initialize(admin);
        treas.grantRole(Constants.TREASURER, treasurer);
        treas.setZUsdToken(address(z));
    }

    function testBalanceAndSweep() public {
        // fund
        z.mint(address(treas), 1000e6);
        assertEq(treas.balanceOf(address(z)), 1000e6);

        // only treasurer can sweep
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        treas.sweepToHub(address(z), 10e6, address(0xBEEF));
        vm.prank(treasurer);
        treas.sweepToHub(address(z), 10e6, address(0xBEEF));
        assertEq(z.balanceOf(address(0xBEEF)), 10e6);
    }

    function testForwardFeesToSplitter() public {
        z.mint(address(treas), 100e6);
        // must have FORWARDER_ROLE to hit parameter validation branches
        treas.grantRole(Constants.FORWARDER_ROLE, address(this));
        vm.expectRevert("invalid splitter");
        treas.forwardFeesToSplitter(10e6, address(0));
        vm.expectRevert("invalid amount");
        treas.forwardFeesToSplitter(0, splitter);
        // ok path
        treas.forwardFeesToSplitter(25e6, splitter);
        assertEq(z.balanceOf(splitter), 25e6);
    }

    function testReceivePenaltyEvents() public {
        vm.expectEmit(true, false, false, true);
        emit TreasurySpoke.PenaltyReceived(123);
        treas.receivePenalty(123);
        // overload variant should not revert
        treas.receivePenalty(address(z), 5);
    }
}
