// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {InsuranceFund} from "../src/finance/InsuranceFund.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract InsuranceFundUUPSTest is Test {
    InsuranceFund proxyFund;
    InsuranceFund impl;
    MockERC20 asset;
    address admin = address(this);

    function setUp() public {
        asset = new MockERC20("USDC", "USDC", 6);
        impl = new InsuranceFund();
        bytes memory initData =
            abi.encodeWithSelector(InsuranceFund.initialize.selector, admin, address(asset), "Insurance Fund", "iFUND");
        proxyFund = InsuranceFund(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testImplementationInitializeReverts() public {
        vm.expectRevert();
        impl.initialize(admin, address(asset), "Insurance Fund", "iFUND");
    }

    function testUpgradeByAdminSucceeds() public {
        InsuranceFund newImpl = new InsuranceFund();
        proxyFund.upgradeTo(address(newImpl));
        // basic smoke post-upgrade
        assertEq(proxyFund.decimals(), 6);
    }
}
