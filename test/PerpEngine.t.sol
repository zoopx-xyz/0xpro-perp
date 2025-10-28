// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PerpEngine} from "../src/core/PerpEngine.sol";
import {IPerpEngine} from "../src/core/interfaces/IPerpEngine.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";

contract PerpEngineTest is Test {
    PerpEngine engine;
    MarginVaultV2 vault;
    CollateralManager cm;
    OracleRouter orac;
    SignedPriceOracle spo;
    MockERC20 z;

    bytes32 constant MARKET = keccak256("BTC-PERP");

    function setUp() public {
        cm = CollateralManager(_deployProxy(address(new CollateralManager())));
        orac = OracleRouter(_deployProxy(address(new OracleRouter())));
        spo = SignedPriceOracle(_deployProxy(address(new SignedPriceOracle())));
        vault = MarginVaultV2(_deployProxy(address(new MarginVaultV2())));
        engine = PerpEngine(_deployProxy(address(new PerpEngine())));

        cm.initialize(address(this), address(orac));
        orac.initialize(address(this));
        spo.initialize(address(this), address(0), 300);
        vault.initialize(address(this), address(cm));
        engine.initialize(address(this), address(vault));

        z = new MockERC20("mockzUSD", "mzUSD", 6);
        orac.registerAdapter(address(z), address(spo));
        cm.setAssetConfig(address(z), true, 10000, address(orac), 6);
        spo.setPrice(address(z), 1e18, uint64(block.timestamp));

        // wire
        engine.setDeps(address(0), address(orac), address(cm), address(0), address(0), address(0), address(z));
        engine.registerMarket(MARKET, address(z), 6);
    }

    function _deployProxy(address impl) internal returns (address) {
        bytes memory code = abi.encodePacked(
            hex"3d602d80600a3d3981f3", hex"363d3d373d3d3d363d73", bytes20(impl), hex"5af43d82803e903d91602b57fd5bf3"
        );
        address proxy;
        assembly {
            proxy := create(0, add(code, 0x20), mload(code))
        }
        require(proxy != address(0), "proxy fail");
        return proxy;
    }

    function testRecordFillIdempotent() public {
        IPerpEngine.Fill memory f = IPerpEngine.Fill({
            fillId: keccak256("fill1"),
            account: address(this),
            marketId: MARKET,
            isBuy: true,
            size: 1e6, // arbitrary
            priceZ: 1e18,
            feeZ: 1000,
            fundingZ: 0,
            ts: uint64(block.timestamp),
            orderDigest: keccak256("fill1")
        });
        engine.recordFill(f);
        vm.expectRevert(bytes("dup fillId"));
        engine.recordFill(f);
    }

    function testGetPositionMarginRatio_NoPositionReturnsMax() public {
        // No position for this account -> expect max uint
        uint256 mr = engine.getPositionMarginRatioBps(address(this), MARKET);
        assertEq(mr, type(uint256).max);
    }

    function testGetPositionMarginRatio_StalePriceReturnsZero() public {
        // Open a small position via recordFill, then warp to make price stale
        IPerpEngine.Fill memory f = IPerpEngine.Fill({
            fillId: keccak256("fill-stale"),
            account: address(this),
            marketId: MARKET,
            isBuy: true,
            size: 1e6,
            priceZ: 1e18,
            feeZ: 0,
            fundingZ: 0,
            ts: uint64(block.timestamp),
            orderDigest: keccak256("fill-stale")
        });
        engine.recordFill(f);
        // Make price stale (SignedPriceOracle maxStale=300 in setUp)
        vm.warp(block.timestamp + 301);
        uint256 mr = engine.getPositionMarginRatioBps(address(this), MARKET);
        assertEq(mr, 0);
    }

    function testGetPositionMarginRatio_PositiveEquity() public {
        // Deposit collateral to have positive equity
        z.mint(address(this), 1_000_000); // 1 z (6 decimals)
        z.approve(address(vault), type(uint256).max);
        vault.deposit(address(z), 1_000_000, false, bytes32(0));

        // Open a small position so denominator (notional) > 0
        IPerpEngine.Fill memory f = IPerpEngine.Fill({
            fillId: keccak256("fill-pos"),
            account: address(this),
            marketId: MARKET,
            isBuy: true,
            size: 1e6,
            priceZ: 1e18,
            feeZ: 0,
            fundingZ: 0,
            ts: uint64(block.timestamp),
            orderDigest: keccak256("fill-pos")
        });
        engine.recordFill(f);

        uint256 mr = engine.getPositionMarginRatioBps(address(this), MARKET);
        // With $1 equity and $1 notional, expect ~10000 bps (allow exact equality)
        assertEq(mr, 10_000);
    }
}
