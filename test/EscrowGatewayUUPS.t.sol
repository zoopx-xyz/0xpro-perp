// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowGateway} from "../src/satellite/EscrowGateway.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EscrowGatewayUUPSTest is Test {
    EscrowGateway gw;
    EscrowGateway impl;

    function setUp() public {
        impl = new EscrowGateway();
        gw = EscrowGateway(address(new ERC1967Proxy(address(impl), "")));
        gw.initialize(address(this));
    }

    function testUpgradeAndImplementationInitializeReverts() public {
        EscrowGateway newImpl = new EscrowGateway();
        gw.upgradeTo(address(newImpl));
        vm.expectRevert();
        newImpl.initialize(address(this));
        // still functional
        gw.setSupportedAsset(address(0xA), true);
    }
}
