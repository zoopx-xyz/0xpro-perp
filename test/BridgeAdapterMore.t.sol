// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BridgeAdapter} from "../src/bridge/BridgeAdapter.sol";
import {IBridgeableVault} from "../src/core/interfaces/IBridgeableVault.sol";
import {Constants} from "../lib/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockVaultBA is IBridgeableVault {
    event Minted(address user, address asset, uint256 amount, bytes32 depositId);
    event Burned(address user, address asset, uint256 amount, bytes32 withdrawalId);

    function mintCreditFromBridge(address user, address asset, uint256 amount, bytes32 depositId) external {
        emit Minted(user, asset, amount, depositId);
    }

    function burnCreditForBridge(address user, address asset, uint256 amount, bytes32 withdrawalId) external {
        emit Burned(user, asset, amount, withdrawalId);
    }
}

contract RevertingSenderAdapter {
    function sendWithdrawal(address, address, uint256, bytes32, bytes32) external pure {
        revert("nope");
    }
}

contract GoodSenderAdapter {
    // no revert, no return value -> low-level call ok=true
    function sendWithdrawal(address, address, uint256, bytes32, bytes32) external pure {}
}

contract BridgeAdapterMoreTest is Test {
    BridgeAdapter bridge;
    BridgeAdapter impl;
    MockVaultBA vault;

    address admin = address(this);
    address user = address(0xBEEF);
    address asset = address(0xA);
    bytes32 chain = keccak256("dst");

    function setUp() public {
        vault = new MockVaultBA();
        impl = new BridgeAdapter();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(BridgeAdapter.initialize.selector, admin, address(vault))
        );
        bridge = BridgeAdapter(address(proxy));
        // Grant receiver role to this test by default
        bridge.grantRole(Constants.MESSAGE_RECEIVER_ROLE, address(this));
    }

    function testOnlyReceiverCanCredit() public {
        // revoke for negative test by using prank from another address
        vm.prank(address(0x1234));
        vm.expectRevert();
        bridge.creditFromMessage(user, asset, 1, keccak256("d0"), chain);
    }

    function testInitiateWithdrawalAmountZeroReverts() public {
        vm.expectRevert(bytes("amount=0"));
        bridge.initiateWithdrawal(asset, 0, chain);
    }

    function testSenderAdapterFailureReverts() public {
        // set an adapter that reverts
        RevertingSenderAdapter rsa = new RevertingSenderAdapter();
        bridge.setMessageSenderAdapter(address(rsa));
        // will attempt to call and must revert with the adapter failure guard
        vm.expectRevert(bytes("sender adapter call failed"));
        bridge.initiateWithdrawal(asset, 1, chain);
    }

    function testInitiateWithdrawalWithAdapterSuccess() public {
        // set an adapter that does not revert; low-level call returns ok=true
        GoodSenderAdapter gsa = new GoodSenderAdapter();
        bridge.setMessageSenderAdapter(address(gsa));
        bytes32 wid = bridge.initiateWithdrawal(asset, 2, chain);
        assertTrue(wid != bytes32(0));
    }

    function testCreditWithZeroWindowLimits() public {
        // windowSeconds = 0 => use bucket 0; limits should accumulate in same window
        bridge.setLimits(asset, 10, 6, 0, true);
        bridge.creditFromMessage(user, asset, 5, keccak256("d1"), chain);
        // user limit exceeded (5 + 2 > 6)
        vm.expectRevert(bytes("user limit"));
        bridge.creditFromMessage(user, asset, 2, keccak256("d2"), chain);
        // different user ok up to asset limit
        bridge.creditFromMessage(address(0xC0FFEE), asset, 5, keccak256("d3"), chain);
        // now asset window exceeded (5 + 5 + 1 > 10)
        vm.expectRevert(bytes("asset limit"));
        bridge.creditFromMessage(address(0xD00D), asset, 1, keccak256("d4"), chain);
    }

    function testCreditWhenLimitsDisabledSkipsChecks() public {
        // enable with zeroes but disabled flag => no checks
        bridge.setLimits(asset, 0, 0, 3600, false);
        // should not revert
        bridge.creditFromMessage(user, asset, 1_000_000, keccak256("d5"), chain);
    }

    function testSetVaultAndUUPSUpgrade() public {
        // setVault emits and updates
        MockVaultBA newVault = new MockVaultBA();
        bridge.setVault(address(newVault));
        // UUPS upgrade
        BridgeAdapter newImpl = new BridgeAdapter();
        bridge.upgradeTo(address(newImpl));
        // implementation initialize should revert
        vm.expectRevert();
        newImpl.initialize(admin, address(newVault));
        // still works through proxy after upgrade
        bridge.setMessageSenderAdapter(address(0));
        bytes32 wid = bridge.initiateWithdrawal(asset, 2, chain);
        assertTrue(wid != bytes32(0));
    }

    function testOnlyAdminCanSetters() public {
        address stranger = address(0xBAD);
        // setVault
        vm.prank(stranger);
        vm.expectRevert();
        bridge.setVault(address(vault));
        // setMessageSenderAdapter
        vm.prank(stranger);
        vm.expectRevert();
        bridge.setMessageSenderAdapter(address(0x1));
        // setLimits
        vm.prank(stranger);
        vm.expectRevert();
        bridge.setLimits(address(0xA), 1, 1, 1, true);
    }
}
