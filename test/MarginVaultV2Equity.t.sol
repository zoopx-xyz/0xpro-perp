// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract MockCMEquity {
    address public tracked;

    function setTracked(address a) external {
        tracked = a;
    }

    function assetValueInZUSD(address, uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function collateralValueInZUSD(address, uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function getAssets() external view returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = tracked;
        return arr;
    }
}

contract MarginVaultV2EquityTest is Test {
    MarginVaultV2 vault;
    MarginVaultV2 impl;
    MockERC20 token;
    MockCMEquity cm;

    address admin = address(this);
    address user = address(0xA11CE);

    function setUp() public {
        token = new MockERC20("TKN", "TKN", 18);
        impl = new MarginVaultV2();
        cm = new MockCMEquity();
        cm.setTracked(address(token));
        bytes memory initData = abi.encodeWithSelector(MarginVaultV2.initialize.selector, admin, address(cm));
        vault = MarginVaultV2(address(new ERC1967Proxy(address(impl), initData)));
        // grant roles
        vault.grantRole(Constants.PAUSER_ROLE, admin);
        vault.grantRole(Constants.ENGINE, admin);
        vault.grantRole(Constants.BRIDGE_ROLE, admin);
        // fund user
        token.mint(user, 1_000 ether);
        vm.prank(user);
        token.approve(address(vault), type(uint256).max);
    }

    function testAccountEquitySumsCrossBalancesAndRespectsReserved() public {
        // deposit 10 ether; equity should be 10e18 (1:1 in mock)
        vm.prank(user);
        vault.deposit(address(token), 10 ether, false, 0);
        int256 eq = vault.accountEquityZUSD(user);
        assertEq(eq, int256(10 ether));
        // reserve 3 ether worth -> amount is removed from cross and also counted as reservedZ
        vault.reserve(user, address(token), 3 ether, false, 0);
        int256 eq2 = vault.accountEquityZUSD(user);
        // Equity considers only cross balances, then subtracts reservedZ => 10 - 3 - 3 = 4
        assertEq(eq2, int256(4 ether));
        // release back and equity restored
        vault.release(user, address(token), 3 ether, false, 0);
        int256 eq3 = vault.accountEquityZUSD(user);
        assertEq(eq3, int256(10 ether));
    }
}
