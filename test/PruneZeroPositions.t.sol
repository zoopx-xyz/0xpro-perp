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

contract PruneZeroPositionsTest is Test {
    MockzUSD public zUsd;
    MockERC20 public mockBTC;
    MockERC20 public mockETH;
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

    bytes32 public constant BTC_PERP = keccak256("BTC-PERP");
    bytes32 public constant ETH_PERP = keccak256("ETH-PERP");

    function setUp() public {
        vm.startPrank(admin);

        // Deploy tokens
        zUsd = new MockzUSD();
        mockBTC = new MockERC20("mockBTC", "mBTC", 8);
        mockETH = new MockERC20("mockETH", "mETH", 18);

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

        // Configure oracle and markets
        oracleRouter.registerAdapter(address(mockBTC), address(spo));
        oracleRouter.registerAdapter(address(mockETH), address(spo));
        oracleRouter.registerAdapter(address(zUsd), address(spo));
        cm.setAssetConfig(address(mockBTC), true, 5000, address(oracleRouter), 8);
        cm.setAssetConfig(address(mockETH), true, 5000, address(oracleRouter), 18);
        cm.setAssetConfig(address(zUsd), true, 10000, address(oracleRouter), 6);
        spo.setPrice(address(mockBTC), 60000e18, uint64(block.timestamp));
        spo.setPrice(address(mockETH), 2000e18, uint64(block.timestamp));
        spo.setPrice(address(zUsd), 1e18, uint64(block.timestamp));

        // Configure fee splitting
        treasury.setZUsdToken(address(zUsd));
        feeSplitter.setZUsdToken(address(zUsd));
        feeSplitter.setRecipients(admin, admin, admin, admin);

        // Setup markets
        RiskConfig.MarketRisk memory risk = RiskConfig.MarketRisk({
            imrBps: 1000, // 10%
            mmrBps: 500, // 5%
            liqPenaltyBps: 100, // 1%
            makerFeeBps: 5,
            takerFeeBps: 10,
            maxLev: 10
        });
        riskConfig.setMarketRisk(BTC_PERP, risk);
        riskConfig.setMarketRisk(ETH_PERP, risk);
        perpEngine.registerMarket(BTC_PERP, address(mockBTC), 8);
        perpEngine.registerMarket(ETH_PERP, address(mockETH), 18);

        // Grant roles
        vault.grantRole(Constants.ENGINE, address(perpEngine));
        treasury.grantRole(Constants.FORWARDER_ROLE, address(perpEngine));

        // Mint tokens
        zUsd.mint(admin, 1_000_000 * 1e6);
        zUsd.mint(address(treasury), 1_000_000 * 1e6);
        zUsd.mint(user, 100_000 * 1e6);
        zUsd.mint(address(perpEngine), 100_000 * 1e6);

        // User deposits minimal zUSD to vault for margin (just above combined IMR requirements ~12k) to allow liquidations post adverse move
        vm.startPrank(user);
        zUsd.approve(address(vault), type(uint256).max);
        vault.deposit(address(zUsd), 15_000 * 1e6, false, bytes32(0));
        vm.stopPrank();

        vm.stopPrank();
    }

    function testOpenPositionsTracking() public {
        // Initially no open positions
        bytes32[] memory openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 0);

        // Open BTC position
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);

        // Should have 1 open market
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 1);
        assertEq(openMarkets[0], BTC_PERP);

        // Open ETH position
        vm.prank(user);
        perpEngine.openPosition(ETH_PERP, true, 20_000 * 1e6, 3);

        // Should have 2 open markets
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 2);

        // Check both markets are present
        bool btcFound = false;
        bool ethFound = false;
        for (uint256 i = 0; i < openMarkets.length; i++) {
            if (openMarkets[i] == BTC_PERP) btcFound = true;
            if (openMarkets[i] == ETH_PERP) ethFound = true;
        }
        assertTrue(btcFound && ethFound);
    }

    function testClosePositionPrunesMarket() public {
        // Open two positions
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);

        vm.prank(user);
        perpEngine.openPosition(ETH_PERP, true, 20_000 * 1e6, 3);

        // Verify 2 open markets
        bytes32[] memory openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 2);

        // Close BTC position
        vm.prank(user);
        perpEngine.closePosition(BTC_PERP);

        // Should have 1 open market (ETH only)
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 1);
        assertEq(openMarkets[0], ETH_PERP);

        // Verify BTC position is zero
        int256 btcPosition = perpEngine.getPosition(user, BTC_PERP);
        assertEq(btcPosition, 0);

        // Close ETH position
        vm.prank(user);
        perpEngine.closePosition(ETH_PERP);

        // Should have no open markets
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 0);
    }

    function testLiquidationPrunesMarket() public {
        // Open positions
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);

        vm.prank(user);
        perpEngine.openPosition(ETH_PERP, true, 20_000 * 1e6, 3);

        // Verify 2 open markets
        bytes32[] memory openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 2);

        // Make BTC position liquidatable
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 10000e18, uint64(block.timestamp)); // Severe drop

        // Liquidate BTC position
        vm.prank(admin); // Admin has KEEPER role
        perpEngine.liquidate(user, BTC_PERP);

        // Should have 1 open market (ETH only)
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 1);
        assertEq(openMarkets[0], ETH_PERP);

        // BTC position should be zero
        int256 btcPosition = perpEngine.getPosition(user, BTC_PERP);
        assertEq(btcPosition, 0);
    }

    function testPartialLiquidationKeepsMarket() public {
        // Open position
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);

        int256 initialPosition = perpEngine.getPosition(user, BTC_PERP);

        // Verify 1 open market
        bytes32[] memory openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 1);

        // Make position liquidatable
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 10000e18, uint64(block.timestamp));

        // Partial liquidation (half the position)
        uint128 partialSize = uint128(uint256(initialPosition) / 2);
        vm.prank(admin); // Admin has KEEPER role
        perpEngine.liquidatePartial(user, BTC_PERP, partialSize);

        // Should still have 1 open market
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 1);
        assertEq(openMarkets[0], BTC_PERP);

        // Position should be reduced but not zero
        int256 remainingPosition = perpEngine.getPosition(user, BTC_PERP);
        assertGt(remainingPosition, 0);
        assertEq(remainingPosition, initialPosition - int256(uint256(partialSize)));
    }

    function testPartialLiquidationFullSizePrunesMarket() public {
        // Open position
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 30_000 * 1e6, 2);

        int256 initialPosition = perpEngine.getPosition(user, BTC_PERP);

        // Make position liquidatable
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 10000e18, uint64(block.timestamp));

        // Partial liquidation with full size
        uint128 fullSize = uint128(uint256(initialPosition));
        vm.prank(admin);
        perpEngine.liquidatePartial(user, BTC_PERP, fullSize);

        // Should have no open markets
        bytes32[] memory openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 0);

        // Position should be zero
        int256 finalPosition = perpEngine.getPosition(user, BTC_PERP);
        assertEq(finalPosition, 0);
    }

    function testMultipleMarketsComplexScenario() public {
        // Open 3 positions
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 25_000 * 1e6, 2);

        vm.prank(user);
        perpEngine.openPosition(ETH_PERP, true, 25_000 * 1e6, 2);

        // Verify 2 open markets
        bytes32[] memory openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 2);

        // Close one position manually
        vm.prank(user);
        perpEngine.closePosition(BTC_PERP);

        // Should have 1 market
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 1);
        assertEq(openMarkets[0], ETH_PERP);

        // Open BTC again
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, false, 25_000 * 1e6, 2); // Short this time

        // Should have 2 markets again
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 2);

        // Liquidate both (make prices unfavorable)
        vm.prank(admin);
        spo.setPrice(address(mockBTC), 80000e18, uint64(block.timestamp)); // BTC up (bad for short)
        vm.prank(admin);
        spo.setPrice(address(mockETH), 1000e18, uint64(block.timestamp)); // ETH down (bad for long)

        // Liquidate ETH first
        vm.prank(admin);
        perpEngine.liquidate(user, ETH_PERP);

        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 1);
        assertEq(openMarkets[0], BTC_PERP);

        // Liquidate BTC
        vm.prank(admin);
        perpEngine.liquidate(user, BTC_PERP);

        // Should have no open markets
        openMarkets = perpEngine.getOpenMarketsForAccount(user);
        assertEq(openMarkets.length, 0);
    }
}
