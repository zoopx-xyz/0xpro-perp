// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowGateway} from "../src/satellite/EscrowGateway.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract MockAdapterGood {
    function sendDeposit(address, address, uint256, bytes32, bytes32) external pure returns (bool) {
        return true;
    }
}

contract MockAdapterBad {
    function sendDeposit(address, address, uint256, bytes32, bytes32) external pure {
        revert("adapter failed");
    }
}

contract EscrowGatewayMoreTest is Test {
    EscrowGateway escrow;
    MockERC20 token;
    MockAdapterGood goodAdapter;
    MockAdapterBad badAdapter;
    
    address admin = address(this);
    address user = address(0xBEEF);
    bytes32 chain = keccak256("dst");

    function setUp() public {
        token = new MockERC20("TEST", "TEST", 18);
        token.transferOwnership(admin);
        
        EscrowGateway impl = new EscrowGateway();
        escrow = EscrowGateway(address(new ERC1967Proxy(address(impl), 
            abi.encodeWithSelector(EscrowGateway.initialize.selector, admin))));
        
        goodAdapter = new MockAdapterGood();
        badAdapter = new MockAdapterBad();
        
        // Setup token and approvals
        token.mint(user, 1000 ether);
        vm.prank(user);
        token.approve(address(escrow), type(uint256).max);
        
        escrow.setSupportedAsset(address(token), true);
    }

    function testDepositWithAdapterSuccess() public {
        escrow.setMessageSenderAdapter(address(goodAdapter));
        
        vm.prank(user);
        escrow.deposit(address(token), 100 ether, chain);
        
        // Check token was escrowed
        assertEq(token.balanceOf(address(escrow)), 100 ether);
        assertEq(token.balanceOf(user), 900 ether);
    }

    function testDepositWithAdapterFailure() public {
        escrow.setMessageSenderAdapter(address(badAdapter));
        
        vm.prank(user);
        vm.expectRevert(bytes("sender adapter call failed"));
        escrow.deposit(address(token), 100 ether, chain);
    }

    function testDepositUnsupportedAsset() public {
        MockERC20 unsupported = new MockERC20("BAD", "BAD", 18);
        vm.prank(user);
        vm.expectRevert(bytes("asset not supported"));
        escrow.deposit(address(unsupported), 1, chain);
    }

    function testDepositZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(bytes("amount=0"));
        escrow.deposit(address(token), 0, chain);
    }

    function testSettersAndEvents() public {
        vm.expectEmit(true, false, false, true);
        emit EscrowGateway.MessageSenderAdapterSet(address(goodAdapter));
        escrow.setMessageSenderAdapter(address(goodAdapter));
        
        vm.expectEmit(true, false, false, true);
        emit EscrowGateway.SupportedAssetSet(address(0x123), true);
        escrow.setSupportedAsset(address(0x123), true);
    }

    function testCompleteWithdrawalTransfersAndEmits() public {
        // First deposit so escrow holds funds
        escrow.setMessageSenderAdapter(address(0));
        vm.prank(user);
        escrow.deposit(address(token), 200 ether, chain);

        // completeWithdrawal can be called by MESSAGE_RECEIVER_ROLE (admin has it)
        bytes32 wid = keccak256("wd-1");
        uint256 beforeUser = token.balanceOf(user);
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit EscrowGateway.WithdrawalReleased(user, address(token), 50 ether, wid);
        escrow.completeWithdrawal(user, address(token), 50 ether, wid);
        assertEq(token.balanceOf(user), beforeUser + 50 ether);
    }

    function testOnlyAdminCanSetters() public {
        address stranger = address(0xBAD);
        // setMessageSenderAdapter
        vm.prank(stranger);
        vm.expectRevert();
        escrow.setMessageSenderAdapter(address(goodAdapter));
        // setSupportedAsset
        vm.prank(stranger);
        vm.expectRevert();
        escrow.setSupportedAsset(address(token), true);
    }
}
