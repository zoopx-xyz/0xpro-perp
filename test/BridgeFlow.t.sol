// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BridgeAdapter} from "../src/bridge/BridgeAdapter.sol";
import {IBridgeAdapter} from "../src/bridge/interfaces/IBridgeAdapter.sol";
import {EscrowGateway} from "../src/satellite/EscrowGateway.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {Constants} from "../lib/Constants.sol";

contract MockPerpEngine {
    int256 public upnl;
    uint256 public mmr;

    function setUPnL(int256 v) external { upnl = v; }
    function setMMR(uint256 v) external { mmr = v; }

    function getUnrealizedPnlZ(address) external view returns (int256) { return upnl; }
    function computeAccountMMRZ(address) external view returns (uint256) { return mmr; }
}

contract BridgeFlowTest is Test {
    MarginVaultV2 vault;
    CollateralManager cm;
    OracleRouter orac;
    SignedPriceOracle spo;
    BridgeAdapter adapter;
    EscrowGateway gateway;
    MockERC20 usdc;
    MockPerpEngine mockEngine;

    address user = address(0xBEEF);

    function setUp() public {
        // Deploy proxies for upgradeable contracts
        cm = CollateralManager(_deployProxy(address(new CollateralManager())));
        orac = OracleRouter(_deployProxy(address(new OracleRouter())));
        spo = SignedPriceOracle(_deployProxy(address(new SignedPriceOracle())));
        vault = MarginVaultV2(_deployProxy(address(new MarginVaultV2())));
        adapter = BridgeAdapter(_deployProxy(address(new BridgeAdapter())));
        gateway = EscrowGateway(_deployProxy(address(new EscrowGateway())));

        // Initialize
        cm.initialize(address(this), address(orac));
        orac.initialize(address(this));
        spo.initialize(address(this), address(0), 300);
        vault.initialize(address(this), address(cm));
        adapter.initialize(address(this), address(vault));
        gateway.initialize(address(this));

        // Token and pricing setup
        usdc = new MockERC20("mockUSDC", "mUSDC", 6);
        orac.registerAdapter(address(usdc), address(spo));
        cm.setAssetConfig(address(usdc), true, 10000, address(orac), 6);
        spo.setPrice(address(usdc), 1e18, uint64(block.timestamp));

        // Grant adapter permission on the vault to mint/burn credit
        vault.grantRole(Constants.BRIDGE_ROLE, address(adapter));

        // Mark asset as bridged-only to enforce withdraws via bridge flow
        vault.setBridgedOnlyAsset(address(usdc), true);

        // Setup mock perp engine to enable equity guards if needed
        mockEngine = new MockPerpEngine();
        vault.setDeps(address(0x01), address(orac), address(mockEngine)); // riskConfig != 0 enables equity check path
    }

    function _deployProxy(address impl) internal returns (address) {
        bytes memory code = abi.encodePacked(
            hex"3d602d80600a3d3981f3", hex"363d3d373d3d3d363d73", bytes20(impl), hex"5af43d82803e903d91602b57fd5bf3"
        );
        address proxy;
        assembly {
            proxy := create(0, add(code, 0x20), mload(code))
        }
        require(proxy != address(0), "proxy fail");
        return proxy;
    }

    function testBridgeCreditIncreasesVaultBalanceAndEmits() public {
        uint256 amount = 1_000_000; // 1 USDC (6 decimals)
        bytes32 depositId = keccak256("dep1");
        bytes32 srcChain = keccak256("BASE_TEST");

        // Expect vault CreditBridged event followed by adapter BridgeCreditReceived
        vm.expectEmit(true, true, true, true, address(vault));
        emit MarginVaultV2.CreditBridged(user, address(usdc), amount, depositId);
        vm.expectEmit(true, true, true, true, address(adapter));
        emit IBridgeAdapter.BridgeCreditReceived(user, address(usdc), amount, depositId, srcChain);

        adapter.creditFromMessage(user, address(usdc), amount, depositId, srcChain);

        uint128 bal = vault.getCrossBalance(user, address(usdc));
        assertEq(bal, amount);
    }

    function testInitiateWithdrawalDebitsAndEmits() public {
        // Pre-credit user via message
        uint256 amount = 2_000_000; // 2 USDC
        bytes32 depositId = keccak256("dep2");
        adapter.creditFromMessage(user, address(usdc), amount, depositId, keccak256("SRC"));
        assertEq(vault.getCrossBalance(user, address(usdc)), uint128(amount));

        // User initiates withdrawal
        bytes32 dstChain = keccak256("OP_TEST");
    vm.prank(user);
    // We don't know withdrawalId ahead of time; don't check the 3rd indexed topic (withdrawalId)
    vm.expectEmit(true, true, false, true, address(adapter));
    emit IBridgeAdapter.BridgeWithdrawalInitiated(user, address(usdc), amount, bytes32(0), dstChain);
        bytes32 wid = adapter.initiateWithdrawal(address(usdc), amount, dstChain);

        // Balance reduced to zero
        assertEq(vault.getCrossBalance(user, address(usdc)), uint128(0));
        assertTrue(wid != bytes32(0));
    }

    function testVaultDirectWithdrawRevertsForBridgedOnlyAsset() public {
        // Credit user via bridge first
        adapter.creditFromMessage(user, address(usdc), 500_000, keccak256("dep3"), keccak256("SRC"));
        vm.prank(user);
        vm.expectRevert(bytes("bridged-only: use bridge withdraw"));
        vault.withdraw(address(usdc), 100_000, false, bytes32(0));
    }

    function testBurnCreditEquityGuardRevertsWhenMMRTooHigh() public {
        // Credit 1 USDC, equity ~ 1e18 zUSD
        adapter.creditFromMessage(user, address(usdc), 1_000_000, keccak256("dep4"), keccak256("SRC"));
        // Set MMR to 2e18 so eq < mmr and debit should revert
        mockEngine.setMMR(2e18);
        mockEngine.setUPnL(0);
        vm.prank(user);
        vm.expectRevert(bytes("MarginVault: insufficient equity after debit"));
        adapter.initiateWithdrawal(address(usdc), 100_000, keccak256("DST"));
    }

    function testEscrowGatewayDepositAndRelease() public {
        // Mark asset supported on satellite gateway
        gateway.setSupportedAsset(address(usdc), true);
        // Mint and approve tokens for user
        usdc.mint(user, 1_000_000);
        vm.prank(user);
        usdc.approve(address(gateway), type(uint256).max);

        // Deposit emits event and holds funds
    vm.prank(user);
    // We don't know depositId ahead of time; don't check the 3rd indexed topic (depositId)
    vm.expectEmit(true, true, false, true, address(gateway));
    emit EscrowGateway.DepositEscrowed(user, address(usdc), 500_000, bytes32(0), keccak256("BASE"));
        gateway.deposit(address(usdc), 500_000, keccak256("BASE"));
        assertEq(usdc.balanceOf(address(gateway)), 500_000);

        // Complete withdrawal releases funds to user (simulating verified burn)
        vm.expectEmit(true, true, true, true, address(gateway));
        emit EscrowGateway.WithdrawalReleased(user, address(usdc), 200_000, keccak256("wid1"));
        gateway.completeWithdrawal(user, address(usdc), 200_000, keccak256("wid1"));
        assertEq(usdc.balanceOf(user), 700_000); // 1,000,000 minted - 500,000 deposited + 200,000 released
        assertEq(usdc.balanceOf(address(gateway)), 300_000);
    }
}
