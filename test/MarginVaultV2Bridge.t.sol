// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract MockCollateralManagerMV2B {
    function assetValueInZUSD(address, uint256 amount) external pure returns (uint256) {
        return amount; // 1:1 mapping for tests
    }
    function collateralValueInZUSD(address, uint256 amount) external pure returns (uint256) {
        return amount;
    }
    function getAssets() external pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = address(0x1);
        return arr;
    }
}

contract MarginVaultV2BridgeTest is Test {
    MarginVaultV2 vault;
    MarginVaultV2 impl;
    MockERC20 token;
    address admin = address(this);
    address user = address(0xB0B);
    bytes32 MARKET = keccak256("ETH-PERP");

    function setUp() public {
        token = new MockERC20("TKN","TKN",18);
        impl = new MarginVaultV2();
        MockCollateralManagerMV2B cm = new MockCollateralManagerMV2B();
        bytes memory initData = abi.encodeWithSelector(MarginVaultV2.initialize.selector, admin, address(cm));
        vault = MarginVaultV2(address(new ERC1967Proxy(address(impl), initData)));
        // grant roles
        vault.grantRole(Constants.PAUSER_ROLE, admin);
        vault.grantRole(Constants.ENGINE, admin);
        vault.grantRole(Constants.BRIDGE_ROLE, admin);
        // fund user
        token.mint(user, 1_000 ether);
        vm.prank(user); token.approve(address(vault), type(uint256).max);
    }

    function _depositCross(address who, uint256 amount) internal {
        vm.prank(who); vault.deposit(address(token), amount, false, 0);
    }

    function _depositIsolated(address who, uint256 amount) internal {
        vm.prank(who); vault.deposit(address(token), amount, true, MARKET);
    }

    function testDepositAndWithdrawAmountZeroReverts() public {
        vm.prank(user); vm.expectRevert(bytes("amount=0"));
        vault.deposit(address(token), 0, false, 0);
        vm.prank(user); vm.expectRevert(bytes("amount=0"));
        vault.deposit(address(token), 0, true, MARKET);

        _depositCross(user, 1 ether);
        vm.prank(user); vm.expectRevert(bytes("amount=0"));
        vault.withdraw(address(token), 0, false, 0);
    }

    function testReserveThenReleaseRestoresBalanceAndReserved() public {
        _depositCross(user, 5 ether);
        // reserve 2 ether
        vault.reserve(user, address(token), 2 ether, false, 0);
        assertGt(vault.reservedZ(user), 0);
        // release back
        vault.release(user, address(token), 2 ether, false, 0);
        assertEq(vault.reservedZ(user), 0);
        assertEq(vault.getCrossBalance(user, address(token)), 5 ether);
    }

    function testMintCreditFromBridgeHappyAndReverts() public {
        // happy path
        vault.mintCreditFromBridge(user, address(token), 3 ether, keccak256("dep1"));
        assertEq(vault.getCrossBalance(user, address(token)), 3 ether);
        // user=0
        vm.expectRevert(bytes("user=0"));
        vault.mintCreditFromBridge(address(0), address(token), 1 ether, keccak256("dep2"));
        // amount=0
        vm.expectRevert(bytes("amount=0"));
        vault.mintCreditFromBridge(user, address(token), 0, keccak256("dep3"));
    }

    function testBurnCreditForBridgeHappyAndReverts() public {
        // seed with credit
        vault.mintCreditFromBridge(user, address(token), 5 ether, keccak256("depX"));
        // happy path burn
        vault.burnCreditForBridge(user, address(token), 2 ether, keccak256("wd1"));
        assertEq(vault.getCrossBalance(user, address(token)), 3 ether);
        // user=0
        vm.expectRevert(bytes("user=0"));
        vault.burnCreditForBridge(address(0), address(token), 1 ether, keccak256("wd2"));
        // amount=0
        vm.expectRevert(bytes("amount=0"));
        vault.burnCreditForBridge(user, address(token), 0, keccak256("wd3"));
        // insufficient
        vm.expectRevert(bytes("insufficient"));
        vault.burnCreditForBridge(user, address(token), 10 ether, keccak256("wd4"));
    }

    function testPenalizeHappyAndReverts() public {
        _depositCross(user, 3 ether);
        // invalid to
        vm.expectRevert(bytes("invalid to"));
        vault.penalize(user, address(token), 1 ether, address(0));
        // insufficient
        vm.expectRevert(bytes("insufficient"));
        vault.penalize(user, address(token), 10 ether, address(0xD3ad));
        // happy path
        address sink = address(0xABCD);
        uint256 before = token.balanceOf(sink);
        vault.penalize(user, address(token), 1 ether, sink);
        assertEq(token.balanceOf(sink), before + 1 ether);
        assertEq(vault.getCrossBalance(user, address(token)), 2 ether);
    }
}
