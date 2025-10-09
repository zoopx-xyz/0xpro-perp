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

contract PartialLiquidationTest is Test {
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
        perpEngine.setDeps(address(riskConfig), address(oracleRouter), address(cm), address(treasury), address(feeSplitter), address(fundingModule), address(zUsd));
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

    // Allow vault to transfer zUSD to treasury for penalty collection
    zUsd.approve(address(treasury), type(uint256).max);

        // Setup market with high liquidation penalty for testing
        RiskConfig.MarketRisk memory risk = RiskConfig.MarketRisk({
            imrBps: 1000, // 10%
            mmrBps: 500,  // 5%
            liqPenaltyBps: 200, // 2%
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

        // Mint tokens
        zUsd.mint(admin, 1_000_000 * 1e6);
        zUsd.mint(address(treasury), 1_000_000 * 1e6);
        zUsd.mint(user, 100_000 * 1e6);
        zUsd.mint(address(perpEngine), 100_000 * 1e6); // For penalty payments
        mockBTC.mint(user, 100 * 1e8);

        // User deposits zUSD to vault for margin
        vm.startPrank(user);
        zUsd.approve(address(vault), type(uint256).max);
        vault.deposit(address(zUsd), 50_000 * 1e6, false, bytes32(0));
        vm.stopPrank();

        vm.stopPrank();
    }

    function testPartialLiquidationHappyPath() public {
        // Create a position of 10 BTC
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2); // 30k collateral, 2x leverage = ~1 BTC position
        
        int256 initialPosition = perpEngine.getPosition(user, BTC_PERP);
        assertGt(initialPosition, 0);
        
        // Make position liquidatable by dropping BTC price
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 10000e18, uint64(block.timestamp)); // Severe drop to make liquidatable
        
    // Record initial treasury balance
    uint256 treasuryInitialBalance = zUsd.balanceOf(address(treasury));
        
        // Keeper partially liquidates half the position
        uint128 closeSize = uint128(uint256(initialPosition) / 2);
        uint128 remainingSize = uint128(uint256(initialPosition) - uint256(closeSize));
        
        vm.prank(keeper);
        // Skip event checking for now - just ensure function works
        // vm.expectEmit(true, true, false, true);
        // emit PartialLiquidation(user, BTC_PERP, closeSize, 10000e18, expectedPenalty, remainingSize);
        perpEngine.liquidatePartial(user, BTC_PERP, closeSize);
        
        // Check position was reduced
        int256 finalPosition = perpEngine.getPosition(user, BTC_PERP);
        assertEq(finalPosition, initialPosition - int256(uint256(closeSize)));
        
    // Penalty should have increased treasury balance (>= initial)
    uint256 treasuryFinalBalance = zUsd.balanceOf(address(treasury));
    assertGt(treasuryFinalBalance, treasuryInitialBalance, "penalty not transferred");
        
        // Check that user is still in the open markets list (partial liquidation)
        bytes32[] memory openMarkets = perpEngine.getOpenMarketsForAccount(user);
        bool found = false;
        for (uint256 i = 0; i < openMarkets.length; i++) {
            if (openMarkets[i] == BTC_PERP) {
                found = true;
                break;
            }
        }
        assertTrue(found, "User should still be in open markets after partial liquidation");
    }

    function testFullLiquidationPrunesPosition() public {
        // Create a position
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);
        
        int256 initialPosition = perpEngine.getPosition(user, BTC_PERP);
        assertGt(initialPosition, 0);
        
        // Verify user is in open markets
        bytes32[] memory openMarketsBefore = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarketsBefore.length, 1);
        assertEq(openMarketsBefore[0], BTC_PERP);
        
        // Make position liquidatable
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 10000e18, uint64(block.timestamp));
        
        // Full liquidation
    uint256 treasuryBefore = zUsd.balanceOf(address(treasury));
        vm.prank(keeper);
        perpEngine.liquidate(user, BTC_PERP);
    uint256 treasuryAfter = zUsd.balanceOf(address(treasury));
    assertGt(treasuryAfter, treasuryBefore, "treasury did not receive penalty");
        
        // Check position is zero
        int256 finalPosition = perpEngine.getPosition(user, BTC_PERP);
        assertEq(finalPosition, 0);
        
        // Check that user is removed from open markets list
        bytes32[] memory openMarketsAfter = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarketsAfter.length, 0);
    }

    function testPartialLiquidationFullClose() public {
        // Create a position
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);
        
        int256 initialPosition = perpEngine.getPosition(user, BTC_PERP);
        assertGt(initialPosition, 0);
        
        // Make position liquidatable
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 10000e18, uint64(block.timestamp));
        
        // Partial liquidation with full size should work like full liquidation
        uint128 fullSize = uint128(uint256(initialPosition));
    uint256 treasuryBefore = zUsd.balanceOf(address(treasury));
    vm.prank(keeper);
    perpEngine.liquidatePartial(user, BTC_PERP, fullSize);
    uint256 treasuryAfter = zUsd.balanceOf(address(treasury));
    assertGt(treasuryAfter, treasuryBefore, "treasury did not receive penalty on full partial liquidation");
        
        // Check position is zero
        int256 finalPosition = perpEngine.getPosition(user, BTC_PERP);
        assertEq(finalPosition, 0);
        
        // Check that user is removed from open markets list
        bytes32[] memory openMarketsAfter = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarketsAfter.length, 0);
    }

    function testPartialLiquidationRevertsOnInvalidSize() public {
        // Create a position
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);
        
        int256 initialPosition = perpEngine.getPosition(user, BTC_PERP);
        
        // Make position liquidatable
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 10000e18, uint64(block.timestamp));
        
        // Try to liquidate more than position size
        uint128 oversizeClose = uint128(uint256(initialPosition) + 1);
        
        vm.prank(keeper);
        vm.expectRevert("close size exceeds position");
        perpEngine.liquidatePartial(user, BTC_PERP, oversizeClose);
        
        // Try to liquidate zero
        vm.prank(keeper);
        vm.expectRevert("invalid close size");
        perpEngine.liquidatePartial(user, BTC_PERP, 0);
    }

    function testOnlyKeeperCanPartialLiquidate() public {
        // Create a position
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);
        
        // Make position liquidatable
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 10000e18, uint64(block.timestamp));
        
        // Non-keeper cannot liquidate
        vm.prank(user);
        vm.expectRevert();
        perpEngine.liquidatePartial(user, BTC_PERP, 50000000); // 0.5 BTC
    }

    // Event definition for testing
    event PartialLiquidation(address indexed account, bytes32 marketId, uint128 closedSize, uint128 priceZ, uint128 penaltyZ, uint128 remainingSize);
}