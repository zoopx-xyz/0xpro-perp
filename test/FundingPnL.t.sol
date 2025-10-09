// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Constants} from "../lib/Constants.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {MockzUSD} from "../src/tokens/MockzUSD.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {PerpEngine} from "../src/core/PerpEngine.sol";
import {RiskConfig} from "../src/core/RiskConfig.sol";
import {TreasurySpoke} from "../src/core/TreasurySpoke.sol";
import {FeeSplitterSpoke} from "../src/core/FeeSplitterSpoke.sol";
import {FundingModule} from "../src/core/FundingModule.sol";
import {IPerpEngine} from "../src/core/interfaces/IPerpEngine.sol";

contract FundingPnLTest is Test {
    MockzUSD public zUsd;
    MockERC20 public mockBTC;
    CollateralManager public cm;
    SignedPriceOracle public spo;
    OracleRouter public oracleRouter;
    MarginVaultV2 public vault;
    PerpEngine public perpEngine;
    RiskConfig public riskConfig;
    TreasurySpoke public treasury;
    FeeSplitterSpoke public feeSplitter;
    FundingModule public fundingModule;

    address public admin = address(0x1);
    address public user = address(0x2);
    address public keeper = address(0x3);

    bytes32 public constant BTC_PERP = keccak256("BTC-PERP");

    function setUp() public {
        vm.startPrank(admin);

        // Deploy tokens
        zUsd = new MockzUSD();
        mockBTC = new MockERC20("mockBTC", "mBTC", 8);

        // Deploy implementations
        CollateralManager cmImpl = new CollateralManager();
        SignedPriceOracle spoImpl = new SignedPriceOracle();
        OracleRouter orImpl = new OracleRouter();
        MarginVaultV2 mvImpl = new MarginVaultV2();
        PerpEngine peImpl = new PerpEngine();
        RiskConfig rcImpl = new RiskConfig();
        TreasurySpoke tsImpl = new TreasurySpoke();
        FeeSplitterSpoke fsImpl = new FeeSplitterSpoke();
        FundingModule fmImpl = new FundingModule();

        // Deploy proxies
        cm = CollateralManager(address(new ERC1967Proxy(address(cmImpl), "")));
        spo = SignedPriceOracle(address(new ERC1967Proxy(address(spoImpl), "")));
        oracleRouter = OracleRouter(address(new ERC1967Proxy(address(orImpl), "")));
        vault = MarginVaultV2(address(new ERC1967Proxy(address(mvImpl), "")));
        perpEngine = PerpEngine(address(new ERC1967Proxy(address(peImpl), "")));
        riskConfig = RiskConfig(address(new ERC1967Proxy(address(rcImpl), "")));
        treasury = TreasurySpoke(address(new ERC1967Proxy(address(tsImpl), "")));
        feeSplitter = FeeSplitterSpoke(address(new ERC1967Proxy(address(fsImpl), "")));
        fundingModule = FundingModule(address(new ERC1967Proxy(address(fmImpl), "")));

        // Initialize
        spo.initialize(admin, address(0), 300);
        oracleRouter.initialize(admin);
        cm.initialize(admin, address(oracleRouter));
        vault.initialize(admin, address(cm));
        perpEngine.initialize(admin, address(vault));
        riskConfig.initialize(admin);
        treasury.initialize(admin);
        feeSplitter.initialize(admin);
        fundingModule.initialize(admin);

        // Wire dependencies
        perpEngine.setDeps(
            address(riskConfig),
            address(oracleRouter),
            address(cm),
            address(treasury),
            address(feeSplitter),
            address(fundingModule),
            address(zUsd)
        );
        vault.setDeps(address(riskConfig), address(oracleRouter), address(perpEngine));

        // Configure oracle and market
        oracleRouter.registerAdapter(address(mockBTC), address(spo));
        oracleRouter.registerAdapter(address(zUsd), address(spo));
        cm.setAssetConfig(address(mockBTC), true, 5000, address(oracleRouter), 8);
        cm.setAssetConfig(address(zUsd), true, 10000, address(oracleRouter), 6);
        spo.setPrice(address(mockBTC), 60000e18, uint64(block.timestamp));
        spo.setPrice(address(zUsd), 1e18, uint64(block.timestamp));

        // Configure fee splitting
        treasury.setZUsdToken(address(zUsd));
        feeSplitter.setZUsdToken(address(zUsd));
        feeSplitter.setRecipients(admin, admin, admin, admin);

        // Setup market
        RiskConfig.MarketRisk memory risk = RiskConfig.MarketRisk({
            imrBps: 1000, // 10%
            mmrBps: 500, // 5%
            liqPenaltyBps: 100, // 1%
            makerFeeBps: 5,
            takerFeeBps: 10,
            maxLev: 10
        });
        riskConfig.setMarketRisk(BTC_PERP, risk);
        perpEngine.registerMarket(BTC_PERP, address(mockBTC), 8);

        // Grant roles
        vault.grantRole(Constants.ENGINE, address(perpEngine));
        treasury.grantRole(Constants.FORWARDER_ROLE, address(perpEngine));
        perpEngine.grantRole(Constants.KEEPER, keeper);
        fundingModule.grantRole(Constants.KEEPER, keeper);

        // Mint tokens
        zUsd.mint(admin, 1_000_000 * 1e6);
        zUsd.mint(address(treasury), 1_000_000 * 1e6);
        zUsd.mint(user, 100_000 * 1e6);
        mockBTC.mint(user, 100 * 1e8);

        // User deposits zUSD to vault for margin
        vm.startPrank(user);
        zUsd.approve(address(vault), type(uint256).max);
        vault.deposit(address(zUsd), 50_000 * 1e6, false, bytes32(0));
        vm.stopPrank();

        vm.stopPrank();
    }

    function testFundingIndexUpdate() public {
        // Initial funding index should be 0
        int128 initialIndex = fundingModule.getFundingIndex(BTC_PERP);
        assertEq(initialIndex, 0);

        // Keeper updates funding index
        int128 fundingDelta = 1000; // Some funding rate

        vm.prank(keeper);
        vm.expectEmit(true, false, false, true);
        emit FundingUpdated(BTC_PERP, fundingDelta, fundingDelta); // newIndex, rate
        fundingModule.updateFundingIndex(BTC_PERP, fundingDelta);

        // Check updated index
        int128 updatedIndex = fundingModule.getFundingIndex(BTC_PERP);
        assertEq(updatedIndex, fundingDelta);

        // Update again
        int128 secondDelta = 500;
        vm.prank(keeper);
        fundingModule.updateFundingIndex(BTC_PERP, secondDelta);

        int128 finalIndex = fundingModule.getFundingIndex(BTC_PERP);
        assertEq(finalIndex, fundingDelta + secondDelta);
    }

    function testOnlyKeeperCanUpdateFunding() public {
        // Non-keeper cannot update funding
        vm.prank(user);
        vm.expectRevert();
        fundingModule.updateFundingIndex(BTC_PERP, 1000);
    }

    function testFundingPnLIntegration() public {
        // Create a long position
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);

        int256 position = perpEngine.getPosition(user, BTC_PERP);
        assertGt(position, 0);

        // Check initial PnL (without funding)
        int256 initialPnL = perpEngine.getUnrealizedPnlZ(user);
        int256 initialPnLWithFunding = perpEngine.getUnrealizedPnlZWithFunding(user);

        // Initially, both should be similar (funding index starts at 0)
        assertEq(initialPnL, initialPnLWithFunding);

        // Keeper updates funding index (positive funding = longs pay shorts)
        int128 positiveFunding = 1e15; // 0.001 in 1e18 scaling

        vm.prank(keeper);
        fundingModule.updateFundingIndex(BTC_PERP, positiveFunding);

        // Check PnL after funding update
        int256 pnlAfterFunding = perpEngine.getUnrealizedPnlZWithFunding(user);

        // PnL with funding should be different now
        // For a long position with positive funding, PnL should decrease (longs pay)
        assertLt(pnlAfterFunding, initialPnLWithFunding);

        // Update funding again with negative funding (shorts pay longs)
        int128 negativeFunding = -2e15; // -0.002 in 1e18 scaling

        vm.prank(keeper);
        fundingModule.updateFundingIndex(BTC_PERP, negativeFunding);

        int256 finalPnLWithFunding = perpEngine.getUnrealizedPnlZWithFunding(user);

        // Now PnL should be higher than after positive funding (longs receive from shorts)
        assertGt(finalPnLWithFunding, pnlAfterFunding);
    }

    function testFundingIndexSnapshotOnRecordFill() public {
        // Set initial funding index
        vm.prank(keeper);
        fundingModule.updateFundingIndex(BTC_PERP, 1000);

        // Create a fill
        IPerpEngine.Fill memory fill = IPerpEngine.Fill({
            fillId: bytes32("test_fill"),
            account: user,
            marketId: BTC_PERP,
            isBuy: true,
            size: 1e8, // 1 BTC
            priceZ: 60000 * 1e18,
            feeZ: 1000,
            fundingZ: 0,
            ts: uint64(block.timestamp),
            orderDigest: keccak256("test_fill")
        });

        vm.prank(admin); // Admin has KEEPER role
        perpEngine.recordFill(fill);

        // Check that position funding index was updated
        int128 positionFundingIndex = perpEngine.positionFundingIndex(user, BTC_PERP);
        assertEq(positionFundingIndex, 1000);

        // Update funding again
        vm.prank(keeper);
        fundingModule.updateFundingIndex(BTC_PERP, 500);

        // Create another fill to update the snapshot
        IPerpEngine.Fill memory fill2 = IPerpEngine.Fill({
            fillId: bytes32("test_fill_2"),
            account: user,
            marketId: BTC_PERP,
            isBuy: true,
            size: 5e7, // 0.5 BTC
            priceZ: 60000 * 1e18,
            feeZ: 500,
            fundingZ: 0,
            ts: uint64(block.timestamp),
            orderDigest: keccak256("test_fill_2")
        });

        vm.prank(admin);
        perpEngine.recordFill(fill2);

        // Position funding index should now be updated to latest
        int128 updatedPositionFundingIndex = perpEngine.positionFundingIndex(user, BTC_PERP);
        assertEq(updatedPositionFundingIndex, 1500); // 1000 + 500
    }

    function testFundingPnLWithPriceChange() public {
        // Create position at current price
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);

        // Update funding index
        vm.prank(keeper);
        fundingModule.updateFundingIndex(BTC_PERP, 1e15); // Positive funding

        // Change BTC price
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 70000e18, uint64(block.timestamp)); // Price up

        // Check both PnL calculations
        int256 pnlWithoutFunding = perpEngine.getUnrealizedPnlZ(user);
        int256 pnlWithFunding = perpEngine.getUnrealizedPnlZWithFunding(user);

        // Both should show profit from price increase, but funding PnL should be lower due to funding cost
        assertGt(pnlWithoutFunding, 0); // Profit from price increase
        assertGt(pnlWithFunding, 0); // Still profit, but less
        assertLt(pnlWithFunding, pnlWithoutFunding); // Funding reduces PnL for longs when positive
    }

    // Event for testing
    event FundingUpdated(bytes32 indexed marketId, int128 index, int128 rate);
}
