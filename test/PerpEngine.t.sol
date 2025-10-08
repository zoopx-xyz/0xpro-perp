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

        // grant engine role to self for vault hooks tests (MVP simplification)
        // In production, vault would grant ENGINE to PerpEngine only
    }

    function _deployProxy(address impl) internal returns (address) {
        bytes memory code = abi.encodePacked(hex"3d602d80600a3d3981f3", hex"363d3d373d3d3d363d73", bytes20(impl), hex"5af43d82803e903d91602b57fd5bf3");
        address proxy;
        assembly { proxy := create(0, add(code, 0x20), mload(code)) }
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
            ts: uint64(block.timestamp)
        });
        engine.recordFill(f);
        vm.expectRevert(bytes("dup fillId"));
        engine.recordFill(f);
    }
}
