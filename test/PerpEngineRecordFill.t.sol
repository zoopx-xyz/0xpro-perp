// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PerpEngine} from "../src/core/PerpEngine.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {RiskConfig} from "../src/core/RiskConfig.sol";
import {FeeSplitterSpoke} from "../src/core/FeeSplitterSpoke.sol";
import {TreasurySpoke} from "../src/core/TreasurySpoke.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {IPerpEngine} from "../src/core/interfaces/IPerpEngine.sol";

contract PerpEngineRecordFillTest is Test {
    PerpEngine engine;
    MarginVaultV2 vault;
    CollateralManager cm;
    OracleRouter orac;
    SignedPriceOracle spo;
    RiskConfig risk;
    FeeSplitterSpoke fs;
    TreasurySpoke ts;
    MockERC20 z;

    address keeper = address(0xBEEF);
    bytes32 constant MARKET = keccak256("BTC-PERP");

    function setUp() public {
        cm = CollateralManager(_proxy(address(new CollateralManager())));
        orac = OracleRouter(_proxy(address(new OracleRouter())));
        spo = SignedPriceOracle(_proxy(address(new SignedPriceOracle())));
        vault = MarginVaultV2(_proxy(address(new MarginVaultV2())));
        engine = PerpEngine(_proxy(address(new PerpEngine())));
        risk = RiskConfig(_proxy(address(new RiskConfig())));
        fs = FeeSplitterSpoke(_proxy(address(new FeeSplitterSpoke())));
        ts = TreasurySpoke(_proxy(address(new TreasurySpoke())));

        cm.initialize(address(this), address(orac));
        orac.initialize(address(this));
        spo.initialize(address(this), address(0), 300);
        vault.initialize(address(this), address(cm));
    engine.initialize(address(this), address(vault));
        risk.initialize(address(this));
        fs.initialize(address(this));
        ts.initialize(address(this));

        // wire engine state via storage slots for tests
        // set roles
        vm.startPrank(address(this));
        // grant keeper role
        // direct storage for simplicity not shown; we'll call as admin
        vm.stopPrank();

    z = new MockERC20("mockzUSD", "mzUSD", 6);
        orac.registerAdapter(address(z), address(spo));
        cm.setAssetConfig(address(z), true, 10000, address(orac), 6);
        spo.setPrice(address(z), 1e18, uint64(block.timestamp));

    // wire deps
    engine.setDeps(address(risk), address(orac), address(cm), address(ts), address(fs), address(z));
    vault.setDeps(address(risk), address(orac), address(engine));
    vault.grantRole(keccak256("ENGINE"), address(engine));
    ts.grantRole(keccak256("FORWARDER_ROLE"), address(engine)); // Grant FORWARDER_ROLE
    
    // Configure treasury and fee splitter
    ts.setZUsdToken(address(z));
    fs.setZUsdToken(address(z));
    fs.setRecipients(address(this), address(this), address(this), address(this));
    
    // setup market
    engine.registerMarket(MARKET, address(z), 6); // using z as base for simplicity in test

        // Pre-fund treasury with fees
        z.mint(address(this), 1_000_000 * 1e6);
        z.transfer(address(ts), 10_000 * 1e6);
    }

    function _proxy(address impl) internal returns (address) {
        bytes memory code = abi.encodePacked(hex"3d602d80600a3d3981f3", hex"363d3d373d3d3d363d73", bytes20(impl), hex"5af43d82803e903d91602b57fd5bf3");
        address proxy;
        assembly { proxy := create(0, add(code, 0x20), mload(code)) }
        require(proxy != address(0), "proxy fail");
        return proxy;
    }

    function testRecordFillHappyPath() public {
        IPerpEngine.Fill memory f = IPerpEngine.Fill({
            fillId: keccak256("fillX"),
            account: address(this),
            marketId: MARKET,
            isBuy: true,
            size: 1_000_000, // arbitrary
            priceZ: 1e18,
            feeZ: 1_000_000, // 1 zUSD (6 decimals internal)
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });

        engine.recordFill(f);

        assertTrue(engine.seenFill(f.fillId));
    }
}
