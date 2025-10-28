// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MultiTokenFaucet} from "../src/faucet/MultiTokenFaucet.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";

contract MultiTokenFaucetTest is Test {
    MultiTokenFaucet faucet;
    MockERC20 mETH;
    MockERC20 mUSDC;
    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        faucet = new MultiTokenFaucet(owner);
        mETH = new MockERC20("mockETH", "mETH", 18);
        mUSDC = new MockERC20("mockUSDC", "mUSDC", 6);

        // seed faucet balances: owner is minter of mocks
        mETH.mint(address(faucet), 1000 ether);
        mUSDC.mint(address(faucet), 10_000_000 * 1e6);

        // configure drops and cooldown
        faucet.setCooldown(1 days);
        faucet.setDrop(address(mETH), 0.5 ether, true);
        faucet.setDrop(address(mUSDC), 2000 * 1e6, true);
    }

    function testOwnerOnlyDispense() public {
        // Non-owner cannot call dispense
        vm.prank(bob);
        vm.expectRevert();
        faucet.dispense(alice, address(mETH));
    }

    function testDispenseAndCooldown() public {
        uint256 beforeEth = mETH.balanceOf(alice);
        uint256 sent = faucet.dispense(alice, address(mETH));
        assertEq(sent, 0.5 ether, "sent amount");
        assertEq(mETH.balanceOf(alice) - beforeEth, 0.5 ether, "balance increased");

        // Attempt again immediately -> should be skipped (returns 0, no transfer)
        uint256 sent2 = faucet.dispense(alice, address(mETH));
        assertEq(sent2, 0, "cooldown skip");
        assertEq(mETH.balanceOf(alice), beforeEth + 0.5 ether, "no extra transfer");

        // Fast-forward 1 day + 1 sec
        vm.warp(block.timestamp + 1 days + 1);
        uint256 sent3 = faucet.dispense(alice, address(mETH));
        assertEq(sent3, 0.5 ether, "after cooldown");
    }

    function testDispenseMany() public {
        address[] memory toks = new address[](2);
        toks[0] = address(mETH);
        toks[1] = address(mUSDC);

        (uint256 tokensSent, uint256 totalAmount) = faucet.dispenseMany(alice, toks);
        assertEq(tokensSent, 2, "both tokens dispensed");
        assertEq(totalAmount, 0.5 ether + 2000 * 1e6, "sum of amounts");

        // immediate second call -> cooldown skips both
        (uint256 tokensSent2, uint256 totalAmount2) = faucet.dispenseMany(alice, toks);
        assertEq(tokensSent2, 0, "cooldown skip");
        assertEq(totalAmount2, 0, "no amount");
    }

    function testDisableTokenStopsDispense() public {
        // disable mUSDC
        faucet.setDrop(address(mUSDC), 2000 * 1e6, false);
        uint256 sent = faucet.dispense(alice, address(mUSDC));
        assertEq(sent, 0, "disabled => no send");
    }

    function testInsufficientBalanceReverts() public {
        // drain faucet's mETH
        uint256 bal = mETH.balanceOf(address(faucet));
        // Withdraw via admin to simulate low balance
        faucet.withdraw(address(mETH), address(this), bal);
        // Now dispensing should revert
        vm.expectRevert(bytes("faucet balance low"));
        faucet.dispense(alice, address(mETH));
    }
}
