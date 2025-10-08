// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MarginVaultV2} from "../src/core/MarginVaultV2.sol";
import {CollateralManager} from "../src/core/CollateralManager.sol";
import {OracleRouter} from "../src/core/OracleRouter.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";

contract MarginVaultWithdrawGuardTest is Test {
    MarginVaultV2 vault;
    CollateralManager cm;
    OracleRouter orac;
    SignedPriceOracle spo;
    MockERC20 usdc;

    function setUp() public {
        cm = CollateralManager(_p(address(new CollateralManager())));
        orac = OracleRouter(_p(address(new OracleRouter())));
        spo = SignedPriceOracle(_p(address(new SignedPriceOracle())));
        vault = MarginVaultV2(_p(address(new MarginVaultV2())));

        cm.initialize(address(this), address(orac));
        orac.initialize(address(this));
        spo.initialize(address(this), address(0), 300);
        vault.initialize(address(this), address(cm));

        usdc = new MockERC20("mockUSDC", "mUSDC", 6);
        orac.registerAdapter(address(usdc), address(spo));
        cm.setAssetConfig(address(usdc), true, 10000, address(orac), 6);
        spo.setPrice(address(usdc), 1e18, uint64(block.timestamp));

        usdc.mint(address(this), 10_000 * 1e6);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _p(address impl) internal returns (address) {
        bytes memory code = abi.encodePacked(hex"3d602d80600a3d3981f3", hex"363d3d373d3d3d363d73", bytes20(impl), hex"5af43d82803e903d91602b57fd5bf3");
        address proxy;
        assembly { proxy := create(0, add(code, 0x20), mload(code)) }
        require(proxy != address(0), "proxy fail");
        return proxy;
    }

    function testWithdrawWithinEquityPasses() public {
        vault.deposit(address(usdc), 1_000_000, false, bytes32(0));
        vault.withdraw(address(usdc), 500_000, false, bytes32(0));
        assertEq(usdc.balanceOf(address(this)), (10_000 * 1e6) - 500_000);
    }
}
