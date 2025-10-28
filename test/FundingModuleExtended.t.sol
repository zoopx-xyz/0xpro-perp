// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FundingModule} from "../src/core/FundingModule.sol";
import {Constants} from "../lib/Constants.sol";

contract FundingModuleExtendedTest is Test {
    FundingModule funding;
    
    function setUp() public {
        funding = FundingModule(_deployProxy(address(new FundingModule())));
        funding.initialize(address(this));
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

    function testInitializeGrantsBothRoles() public {
        // Deploy a fresh instance to test initialization
        FundingModule freshFunding = FundingModule(_deployProxy(address(new FundingModule())));
        address admin = address(0x789);
        
        freshFunding.initialize(admin);
        
        // Check that both admin and keeper roles were granted
        assertTrue(freshFunding.hasRole(Constants.DEFAULT_ADMIN, admin));
        assertTrue(freshFunding.hasRole(Constants.KEEPER, admin));
    }
    
    function testInitializeCanOnlyBeCalledOnce() public {
        // Try to initialize again - should revert
        vm.expectRevert();
        funding.initialize(address(0x999));
    }
    
    function testConstructorDisablesInitializers() public {
        // The constructor should have disabled initializers
        FundingModule impl = new FundingModule();
        
        // Trying to initialize implementation directly should revert
        vm.expectRevert();
        impl.initialize(address(0x456));
    }

    function testUpdateFundingIndexOnlyKeeper() public {
        bytes32 marketId = keccak256("BTC-PERP");
        int128 delta = 1000;
        
        // Should work for keeper (this contract has both admin and keeper roles)
        vm.expectEmit(true, true, true, true);
        emit FundingModule.FundingUpdated(marketId, delta, delta);
        
        funding.updateFundingIndex(marketId, delta);
        assertEq(funding.getFundingIndex(marketId), delta);
        
        // Should fail for non-keeper
        vm.prank(address(0xBAD));
        vm.expectRevert();
        funding.updateFundingIndex(marketId, 500);
    }
    
    function testUpdateFundingIndexAccumulates() public {
        bytes32 marketId = keccak256("ETH-PERP");
        int128 delta1 = 1500;
        int128 delta2 = -500;
        int128 delta3 = 2000;
        
        // First update
        funding.updateFundingIndex(marketId, delta1);
        assertEq(funding.getFundingIndex(marketId), delta1);
        
        // Second update - should accumulate
        vm.expectEmit(true, true, true, true);
        emit FundingModule.FundingUpdated(marketId, delta1 + delta2, delta2);
        
        funding.updateFundingIndex(marketId, delta2);
        assertEq(funding.getFundingIndex(marketId), delta1 + delta2);
        
        // Third update - should accumulate further
        funding.updateFundingIndex(marketId, delta3);
        assertEq(funding.getFundingIndex(marketId), delta1 + delta2 + delta3);
    }
    
    function testGetFundingIndexDefaultsToZero() public {
        bytes32 nonExistentMarket = keccak256("NONEXISTENT-PERP");
        assertEq(funding.getFundingIndex(nonExistentMarket), 0);
    }
    
    function testNegativeFundingDeltas() public {
        bytes32 marketId = keccak256("SOL-PERP");
        int128 negativeDelta = -2500;
        
        vm.expectEmit(true, true, true, true);
        emit FundingModule.FundingUpdated(marketId, negativeDelta, negativeDelta);
        
        funding.updateFundingIndex(marketId, negativeDelta);
        assertEq(funding.getFundingIndex(marketId), negativeDelta);
        
        // Add positive delta to test accumulation with negative
        int128 positiveDelta = 1000;
        funding.updateFundingIndex(marketId, positiveDelta);
        assertEq(funding.getFundingIndex(marketId), negativeDelta + positiveDelta);
    }
    
    function testMultipleMarketsIndependent() public {
        bytes32 market1 = keccak256("BTC-PERP");
        bytes32 market2 = keccak256("ETH-PERP");
        int128 delta1 = 1000;
        int128 delta2 = 2000;
        
        funding.updateFundingIndex(market1, delta1);
        funding.updateFundingIndex(market2, delta2);
        
        // Markets should have independent indices
        assertEq(funding.getFundingIndex(market1), delta1);
        assertEq(funding.getFundingIndex(market2), delta2);
        
        // Update one market - shouldn't affect the other
        funding.updateFundingIndex(market1, 500);
        assertEq(funding.getFundingIndex(market1), delta1 + 500);
        assertEq(funding.getFundingIndex(market2), delta2); // unchanged
    }

    function testZeroFundingDelta() public {
        bytes32 marketId = keccak256("AVAX-PERP");
        int128 zeroDelta = 0;
        
        vm.expectEmit(true, true, true, true);
        emit FundingModule.FundingUpdated(marketId, zeroDelta, zeroDelta);
        
        funding.updateFundingIndex(marketId, zeroDelta);
        assertEq(funding.getFundingIndex(marketId), 0);
        
        // Even after zero delta, further updates should work normally
        int128 nonZeroDelta = 1500;
        funding.updateFundingIndex(marketId, nonZeroDelta);
        assertEq(funding.getFundingIndex(marketId), nonZeroDelta);
    }
}