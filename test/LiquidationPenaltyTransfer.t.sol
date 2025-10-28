// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Constants} from "../lib/Constants.sol";
import {MockzUSD} from "../src/tokens/MockzUSD.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {PerpEngine} from "../src/core/PerpEngine.sol";
import {RiskConfig} from "../src/core/RiskConfig.sol";
import {TreasurySpoke} from "../src/core/TreasurySpoke.sol";
import {IPerpEngine} from "../src/core/interfaces/IPerpEngine.sol";

contract LiquidationPenaltyTransferTest is Test {
    MockzUSD z;
    MockERC20 base;
    CollateralManager cm;
    SignedPriceOracle spo;
    OracleRouter orac;
    MarginVaultV2 vault;
    PerpEngine engine;
    RiskConfig risk;
    TreasurySpoke treasury;

    address admin = address(this);
    address user = address(0xB0B);
    bytes32 constant MARKET = keccak256("BTC-PERP");

    function setUp() public {
        // Deploy tokens
        z = new MockzUSD();
        base = new MockERC20("mockBTC", "mBTC", 8);

        // Deploy implementations
        CollateralManager cmImpl = new CollateralManager();
        SignedPriceOracle spoImpl = new SignedPriceOracle();
        OracleRouter orImpl = new OracleRouter();
        MarginVaultV2 mvImpl = new MarginVaultV2();
        PerpEngine peImpl = new PerpEngine();
        RiskConfig rcImpl = new RiskConfig();
        TreasurySpoke tsImpl = new TreasurySpoke();

        // Proxies
        cm = CollateralManager(address(new ERC1967Proxy(address(cmImpl), "")));
        spo = SignedPriceOracle(address(new ERC1967Proxy(address(spoImpl), "")));
        orac = OracleRouter(address(new ERC1967Proxy(address(orImpl), "")));
        vault = MarginVaultV2(address(new ERC1967Proxy(address(mvImpl), "")));
        engine = PerpEngine(address(new ERC1967Proxy(address(peImpl), "")));
        risk = RiskConfig(address(new ERC1967Proxy(address(rcImpl), "")));
        treasury = TreasurySpoke(address(new ERC1967Proxy(address(tsImpl), "")));

        // Initialize
        cm.initialize(admin, address(orac));
        spo.initialize(admin, address(0), 300);
        orac.initialize(admin);
        vault.initialize(admin, address(cm));
        engine.initialize(admin, address(vault));
        risk.initialize(admin);
        treasury.initialize(admin);

        // Wiring
        orac.registerAdapter(address(base), address(spo));
        orac.registerAdapter(address(z), address(spo));
        cm.setAssetConfig(address(base), true, 5000, address(orac), 8);
        cm.setAssetConfig(address(z), true, 10000, address(orac), 6);
        spo.setPrice(address(base), 60_000e18, uint64(block.timestamp));
        spo.setPrice(address(z), 1e18, uint64(block.timestamp));

        engine.setDeps(address(risk), address(orac), address(cm), address(treasury), address(0), address(0), address(z));
        vault.setDeps(address(risk), address(orac), address(engine));
        vault.grantRole(Constants.ENGINE, address(engine));
        treasury.grantRole(Constants.FORWARDER_ROLE, address(engine));

        // Risk params (large liq penalty so it is noticeable)
        RiskConfig.MarketRisk memory r = RiskConfig.MarketRisk({
            imrBps: 1000,   // 10%
            mmrBps: 900,    // 9%
            liqPenaltyBps: 500, // 5%
            makerFeeBps: 0,
            takerFeeBps: 0,
            maxLev: 10
        });
        risk.setMarketRisk(MARKET, r);
        engine.registerMarket(MARKET, address(base), 8);

        // Fund user and deposit zUSD
        z.mint(user, 100_000 * 1e6);
        vm.startPrank(user);
        z.approve(address(vault), type(uint256).max);
        vault.deposit(address(z), 10_000 * 1e6, false, bytes32(0));
        vm.stopPrank();
    }

    function testPenaltyTransfersToTreasuryOnLiquidation() public {
        // Open a position via recordFill (keeper)
        vm.startPrank(admin);
        engine.grantRole(Constants.KEEPER, admin);

        // Create a fill opening 1 BTC long at 60k
        IPerpEngine.Fill memory f = IPerpEngine.Fill({
            fillId: keccak256("fill-open"),
            account: user,
            marketId: MARKET,
            isBuy: true,
            size: uint128(1e8),
            priceZ: uint128(60_000e18),
            feeZ: 0,
            fundingZ: 0,
            ts: uint64(block.timestamp),
            orderDigest: keccak256("fill-open")
        });
        engine.recordFill(f);

        // Crash price to force under MMR
        spo.setPrice(address(base), 30_000e18, uint64(block.timestamp));

    // Track balances before
    uint256 treasuryBefore = z.balanceOf(address(treasury));
    uint128 userVaultBefore = vault.getCrossBalance(user, address(z));

        // Liquidate
        engine.liquidate(user, MARKET);

        // Penalty should have moved from user vault to treasury, and reserved IMR released back to user
        uint256 treasuryAfter = z.balanceOf(address(treasury));
        uint128 userVaultAfter = vault.getCrossBalance(user, address(z));

        // Expected amounts with our test parameters:
        // size = 1e8 (1 BTC), mark post-crash = 30_000e18, decimals=8
        // notionalZ = 3e22; penaltyZ=1.5e21 (5%); releaseZ=3e21 (10%)
        // token units (6 decimals): penaltyToken=1.5e9; releaseToken=3e9
        uint256 expectedPenaltyToken = 1_500_000_000; // 1.5e9
        uint256 expectedReleaseToken = 3_000_000_000; // 3e9

        assertEq(treasuryAfter - treasuryBefore, expectedPenaltyToken, "treasury penalty delta");
        assertEq(uint256(userVaultAfter) - uint256(userVaultBefore), expectedReleaseToken - expectedPenaltyToken, "user vault net delta");
        vm.stopPrank();
    }
}
