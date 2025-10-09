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

contract PauseTest is Test {
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
    address public guardian = address(0x3);

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

        // Grant guardian PAUSER_ROLE
        perpEngine.grantRole(Constants.PAUSER_ROLE, guardian);
        vault.grantRole(Constants.PAUSER_ROLE, guardian);

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

    function testPauseUnpauseEngine() public {
        // Initially not paused
        assertFalse(perpEngine.paused());

        // Admin can pause
        vm.prank(admin);
        perpEngine.pause();
        assertTrue(perpEngine.paused());

        // Admin can unpause
        vm.prank(admin);
        perpEngine.unpause();
        assertFalse(perpEngine.paused());
    }

    function testGuardianCanPause() public {
        // Guardian can pause
        vm.prank(guardian);
        perpEngine.pause();
        assertTrue(perpEngine.paused());

        // Guardian can unpause
        vm.prank(guardian);
        perpEngine.unpause();
        assertFalse(perpEngine.paused());
    }

    function testOnlyPauserCanPause() public {
        // Non-pauser cannot pause
        vm.prank(user);
        vm.expectRevert();
        perpEngine.pause();

        // Non-pauser cannot unpause
        vm.prank(admin);
        perpEngine.pause();

        vm.prank(user);
        vm.expectRevert();
        perpEngine.unpause();
    }

    function testRecordFillRevertsWhenPaused() public {
        // Pause the engine
        vm.prank(admin);
        perpEngine.pause();

        // recordFill should revert when paused
        IPerpEngine.Fill memory fill = IPerpEngine.Fill({
            fillId: bytes32("test_fill"),
            account: user,
            marketId: BTC_PERP,
            isBuy: true,
            size: 1e8,
            priceZ: 60000 * 1e18,
            feeZ: 1000,
            fundingZ: 0,
            ts: uint64(block.timestamp),
            orderDigest: keccak256("test_fill")
        });

        vm.prank(admin);
        vm.expectRevert("Pausable: paused");
        perpEngine.recordFill(fill);
    }

    function testOpenPositionRevertsWhenPaused() public {
        // Pause the engine
        vm.prank(admin);
        perpEngine.pause();

        // openPosition should revert when paused
        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        perpEngine.openPosition(BTC_PERP, true, 10_000 * 1e6, 10);
    }

    function testVaultDepositRevertsWhenPaused() public {
        // Pause the vault
        vm.prank(admin);
        vault.pause();

        // deposit should revert when paused
        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        vault.deposit(address(zUsd), 1000 * 1e6, false, bytes32(0));
    }

    function testVaultWithdrawRevertsWhenPaused() public {
        // Pause the vault
        vm.prank(admin);
        vault.pause();

        // withdraw should revert when paused
        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        vault.withdraw(address(zUsd), 1000 * 1e6, false, bytes32(0));
    }

    function testOperationsWorkWhenUnpaused() public {
        // Ensure not paused
        assertFalse(perpEngine.paused());
        assertFalse(vault.paused());

        // Operations should work normally
        vm.prank(user);
        perpEngine.openPosition(BTC_PERP, true, 10_000 * 1e6, 2);

        // Verify position was created
        int256 position = perpEngine.getPosition(user, BTC_PERP);
        assertGt(position, 0);
    }
}
