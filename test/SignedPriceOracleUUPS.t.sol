// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SignedPriceOracle} from "../src/core/SignedPriceOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SignedPriceOracleUUPSTest is Test {
    SignedPriceOracle proxyOracle;
    SignedPriceOracle impl;
    address admin = address(this);
    address signer;
    uint256 signerPk;

    function setUp() public {
        (signer, signerPk) = makeAddrAndKey("signer");
        impl = new SignedPriceOracle();
        bytes memory initData = abi.encodeWithSelector(SignedPriceOracle.initialize.selector, admin, signer, uint64(3600));
        proxyOracle = SignedPriceOracle(address(new ERC1967Proxy(address(impl), initData)));
    }

    function testImplementationInitializeReverts() public {
        vm.expectRevert();
        impl.initialize(admin, signer, 0);
    }

    function testUpgradeByAdminSucceeds() public {
        SignedPriceOracle newImpl = new SignedPriceOracle();
        proxyOracle.upgradeTo(address(newImpl));
        // getter sanity
        assertEq(proxyOracle.getMaxStale(), 3600);
    }

    function testSetPriceSignedEIP712() public {
        address asset = address(0xA);
        uint256 px = 123e18;
        uint64 ts = uint64(block.timestamp);
        uint256 nonce = proxyOracle.nonces(signer);
        bytes32 typehash = proxyOracle.PRICE_TYPEHASH();
        bytes32 structHash = keccak256(abi.encode(typehash, asset, px, ts, nonce));
        // build EIP712 domain separator
        bytes32 EIP712_DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256(bytes("SignedPriceOracle"));
        bytes32 versionHash = keccak256(bytes("1"));
        bytes32 domainSeparator = keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            nameHash,
            versionHash,
            block.chainid,
            address(proxyOracle)
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        proxyOracle.setPriceSigned(asset, px, ts, sig);
        (uint256 readPx,,) = proxyOracle.getPrice(asset);
        assertEq(readPx, px);
        // replay should fail due to nonce increment
        vm.expectRevert(bytes("bad sig"));
        proxyOracle.setPriceSigned(asset, px, ts, sig);
    }
}
