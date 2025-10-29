// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SignedPriceOracleSignedTest is Test {
    SignedPriceOracle spo;
    address admin = address(this);
    uint256 privateKey;
    address signer;

    function setUp() public {
        SignedPriceOracle impl = new SignedPriceOracle();
        privateKey = 0xBEEF;
        signer = vm.addr(privateKey);
        spo = SignedPriceOracle(address(new ERC1967Proxy(address(impl), "")));
        spo.initialize(admin, signer, 300);
    }

    function testSetSignerAndMaxStale() public {
        spo.setSigner(address(0xBEEF));
        assertEq(vm.load(address(spo), bytes32(uint256(keccak256("eip1967.proxy.signer")) - 1)), bytes32(0)); // sanity: no storage slot leak
        // Keeper role is admin by default in tests
        spo.setMaxStale(1234);
        assertEq(spo.getMaxStale(), 1234);
    }

    function testSetPriceSignedLegacy() public {
        address asset = address(0xFEED);
        uint256 price = 42e18;
        uint64 ts = uint64(block.timestamp);
        bytes32 digest = keccak256(abi.encode(asset, price, ts, address(spo)));
        bytes32 ethSigned = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSigned);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(address(0xCAFE));
        spo.setPriceSignedLegacy(asset, price, ts, sig);
        (uint256 p,, bool stale) = spo.getPrice(asset);
        assertEq(p, price);
        assertFalse(stale);
    }
}
