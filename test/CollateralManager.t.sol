// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";

contract CollateralManagerTest is Test {
    CollateralManager cm;
    OracleRouter orac;
    SignedPriceOracle spo;
    MockERC20 m;

    function setUp() public {
        cm = CollateralManager(_deployProxy(address(new CollateralManager())));
        orac = OracleRouter(_deployProxy(address(new OracleRouter())));
        spo = SignedPriceOracle(_deployProxy(address(new SignedPriceOracle())));

        cm.initialize(address(this), address(orac));
        orac.initialize(address(this));
        spo.initialize(address(this), address(0), 300);

        m = new MockERC20("mock", "m", 6);
        orac.registerAdapter(address(m), address(spo));
        cm.setAssetConfig(address(m), true, 10000, address(orac), 6);
        spo.setPrice(address(m), 2e18, uint64(block.timestamp));
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

    function testAssetValue() public {
        uint256 v = cm.assetValueInZUSD(address(m), 1_000_000); // 1 token with 6 decimals at $2
        assertEq(v, 2e18);
    }

    function testCollateralValueLTV() public {
        uint256 v = cm.collateralValueInZUSD(address(m), 1_000_000); // ltv 100%
        assertEq(v, 2e18);
    }
}
