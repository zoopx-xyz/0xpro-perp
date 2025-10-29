// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetMapper} from "../src/bridge/AssetMapper.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AssetMapperTest is Test {
    AssetMapper mapper;
    address admin = address(this);

    function setUp() public {
        AssetMapper impl = new AssetMapper();
        bytes memory data = abi.encodeWithSelector(AssetMapper.initialize.selector, admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        mapper = AssetMapper(address(proxy));
    }

    function testSetAndGetMapping() public {
        bytes32 chain = keccak256("op-sepolia");
        address sat = address(0xBEEF);
        address base = address(0xCAFE);

        vm.expectEmit(true, true, true, true);
        emit AssetMapper.MappingSet(chain, sat, base);
        mapper.setMapping(chain, sat, base);

        assertEq(mapper.getBaseAsset(chain, sat), base);
        assertEq(mapper.getSatelliteAsset(chain, base), sat);
    }

    function testOnlyAdminCanSetMapping() public {
        bytes32 chain = keccak256("op-sepolia");
        address sat = address(0x1);
        address base = address(0x2);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        mapper.setMapping(chain, sat, base);
    }

    function testRevertOnZeroAddresses() public {
        bytes32 chain = keccak256("chain");
        vm.expectRevert(bytes("zero addr"));
        mapper.setMapping(chain, address(0), address(0x2));
        vm.expectRevert(bytes("zero addr"));
        mapper.setMapping(chain, address(0x1), address(0));
    }

    function testGettersReturnZeroForUnmapped() public {
        bytes32 chain = keccak256("unmapped-chain");
        address sat = address(0x111);
        address base = address(0x222);

        // before mapping
        assertEq(mapper.getBaseAsset(chain, sat), address(0));
        assertEq(mapper.getSatelliteAsset(chain, base), address(0));

        // after mapping
        mapper.setMapping(chain, sat, base);
        assertEq(mapper.getBaseAsset(chain, sat), base);
        assertEq(mapper.getSatelliteAsset(chain, base), sat);
    }

    function testNonAdminCannotUpgrade() public {
        address newImpl = address(0x789);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        mapper.upgradeToAndCall(newImpl, "");
    }

    function testMappingOverwrite() public {
        bytes32 chain = keccak256("test-chain");
        address sat1 = address(0x111);
        address sat2 = address(0x222);
        address base = address(0x333);

        // first mapping
        mapper.setMapping(chain, sat1, base);
        assertEq(mapper.getBaseAsset(chain, sat1), base);

        // overwrite with different satellite for same base
        mapper.setMapping(chain, sat2, base);
        assertEq(mapper.getBaseAsset(chain, sat2), base);
        assertEq(mapper.getSatelliteAsset(chain, base), sat2);
        // old mapping should still exist
        assertEq(mapper.getBaseAsset(chain, sat1), base);
    }
}
