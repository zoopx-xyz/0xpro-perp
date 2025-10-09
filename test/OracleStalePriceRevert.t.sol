// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/core/SignedPriceOracle.sol";
import "../src/core/OracleRouter.sol";
import "../src/core/PerpEngine.sol";
import "../src/core/MarginVaultV2.sol";
import "../src/core/CollateralManager.sol";
import "../src/core/RiskConfig.sol";
import "../src/tokens/MockzUSD.sol";
import "../src/tokens/MockERC20.sol";
import "../src/core/interfaces/IRiskConfig.sol";
import "../lib/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OracleStalePriceRevertTest is Test {
    SignedPriceOracle oracle;
    OracleRouter router;
    PerpEngine engine;
    MarginVaultV2 vault;
    CollateralManager collateralManager;
    RiskConfig riskConfig;
    MockzUSD zUSD;
    MockERC20 mBTC;

    address admin = address(0x123);
    address keeper = address(0x456);
    address user = address(0x789);
    address signer = address(0xabc);
    
    bytes32 marketId = keccak256("BTC-PERP");
    uint256 constant MAX_STALE = 300; // 5 minutes

    function setUp() public {
        vm.startPrank(admin);

        // Deploy tokens
        zUSD = new MockzUSD();
        mBTC = new MockERC20("Mock BTC", "mBTC", 8);

    // Deploy via proxies to respect upgradeable initialize patterns
    SignedPriceOracle oracleImpl = new SignedPriceOracle();
    oracle = SignedPriceOracle(address(new ERC1967Proxy(address(oracleImpl), "")));
    oracle.initialize(admin, signer, uint64(MAX_STALE));

    OracleRouter routerImpl = new OracleRouter();
    router = OracleRouter(address(new ERC1967Proxy(address(routerImpl), "")));
    router.initialize(admin);
        router.registerAdapter(address(mBTC), address(oracle));

    CollateralManager cmImpl = new CollateralManager();
    collateralManager = CollateralManager(address(new ERC1967Proxy(address(cmImpl), "")));
    collateralManager.initialize(admin, address(router));
        collateralManager.setAssetConfig(address(zUSD), true, 10000, address(router), 6);
        // Register zUSD on the router and set its price to 1.0 to enable valuation in CollateralManager
        router.registerAdapter(address(zUSD), address(oracle));

    MarginVaultV2 mvImpl = new MarginVaultV2();
    vault = MarginVaultV2(address(new ERC1967Proxy(address(mvImpl), "")));
    vault.initialize(admin, address(collateralManager));

    RiskConfig rcImpl = new RiskConfig();
    riskConfig = RiskConfig(address(new ERC1967Proxy(address(rcImpl), "")));
    riskConfig.initialize(admin);
        riskConfig.setMarketRisk(marketId, RiskConfig.MarketRisk({
            imrBps: 500,
            mmrBps: 250,
            liqPenaltyBps: 50,
            makerFeeBps: 0,
            takerFeeBps: 0,
            maxLev: 20
        })); // 5% IMR, 2.5% MMR, 0.5% penalty

    PerpEngine peImpl = new PerpEngine();
    engine = PerpEngine(address(new ERC1967Proxy(address(peImpl), "")));
    engine.initialize(admin, address(vault));
        engine.setDeps(
            address(riskConfig),
            address(router),
            address(collateralManager),
            address(0), // treasury
            address(0), // feeSplitter
            address(0), // fundingModule
            address(zUSD)
        );
        engine.registerMarket(marketId, address(mBTC), 8, "BTC-PERP");

        // Grant roles
    vault.grantRole(Constants.ENGINE, address(engine));
        engine.grantRole(Constants.KEEPER, keeper);
        oracle.grantRole(Constants.PRICE_KEEPER, keeper);

    // Set initial price (fresh)
        vm.warp(1000);
        oracle.setPrice(address(mBTC), 50000e18, uint64(block.timestamp));
    oracle.setPrice(address(zUSD), 1e18, uint64(block.timestamp));

        vm.stopPrank();
    }

    function testSetMaxStaleByPriceKeeper() public {
        vm.prank(keeper);
        oracle.setMaxStale(600); // 10 minutes
        assertEq(oracle.getMaxStale(), 600);
    }

    function test_RevertWhen_SetMaxStaleByNonKeeper() public {
        vm.prank(user);
        vm.expectRevert();
        oracle.setMaxStale(600);
    }

    function testGetPriceAndStale() public {
        // Fresh price
        (uint256 price, bool isStale) = router.getPriceAndStale(address(mBTC));
        assertEq(price, 50000e18);
        assertFalse(isStale);

        // Make price stale
        vm.warp(block.timestamp + MAX_STALE + 1);
        (price, isStale) = router.getPriceAndStale(address(mBTC));
        assertEq(price, 50000e18);
        assertTrue(isStale);
    }

    function testRecordFillRevertsOnStalePrice() public {
        // Make price stale
        vm.warp(block.timestamp + MAX_STALE + 1);

        IPerpEngine.Fill memory fill = IPerpEngine.Fill({
            fillId: bytes32("test_fill_1"),
            account: user,
            marketId: marketId,
            isBuy: true,
            size: 1e8, // 1 BTC
            priceZ: 50000e18,
            feeZ: 0,
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });

        vm.prank(keeper);
        vm.expectRevert("PRICE_STALE");
        engine.recordFill(fill);
    }

    function testRecordFillSucceedsOnFreshPrice() public {
        // Price is fresh from setUp
        // Fund and deposit user collateral so reserve in recordFill can succeed
        vm.prank(admin);
        zUSD.mint(user, 10_000e6);
        vm.startPrank(user);
        zUSD.approve(address(vault), 10_000e6);
        vault.deposit(address(zUSD), 10_000e6, false, bytes32(0));
        vm.stopPrank();

        IPerpEngine.Fill memory fill = IPerpEngine.Fill({
            fillId: bytes32("test_fill_1"),
            account: user,
            marketId: marketId,
            isBuy: true,
            size: 1e8, // 1 BTC
            priceZ: 50000e18,
            feeZ: 0,
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });

        vm.prank(keeper);
        engine.recordFill(fill);

        // Check position was updated
        int256 position = engine.positions(user, marketId);
        assertEq(position, 1e8);
    }

    function testOpenPositionRevertsOnStalePrice() public {
        // Fund user with zUSD
        vm.prank(admin);
        zUSD.mint(user, 1000e6); // 1000 zUSD

        vm.startPrank(user);
        zUSD.approve(address(vault), 1000e6);
        vault.deposit(address(zUSD), 1000e6, false, bytes32(0));
        vm.stopPrank();

        // Make price stale
        vm.warp(block.timestamp + MAX_STALE + 1);

        vm.prank(user);
        vm.expectRevert("PRICE_STALE");
        engine.openPosition(marketId, true, 100e6, 2); // 100 zUSD collateral, 2x leverage
    }

    function testOpenPositionSucceedsOnFreshPrice() public {
        // Fund user with zUSD
        vm.prank(admin);
        zUSD.mint(user, 1000e6); // 1000 zUSD

        vm.startPrank(user);
        zUSD.approve(address(vault), 1000e6);
        vault.deposit(address(zUSD), 1000e6, false, bytes32(0));

        // Price is fresh from setUp
        engine.openPosition(marketId, true, 100e6, 2); // 100 zUSD collateral, 2x leverage
        vm.stopPrank();

        // Check position was created
        int256 position = engine.positions(user, marketId);
        assertTrue(position > 0);
    }

    function testRefreshPriceMakesFreshAgain() public {
        // Make price stale
        vm.warp(block.timestamp + MAX_STALE + 1);
        
        (, bool isStale) = router.getPriceAndStale(address(mBTC));
        assertTrue(isStale);

        // Refresh price
        vm.prank(keeper);
        oracle.setPrice(address(mBTC), 51000e18, uint64(block.timestamp));

        // Should be fresh now
        (uint256 price, bool isStaleAfter) = router.getPriceAndStale(address(mBTC));
        assertEq(price, 51000e18);
        assertFalse(isStaleAfter);
    }

    function testMaxStaleZeroMeansPriceNeverStale() public {
        // Set max stale to 0 (special case: never stale)
        vm.prank(keeper);
        oracle.setMaxStale(0);

        // Even after long time, should not be stale
        vm.warp(block.timestamp + 365 days);
        
        (, bool isStale) = router.getPriceAndStale(address(mBTC));
        assertFalse(isStale);
    }

    function testEmptyPriceIsStale() public {
        // Register new asset without setting price
        MockERC20 mETH = new MockERC20("Mock ETH", "mETH", 18);
        
        vm.prank(admin);
        router.registerAdapter(address(mETH), address(oracle));

        // Should be stale (timestamp = 0)
        (, bool isStale) = router.getPriceAndStale(address(mETH));
        assertTrue(isStale);
    }
}