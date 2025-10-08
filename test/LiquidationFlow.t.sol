// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PerpEngine} from "../src/core/PerpEngine.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {IPerpEngine} from "../src/core/interfaces/IPerpEngine.sol";
import {RiskConfig} from "../src/core/RiskConfig.sol";

contract LiquidationFlowTest is Test {
    PerpEngine engine;
    MarginVaultV2 vault;
    CollateralManager cm;
    OracleRouter orac;
    SignedPriceOracle spo;
    MockERC20 z;
    RiskConfig risk;

    bytes32 constant MARKET = keccak256("BTC-PERP");

    function setUp() public {
        cm = CollateralManager(_p(address(new CollateralManager())));
        orac = OracleRouter(_p(address(new OracleRouter())));
        spo = SignedPriceOracle(_p(address(new SignedPriceOracle())));
        vault = MarginVaultV2(_p(address(new MarginVaultV2())));
    engine = PerpEngine(_p(address(new PerpEngine())));
    risk = RiskConfig(_p(address(new RiskConfig())));

        cm.initialize(address(this), address(orac));
        orac.initialize(address(this));
        spo.initialize(address(this), address(0), 300);
        vault.initialize(address(this), address(cm));
    engine.initialize(address(this), address(vault));
    risk.initialize(address(this));

        z = new MockERC20("mockzUSD", "mzUSD", 6);
        orac.registerAdapter(address(z), address(spo));
        cm.setAssetConfig(address(z), true, 10000, address(orac), 6);
        spo.setPrice(address(z), 1e18, uint64(block.timestamp));
    }

    function _p(address impl) internal returns (address) {
        bytes memory code = abi.encodePacked(hex"3d602d80600a3d3981f3", hex"363d3d373d3d3d363d73", bytes20(impl), hex"5af43d82803e903d91602b57fd5bf3");
        address proxy;
        assembly { proxy := create(0, add(code, 0x20), mload(code)) }
        require(proxy != address(0), "proxy fail");
        return proxy;
    }

    function testLiquidateNoPositionReverts() public {
        vm.expectRevert(bytes("no pos"));
        engine.liquidate(address(this), MARKET);
    }

    function testLiquidationHappyPath() public {
    engine.setDeps(address(risk), address(orac), address(cm), address(0), address(0), address(z));
    vault.setDeps(address(risk), address(orac), address(engine));
    vault.grantRole(keccak256("ENGINE"), address(engine));
        engine.registerMarket(MARKET, address(z), 6);

        // set MM R high so liquidation condition holds easily
        RiskConfig.MarketRisk memory r = RiskConfig.MarketRisk({imrBps: 10000, mmrBps: 9000, liqPenaltyBps: 500, makerFeeBps: 5, takerFeeBps: 7, maxLev: 10});
        risk.setMarketRisk(MARKET, r);

        z.mint(address(this), 1000 * 1e6);
        z.approve(address(vault), type(uint256).max);
        vault.deposit(address(z), 100 * 1e6, false, bytes32(0));

        IPerpEngine.Fill memory f = IPerpEngine.Fill({
            fillId: keccak256("fillL"),
            account: address(this),
            marketId: MARKET,
            isBuy: true,
            size: 100 * 1e6,
            priceZ: 1e18,
            feeZ: 0,
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });
        engine.recordFill(f);

        // make equity < MMR by setting price high then low if needed
        spo.setPrice(address(z), 2e18, uint64(block.timestamp));
        spo.setPrice(address(z), 0.5e18, uint64(block.timestamp));

        engine.liquidate(address(this), MARKET);
        assertEq(engine.getPosition(address(this), MARKET), 0);
    }
}
