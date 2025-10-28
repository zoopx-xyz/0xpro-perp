// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AssetMapper} from "../src/bridge/AssetMapper.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AssetMapperUUPSTest is Test {
    AssetMapper proxyMap;
    AssetMapper impl;
    address admin = address(this);

    function setUp() public {
        impl = new AssetMapper();
        bytes memory initData = abi.encodeWithSelector(AssetMapper.initialize.selector, admin);
        proxyMap = AssetMapper(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testImplementationInitializeReverts() public {
        vm.expectRevert();
        impl.initialize(admin);
    }

    function testUpgradeByAdminSucceeds() public {
        AssetMapper newImpl = new AssetMapper();
        proxyMap.upgradeTo(address(newImpl));
        // basic path still works
        bytes32 chain = keccak256("OP");
        proxyMap.setMapping(chain, address(0xA), address(0xB));
        assertEq(proxyMap.getBaseAsset(chain, address(0xA)), address(0xB));
    }
}
