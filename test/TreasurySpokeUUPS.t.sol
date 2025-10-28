// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TreasurySpoke} from "../src/core/TreasurySpoke.sol";
import {MockzUSD} from "../src/tokens/MockzUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract TreasurySpokeUUPSTest is Test {
    TreasurySpoke proxyTreasury;
    TreasurySpoke impl;
    MockzUSD z;
    address admin = address(this);

    function setUp() public {
        z = new MockzUSD();
        impl = new TreasurySpoke();
        bytes memory initData = abi.encodeWithSelector(TreasurySpoke.initialize.selector, admin);
        proxyTreasury = TreasurySpoke(address(new ERC1967Proxy(address(impl), initData)));
        proxyTreasury.setZUsdToken(address(z));
    }

    function testImplementationInitializeReverts() public {
        vm.expectRevert();
        impl.initialize(admin);
    }

    function testDepositFromBotNoOpAndUpgrade() public {
        // touch depositFromBot
        proxyTreasury.depositFromBot(address(z), 123);
        // upgrade path
        TreasurySpoke newImpl = new TreasurySpoke();
        proxyTreasury.upgradeTo(address(newImpl));
        // sanity: forward fees still works with role
        proxyTreasury.grantRole(Constants.FORWARDER_ROLE, address(this));
        z.mint(address(proxyTreasury), 100);
        proxyTreasury.forwardFeesToSplitter(50, address(0xFEE));
        assertEq(z.balanceOf(address(0xFEE)), 50);
    }
}
