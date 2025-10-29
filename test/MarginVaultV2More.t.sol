// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract MockCollateralManager {
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

contract MockEngineMV2 {
    uint256 public mmr;

    function set(uint256 v) external {
        mmr = v;
    }

    function computeAccountMMRZ(address) external view returns (uint256) {
        return mmr;
    }

    function getUnrealizedPnlZ(address) external pure returns (int256) {
        return 0;
    }
}

contract MarginVaultV2MoreTest is Test {
    MarginVaultV2 vault;
    MarginVaultV2 impl;
    MockERC20 token;
    address admin = address(this);
    address user = address(0xBEEF);
    bytes32 MARKET = keccak256("ETH-PERP");

    function setUp() public {
        token = new MockERC20("TKN", "TKN", 18);
        impl = new MarginVaultV2();
        MockCollateralManager cm = new MockCollateralManager();
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

    function _depositCross(address who, uint256 amount) internal {
        vm.prank(who);
        vault.deposit(address(token), amount, false, 0);
    }

    function _depositIsolated(address who, uint256 amount) internal {
        vm.prank(who);
        vault.deposit(address(token), amount, true, MARKET);
    }

    function testUnpauseFunctionCovered() public {
        vault.pause();
        vault.unpause();
        _depositCross(user, 1 ether);
        assertEq(vault.getCrossBalance(user, address(token)), 1 ether);
    }

    function testWithdrawIsolatedAndCrossPaths() public {
        _depositCross(user, 5 ether);
        _depositIsolated(user, 3 ether);
        // withdraw isolated
        vm.prank(user);
        vault.withdraw(address(token), 1 ether, true, MARKET);
        // withdraw cross
        vm.prank(user);
        vault.withdraw(address(token), 2 ether, false, 0);
    }

    function testWithdrawInsufficientRevertsBothPaths() public {
        _depositCross(user, 1 ether);
        // cross insufficient
        vm.prank(user);
        vm.expectRevert(bytes("insufficient"));
        vault.withdraw(address(token), 2 ether, false, 0);
        // isolated insufficient
        _depositIsolated(user, 0.5 ether);
        vm.prank(user);
        vm.expectRevert(bytes("insufficient"));
        vault.withdraw(address(token), 1 ether, true, MARKET);
    }

    function testWithdrawBridgedOnlyReverts() public {
        vault.setBridgedOnlyAsset(address(token), true);
        _depositCross(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(bytes("bridged-only: use bridge withdraw"));
        vault.withdraw(address(token), 0.1 ether, false, 0);
    }

    function testHandlePostLiquidationReducesReserved() public {
        // simulate reserve then release via post liquidation
        _depositCross(user, 10 ether);
        vault.reserve(user, address(token), 1 ether, false, 0);
        uint256 beforeZ = vault.reservedZ(user);
        assertGt(beforeZ, 0);
        vault.handlePostLiquidation(user, beforeZ);
        assertEq(vault.reservedZ(user), 0);
    }

    function testUpgradeByAdminSucceeds() public {
        MarginVaultV2 newImpl = new MarginVaultV2();
        vault.upgradeTo(address(newImpl));
        // still functional
        _depositCross(user, 0.5 ether);
        assertEq(vault.getCrossBalance(user, address(token)), 0.5 ether);
    }

    function testSetDepsWiresContracts() public {
        // set dependencies and verify they are stored
        address rc = address(0x1001);
        address or = address(0x2002);
        address pe = address(0x3003);
        vault.setDeps(rc, or, pe);
        // read via public getters
        assertEq(address(vault.riskConfig()), rc);
        assertEq(address(vault.oracleRouter()), or);
        assertEq(address(vault.perpEngine()), pe);
    }

    function testWithdrawEquityGuardRevertsWithHighMMR() public {
        // Wire a mock engine with high MMR and nonzero riskConfig to enable guard
        MockEngineMV2 eng = new MockEngineMV2();
        eng.set(1000 ether);
        vault.setDeps(address(0xABCD), address(0xDCBA), address(eng));
        // Deposit some balance
        _depositCross(user, 10 ether);
        // Attempt withdraw should revert on insufficient equity (10 < 1000)
        vm.prank(user);
        vm.expectRevert(bytes("MarginVault: insufficient equity after withdraw"));
        vault.withdraw(address(token), 1 ether, false, 0);
    }

    function testSetBridgedOnlyAssetToggle() public {
        // toggling bridged-only flag should update mapping
        vault.setBridgedOnlyAsset(address(token), true);
        vm.prank(user);
        vm.expectRevert(bytes("bridged-only: use bridge withdraw"));
        vault.withdraw(address(token), 1, false, 0);
        // turn off and withdraw succeeds after deposit
        vault.setBridgedOnlyAsset(address(token), false);
        _depositCross(user, 2 ether);
        vm.prank(user);
        vault.withdraw(address(token), 1 ether, false, 0);
    }

    function testMintCreditAmountZeroReverts() public {
        vm.expectRevert(bytes("amount=0"));
        vault.mintCreditFromBridge(user, address(token), 0, keccak256("dep"));
    }

    function testBurnCreditUserZeroReverts() public {
        vm.expectRevert(bytes("user=0"));
        vault.burnCreditForBridge(address(0), address(token), 1, keccak256("wd"));
    }

    function testPenalizeInvalidToReverts() public {
        _depositCross(user, 1 ether);
        vm.expectRevert(bytes("invalid to"));
        vault.penalize(user, address(token), 1, address(0));
    }

    function testReserveAndReleaseIsolatedPaths() public {
        // deposit isolated and reserve
        _depositIsolated(user, 2 ether);
        uint256 rzBefore = vault.reservedZ(user);
        vault.reserve(user, address(token), 1 ether, true, MARKET); // isolated branch
        assertEq(vault.reservedZ(user), rzBefore + 1 ether);
        // release a small amount -> reservedZ decreases via >= branch
        vault.release(user, address(token), 0.5 ether, true, MARKET);
        // now release with a large amount to hit else branch where reservedZ[user] = 0
        vault.release(user, address(token), 10 ether, true, MARKET);
        assertEq(vault.reservedZ(user), 0);
    }

    function testBurnCreditEquityGuardRevertsWithHighMMR() public {
        // Wire a mock engine and nonzero riskConfig to enable equity guard
        MockEngineMV2 eng = new MockEngineMV2();
        eng.set(1000 ether);
        vault.setDeps(address(0xABCD), address(0xDCBA), address(eng));
        // Mint some credit and then attempt to burn, which should fail due to high MMR
        vault.mintCreditFromBridge(user, address(token), 10 ether, keccak256("depEq"));
        vm.expectRevert(bytes("MarginVault: insufficient equity after debit"));
        vault.burnCreditForBridge(user, address(token), 1 ether, keccak256("wdEq"));
    }
}
