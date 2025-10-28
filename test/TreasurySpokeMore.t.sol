// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasurySpoke} from "../src/core/TreasurySpoke.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract TreasurySpokeMoreTest is Test {
    function testForwardFeesRevertsWhenZUSDNotSet() public {
        TreasurySpoke impl = new TreasurySpoke();
        TreasurySpoke treas = TreasurySpoke(address(new ERC1967Proxy(address(impl), "")));
        treas.initialize(address(this));
        treas.grantRole(Constants.FORWARDER_ROLE, address(this));
        vm.expectRevert("zUSD not set");
        treas.forwardFeesToSplitter(1, address(0xFEE));
    }

    function testReceivePenaltyOverloadNoop() public {
        TreasurySpoke impl = new TreasurySpoke();
        TreasurySpoke treas = TreasurySpoke(address(new ERC1967Proxy(address(impl), "")));
        treas.initialize(address(this));
        // call the overload that takes (token, amount); should be a no-op and not revert
        treas.receivePenalty(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), 123);
    }
}
