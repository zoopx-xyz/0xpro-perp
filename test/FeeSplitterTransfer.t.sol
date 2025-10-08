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
import {IPerpEngine} from "../src/core/interfaces/IPerpEngine.sol";

contract FeeSplitterTransferTest is Test {
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

    address public admin = address(0x1);
    address public user = address(0x2);
    address public treasuryRecipient = address(0x3);
    address public insuranceRecipient = address(0x4);
    address public uiRecipient = address(0x5);
    address public referralRecipient = address(0x6);

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

        // Deploy proxies
        cm = CollateralManager(address(new ERC1967Proxy(address(cmImpl), "")));
        spo = SignedPriceOracle(address(new ERC1967Proxy(address(spoImpl), "")));
        oracleRouter = OracleRouter(address(new ERC1967Proxy(address(orImpl), "")));
        vault = MarginVaultV2(address(new ERC1967Proxy(address(mvImpl), "")));
        perpEngine = PerpEngine(address(new ERC1967Proxy(address(peImpl), "")));
        riskConfig = RiskConfig(address(new ERC1967Proxy(address(rcImpl), "")));
        treasury = TreasurySpoke(address(new ERC1967Proxy(address(tsImpl), "")));
        feeSplitter = FeeSplitterSpoke(address(new ERC1967Proxy(address(fsImpl), "")));

        // Initialize
        spo.initialize(admin, address(0), 300);
        oracleRouter.initialize(admin);
        cm.initialize(admin, address(oracleRouter));
        vault.initialize(admin, address(cm));
        perpEngine.initialize(admin, address(vault));
        riskConfig.initialize(admin);
        treasury.initialize(admin);
        feeSplitter.initialize(admin);

        // Wire dependencies
        perpEngine.setDeps(address(riskConfig), address(oracleRouter), address(cm), address(treasury), address(feeSplitter), address(zUsd));
        vault.setDeps(address(riskConfig), address(oracleRouter), address(perpEngine));

        // Configure oracle and market
        oracleRouter.registerAdapter(address(mockBTC), address(spo));
        oracleRouter.registerAdapter(address(zUsd), address(spo)); // Register zUSD adapter
        cm.setAssetConfig(address(mockBTC), true, 5000, address(oracleRouter), 8);
        cm.setAssetConfig(address(zUsd), true, 10000, address(oracleRouter), 6); // Configure zUSD
        spo.setPrice(address(mockBTC), 60000e18, uint64(block.timestamp));
        spo.setPrice(address(zUsd), 1e18, uint64(block.timestamp)); // zUSD price

        // Configure fee splitting
        treasury.setZUsdToken(address(zUsd));
        feeSplitter.setZUsdToken(address(zUsd));
        feeSplitter.setRecipients(treasuryRecipient, insuranceRecipient, uiRecipient, referralRecipient);
        
        // Set custom split: 50% treasury, 30% insurance, 10% UI, 10% referral
        feeSplitter.setSplit(5000, 3000, 1000, 1000);

        // Setup market
        RiskConfig.MarketRisk memory risk = RiskConfig.MarketRisk({
            imrBps: 1000, // 10%
            mmrBps: 500,  // 5%
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

        // Mint tokens
        zUsd.mint(admin, 1_000_000 * 1e6);
        zUsd.mint(address(treasury), 1_000_000 * 1e6); // Fund treasury with fees
        zUsd.mint(user, 100_000 * 1e6); // Fund user for margin requirements
        mockBTC.mint(admin, 1000 * 1e8);
        mockBTC.mint(user, 100 * 1e8);

        // User deposits zUSD to vault for margin
        vm.startPrank(user);
        zUsd.approve(address(vault), type(uint256).max);
        vault.deposit(address(zUsd), 50_000 * 1e6, false, bytes32(0)); // Deposit for margin
        vm.stopPrank();

        vm.stopPrank();
    }

    function testFeeSplitterTransfer() public {
        vm.startPrank(admin);

        // Record initial balances
        uint256 treasuryInitial = zUsd.balanceOf(treasuryRecipient);
        uint256 insuranceInitial = zUsd.balanceOf(insuranceRecipient);
        uint256 uiInitial = zUsd.balanceOf(uiRecipient);
        uint256 referralInitial = zUsd.balanceOf(referralRecipient);
        uint256 treasuryContractInitial = zUsd.balanceOf(address(treasury));

        // Create a fill with fees
        uint256 feeAmount = 1000 * 1e6; // 1000 zUSD fee
        IPerpEngine.Fill memory fill = IPerpEngine.Fill({
            fillId: bytes32("test_fill_1"),
            account: user,
            marketId: BTC_PERP,
            isBuy: true,
            size: 1e8, // 1 BTC
            priceZ: 60000 * 1e18,
            feeZ: uint128(feeAmount),
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });

        // Record the fill (this should trigger fee forwarding and splitting)
        perpEngine.recordFill(fill);

        // Check that fees were distributed correctly
        uint256 expectedTreasury = (feeAmount * 5000) / 10000; // 50%
        uint256 expectedInsurance = (feeAmount * 3000) / 10000; // 30%
        uint256 expectedUI = (feeAmount * 1000) / 10000; // 10%
        uint256 expectedReferral = (feeAmount * 1000) / 10000; // 10%

        assertEq(zUsd.balanceOf(treasuryRecipient), treasuryInitial + expectedTreasury, "Treasury recipient balance incorrect");
        assertEq(zUsd.balanceOf(insuranceRecipient), insuranceInitial + expectedInsurance, "Insurance recipient balance incorrect");
        assertEq(zUsd.balanceOf(uiRecipient), uiInitial + expectedUI, "UI recipient balance incorrect");
        assertEq(zUsd.balanceOf(referralRecipient), referralInitial + expectedReferral, "Referral recipient balance incorrect");

        // Check that treasury contract balance decreased by the fee amount
        assertEq(zUsd.balanceOf(address(treasury)), treasuryContractInitial - feeAmount, "Treasury contract balance incorrect");

        vm.stopPrank();
    }

    function testFeeSplitterNoFeesWhenZeroAmount() public {
        vm.startPrank(admin);

        // Record initial balances
        uint256 treasuryInitial = zUsd.balanceOf(treasuryRecipient);
        uint256 insuranceInitial = zUsd.balanceOf(insuranceRecipient);
        uint256 treasuryContractInitial = zUsd.balanceOf(address(treasury));

        // Create a fill with zero fees
        IPerpEngine.Fill memory fill = IPerpEngine.Fill({
            fillId: bytes32("test_fill_zero"),
            account: user,
            marketId: BTC_PERP,
            isBuy: true,
            size: 1e8, // 1 BTC
            priceZ: 60000 * 1e18,
            feeZ: 0, // Zero fees
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });

        // Record the fill
        perpEngine.recordFill(fill);

        // Check that no fees were transferred
        assertEq(zUsd.balanceOf(treasuryRecipient), treasuryInitial, "Treasury recipient should not receive fees");
        assertEq(zUsd.balanceOf(insuranceRecipient), insuranceInitial, "Insurance recipient should not receive fees");
        assertEq(zUsd.balanceOf(address(treasury)), treasuryContractInitial, "Treasury contract balance should be unchanged");

        vm.stopPrank();
    }

    function testFeeSplitterCustomSplit() public {
        vm.startPrank(admin);

        // Change split to 100% treasury
        feeSplitter.setSplit(10000, 0, 0, 0);

        uint256 treasuryInitial = zUsd.balanceOf(treasuryRecipient);
        uint256 insuranceInitial = zUsd.balanceOf(insuranceRecipient);

        uint256 feeAmount = 2000 * 1e6; // 2000 zUSD fee
        IPerpEngine.Fill memory fill = IPerpEngine.Fill({
            fillId: bytes32("test_fill_custom"),
            account: user,
            marketId: BTC_PERP,
            isBuy: true,
            size: 1e8,
            priceZ: 60000 * 1e18,
            feeZ: uint128(feeAmount),
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });

        perpEngine.recordFill(fill);

        // All fees should go to treasury
        assertEq(zUsd.balanceOf(treasuryRecipient), treasuryInitial + feeAmount, "All fees should go to treasury");
        assertEq(zUsd.balanceOf(insuranceRecipient), insuranceInitial, "Insurance should receive no fees");

        vm.stopPrank();
    }

    function testFeeSplitterRevertOnInvalidSplit() public {
        vm.startPrank(admin);

        // Try to set split that exceeds 100%
        vm.expectRevert("split exceeds 100%");
        feeSplitter.setSplit(5000, 5000, 5000, 5000); // 200% total

        vm.stopPrank();
    }
}