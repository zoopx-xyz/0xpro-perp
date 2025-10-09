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
import {FundingModule} from "../src/core/FundingModule.sol";

/// @notice Basic invariant tests for market tracking and margin accounting.
/// These focus on properties that should always hold regardless of user actions.
contract InvariantsTest is Test {
    MockzUSD zUsd;
    MockERC20 mockBTC;
    MockERC20 mockETH;
    CollateralManager cm;
    SignedPriceOracle spo;
    OracleRouter oracleRouter;
    MarginVaultV2 vault;
    PerpEngine engine;
    RiskConfig riskConfig;
    FundingModule fundingModule;

    address admin = address(0xA11CE);
    address userA = address(0xBEEF);
    address userB = address(0xFEED);

    bytes32 constant BTC_PERP = keccak256("BTC-PERP");
    bytes32 constant ETH_PERP = keccak256("ETH-PERP");

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
        FundingModule fmImpl = new FundingModule();

        // Proxies
        cm = CollateralManager(address(new ERC1967Proxy(address(cmImpl), "")));
        spo = SignedPriceOracle(address(new ERC1967Proxy(address(spoImpl), "")));
        oracleRouter = OracleRouter(address(new ERC1967Proxy(address(orImpl), "")));
        vault = MarginVaultV2(address(new ERC1967Proxy(address(mvImpl), "")));
        engine = PerpEngine(address(new ERC1967Proxy(address(peImpl), "")));
        riskConfig = RiskConfig(address(new ERC1967Proxy(address(rcImpl), "")));
        fundingModule = FundingModule(address(new ERC1967Proxy(address(fmImpl), "")));

        // Initialize
        spo.initialize(admin, address(0), 300); // signer unused here
        oracleRouter.initialize(admin);
        cm.initialize(admin, address(oracleRouter));
        vault.initialize(admin, address(cm));
        engine.initialize(admin, address(vault));
        riskConfig.initialize(admin);
        fundingModule.initialize(admin);

        // Dependencies
        engine.setDeps(address(riskConfig), address(oracleRouter), address(cm), address(0), address(0), address(fundingModule), address(zUsd));
        vault.setDeps(address(riskConfig), address(oracleRouter), address(engine));

        // Markets & oracle
        oracleRouter.registerAdapter(address(mockBTC), address(spo));
        oracleRouter.registerAdapter(address(mockETH), address(spo));
        oracleRouter.registerAdapter(address(zUsd), address(spo));
        cm.setAssetConfig(address(mockBTC), true, 5000, address(oracleRouter), 8);
        cm.setAssetConfig(address(mockETH), true, 5000, address(oracleRouter), 18);
        cm.setAssetConfig(address(zUsd), true, 10000, address(oracleRouter), 6);
        spo.setPrice(address(mockBTC), 60_000e18, uint64(block.timestamp));
        spo.setPrice(address(mockETH), 2_000e18, uint64(block.timestamp));
        spo.setPrice(address(zUsd), 1e18, uint64(block.timestamp));

        // Risk config
        RiskConfig.MarketRisk memory risk = RiskConfig.MarketRisk({
            imrBps: 1000,
            mmrBps: 500,
            liqPenaltyBps: 100,
            makerFeeBps: 0,
            takerFeeBps: 0,
            maxLev: 10
        });
        riskConfig.setMarketRisk(BTC_PERP, risk);
        riskConfig.setMarketRisk(ETH_PERP, risk);
        engine.registerMarket(BTC_PERP, address(mockBTC), 8);
        engine.registerMarket(ETH_PERP, address(mockETH), 18);

        // Roles
        vault.grantRole(Constants.ENGINE, address(engine));
        engine.grantRole(Constants.KEEPER, admin);

        // Mint & deposit margin for users
        zUsd.mint(userA, 100_000e6);
        zUsd.mint(userB, 100_000e6);
        vm.startPrank(userA);
        zUsd.approve(address(vault), type(uint256).max);
        vault.deposit(address(zUsd), 30_000e6, false, bytes32(0));
        vm.stopPrank();
        vm.startPrank(userB);
        zUsd.approve(address(vault), type(uint256).max);
        vault.deposit(address(zUsd), 30_000e6, false, bytes32(0));
        vm.stopPrank();

        vm.stopPrank();

        // Target fuzzing at this test contract (we expose handlers below)
        targetContract(address(this));
    }

    // Handlers (called by the invariant fuzzer)
    function openLongBTC(uint256 collateralZ, uint256 lev, bool userA_) external {
        if (collateralZ == 0 || collateralZ > 5_000e6) return;
        if (lev == 0 || lev > 10) return;
        address user = userA_ ? userA : userB;
        vm.startPrank(user);
        try engine.openPosition(BTC_PERP, true, collateralZ, lev) {} catch {}
        vm.stopPrank();
    }

    function openLongETH(uint256 collateralZ, uint256 lev, bool userA_) external {
        if (collateralZ == 0 || collateralZ > 5_000e6) return;
        if (lev == 0 || lev > 10) return;
        address user = userA_ ? userA : userB;
        vm.startPrank(user);
        try engine.openPosition(ETH_PERP, true, collateralZ, lev) {} catch {}
        vm.stopPrank();
    }

    function closeBTC(bool userA_) external {
        address user = userA_ ? userA : userB;
        vm.startPrank(user);
        try engine.closePosition(BTC_PERP) {} catch {}
        vm.stopPrank();
    }

    function closeETH(bool userA_) external {
        address user = userA_ ? userA : userB;
        vm.startPrank(user);
        try engine.closePosition(ETH_PERP) {} catch {}
        vm.stopPrank();
    }

    // Invariants
    /// @notice Open markets list must contain only markets with non-zero positions and no markets with zero positions.
    function invariant_OpenMarketsConsistency() external {
        _assertAccountConsistency(userA);
        _assertAccountConsistency(userB);
    }

    /// @notice Reserved margin must never exceed total deposited gross collateral value (haircut applied can reduce equity but reserved cannot be larger than gross value).
    function invariant_ReservedMarginBounded() external {
        // crude bound: reservedZ <= sum(assetValueInZUSD(deposited)) across crossBalances
        _assertReservedBound(userA);
        _assertReservedBound(userB);
    }

    function _assertAccountConsistency(address user) internal {
        bytes32[] memory ms = engine.getOpenMarketsForAccount(user);
        // Build a set for duplicate detection
        for (uint256 i = 0; i < ms.length; i++) {
            // position must be non-zero
            int256 p = engine.getPosition(user, ms[i]);
            assertTrue(p != 0, "open list contains zero position");
            // ensure no duplicate by checking later occurrences
            for (uint256 j = i + 1; j < ms.length; j++) {
                assertTrue(ms[i] != ms[j], "duplicate market in open list");
            }
        }
        // Also ensure there is no market with non-zero position missing from list (check two known markets)
        if (engine.getPosition(user, BTC_PERP) != 0) {
            bool found;
            for (uint256 k = 0; k < ms.length; k++) if (ms[k] == BTC_PERP) { found = true; break; }
            assertTrue(found, "BTC missing from open markets");
        }
        if (engine.getPosition(user, ETH_PERP) != 0) {
            bool found2;
            for (uint256 k2 = 0; k2 < ms.length; k2++) if (ms[k2] == ETH_PERP) { found2 = true; break; }
            assertTrue(found2, "ETH missing from open markets");
        }
    }

    function _assertReservedBound(address user) internal {
        // Sum deposited crossBalances for zUSD only (simplified; multi-asset extension possible)
        uint128 bal = vault.crossBalances(user, address(zUsd));
        uint256 grossValue = uint256(bal) * 1e12; // zUSD has 6 decimals; price is 1e18; value = amount * 1e18 / 1e6 => amount * 1e12
        uint256 reserved = vault.reservedZ(user);
        assertTrue(reserved <= grossValue + 1e6, "reserved exceeds gross value"); // +1e6 slack for rounding
    }
}
