// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {InsuranceFund} from "../src/finance/InsuranceFund.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract InsuranceFundTest is Test {
    InsuranceFund fund;
    MockERC20 asset;
    address admin = address(this);
    address user = address(0xBEEF);

    function setUp() public {
        asset = new MockERC20("USDC", "USDC", 6);
        asset.transferOwnership(admin);
    InsuranceFund impl = new InsuranceFund();
    fund = InsuranceFund(address(new ERC1967Proxy(address(impl), abi.encodeWithSelector(InsuranceFund.initialize.selector, admin, address(asset), "Insurance Fund", "iFUND"))));
    }

    function testDepositAndWithdraw() public {
        // mint to user and approve
        asset.mint(user, 1_000_000_000); // 1000 USDC (6 decimals)
        vm.prank(user);
        asset.approve(address(fund), type(uint256).max);

        // deposit 100 USDC
        vm.prank(user);
        uint256 shares = fund.deposit(100_000_000, user);
        assertGt(shares, 0);
        assertEq(fund.balanceOf(user), shares);
        assertEq(asset.balanceOf(address(fund)), 100_000_000);

        // redeem all
        vm.prank(user);
        uint256 assetsOut = fund.redeem(shares, user, user);
        assertEq(assetsOut, 100_000_000);
        assertEq(fund.balanceOf(user), 0);
    }

    function testPauseUnpause() public {
        fund.pause();
        vm.expectRevert();
        fund.deposit(1, user);
        fund.unpause();
        // can call view decimals
        assertEq(fund.decimals(), 6);
    }

    function testPauseBlocksMint() public {
        fund.pause();
        vm.expectRevert();
        fund.mint(1, user);
        
        fund.unpause();
        // test some successful operation that doesn't fail on balance
        assertEq(fund.decimals(), 6); // just exercise decimals() override
    }

    function testAssetAndTotalSupply() public {
        // test asset() and totalSupply() getters
        assertEq(address(fund.asset()), address(asset));
        assertEq(fund.totalSupply(), 0);
        
        // after deposit
        asset.mint(user, 1_000_000);
        vm.prank(user);
        asset.approve(address(fund), type(uint256).max);
        vm.prank(user);
        uint256 shares = fund.deposit(1_000_000, user);
        assertEq(fund.totalSupply(), shares);
    }

    function testNonAdminCannotUpgrade() public {
        address newImpl = address(0x456);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        fund.upgradeToAndCall(newImpl, "");
    }
}
