// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BridgeAdapter} from "../src/bridge/BridgeAdapter.sol";
import {IBridgeableVault} from "../src/core/interfaces/IBridgeableVault.sol";
import {Constants} from "../lib/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockVault2 is IBridgeableVault {
    event Minted(address user, address asset, uint256 amount, bytes32 depositId);
    event Burned(address user, address asset, uint256 amount, bytes32 withdrawalId);

    function mintCreditFromBridge(address user, address asset, uint256 amount, bytes32 depositId) external {
        emit Minted(user, asset, amount, depositId);
    }

    function burnCreditForBridge(address user, address asset, uint256 amount, bytes32 withdrawalId) external {
        emit Burned(user, asset, amount, withdrawalId);
    }
}

contract MockSenderAdapter {
    address public lastUser;
    address public lastAsset;
    uint256 public lastAmount;
    bytes32 public lastWithdrawalId;
    bytes32 public lastDst;

    function sendWithdrawal(address user, address asset, uint256 amount, bytes32 withdrawalId, bytes32 dst) external {
        lastUser = user;
        lastAsset = asset;
        lastAmount = amount;
        lastWithdrawalId = withdrawalId;
        lastDst = dst;
    }
}

contract BridgeAdapterLimitsTest is Test {
    BridgeAdapter bridge;
    MockVault2 vault;
    address admin = address(this);
    address user = address(0xBEEF);
    address asset = address(0xA);
    bytes32 chain = keccak256("dst");

    function setUp() public {
        vault = new MockVault2();
        BridgeAdapter impl = new BridgeAdapter();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl), abi.encodeWithSelector(BridgeAdapter.initialize.selector, admin, address(vault))
        );
        bridge = BridgeAdapter(address(proxy));
        // grant receiver role to this test for calling creditFromMessage
        bridge.grantRole(Constants.MESSAGE_RECEIVER_ROLE, address(this));
    }

    function testCreditWithLimits() public {
        // enable limits: 1000 per asset per window, 600 per user per window, window=1 hour
        bridge.setLimits(asset, 1000, 600, 3600, true);

        // First credit within limits
        bridge.creditFromMessage(user, asset, 500, keccak256("d1"), chain);
        // Second credit of 200 OK (user total 700 would exceed 600)
        vm.expectRevert(bytes("user limit"));
        bridge.creditFromMessage(user, asset, 200, keccak256("d2"), chain);

        // Different user within per-asset limit
        bridge.creditFromMessage(address(0xC0FFEE), asset, 400, keccak256("d3"), chain);
        // Next credit would exceed per-asset window (500 + 400 + 200 > 1000) even if user ok
        vm.expectRevert(bytes("asset limit"));
        bridge.creditFromMessage(address(0xD00D), asset, 200, keccak256("d4"), chain);
    }

    function testInitiateWithdrawalForwardsToSenderAdapter() public {
        // set outbound sender adapter
        MockSenderAdapter msa = new MockSenderAdapter();
        bridge.setMessageSenderAdapter(address(msa));

        // initiate withdrawal burns and forwards
        bytes32 wid = bridge.initiateWithdrawal(asset, 123, chain);
        // fields captured in mock
        assertEq(msa.lastUser(), address(this));
        assertEq(msa.lastAsset(), asset);
        assertEq(msa.lastAmount(), 123);
        assertEq(msa.lastWithdrawalId(), wid);
        assertEq(msa.lastDst(), chain);
    }
}
