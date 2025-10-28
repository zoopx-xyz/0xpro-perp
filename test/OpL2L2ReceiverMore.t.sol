// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IL2ToL2CrossDomainMessenger} from "../src/bridge/op/IL2ToL2CrossDomainMessenger.sol";
import {OpL2L2Receiver} from "../src/bridge/op/OpL2L2Receiver.sol";
import {AssetMapper} from "../src/bridge/AssetMapper.sol";
import {BridgeAdapter} from "../src/bridge/BridgeAdapter.sol";
import {EscrowGateway} from "../src/satellite/EscrowGateway.sol";
import {MockERC20} from "../src/tokens/MockERC20.sol";
import {IBridgeableVault} from "../src/core/interfaces/IBridgeableVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Constants} from "../lib/Constants.sol";

contract MockVaultR is IBridgeableVault {
    function mintCreditFromBridge(address, address, uint256, bytes32) external {}
    function burnCreditForBridge(address, address, uint256, bytes32) external {}
}

contract MockMessengerR is IL2ToL2CrossDomainMessenger {
    address private _xSender;
    function setXSender(address s) external { _xSender = s; }
    function sendMessage(address, bytes calldata, uint32) external {}
    function xDomainMessageSender() external view returns (address) { return _xSender; }
}

contract OpL2L2ReceiverMoreTest is Test {
    MockMessengerR messenger;
    OpL2L2Receiver receiver;
    AssetMapper mapper;
    BridgeAdapter bridge;
    EscrowGateway escrow;
    MockVaultR vault;
    
    address admin = address(this);
    address sender = address(0x123);

    function setUp() public {
        messenger = new MockMessengerR();
        vault = new MockVaultR();
        
        // Deploy receiver
        OpL2L2Receiver rImpl = new OpL2L2Receiver();
        receiver = OpL2L2Receiver(address(new ERC1967Proxy(address(rImpl), 
            abi.encodeWithSelector(OpL2L2Receiver.initialize.selector, admin, address(messenger), sender))));
        
        // Deploy mapper
        AssetMapper mImpl = new AssetMapper();
        mapper = AssetMapper(address(new ERC1967Proxy(address(mImpl), 
            abi.encodeWithSelector(AssetMapper.initialize.selector, admin))));
        
        // Deploy bridge
        BridgeAdapter bImpl = new BridgeAdapter();
        bridge = BridgeAdapter(address(new ERC1967Proxy(address(bImpl), 
            abi.encodeWithSelector(BridgeAdapter.initialize.selector, admin, address(vault)))));
        
        // Deploy escrow
        EscrowGateway eImpl = new EscrowGateway();
        escrow = EscrowGateway(address(new ERC1967Proxy(address(eImpl), 
            abi.encodeWithSelector(EscrowGateway.initialize.selector, admin))));
        
        // Grant roles
        bridge.grantRole(Constants.MESSAGE_RECEIVER_ROLE, address(receiver));
        escrow.grantRole(Constants.MESSAGE_RECEIVER_ROLE, address(receiver));
    }

    function testSettersAndEvents() public {
        // set all components and verify events
        vm.expectEmit(true, false, false, true);
        emit OpL2L2Receiver.BridgeAdapterSet(address(bridge));
        receiver.setBridgeAdapter(address(bridge));
        
        vm.expectEmit(true, false, false, true);
        emit OpL2L2Receiver.EscrowGatewaySet(address(escrow));
        receiver.setEscrowGateway(address(escrow));
        
        vm.expectEmit(true, false, false, true);
        emit OpL2L2Receiver.AssetMapperSet(address(mapper));
        receiver.setAssetMapper(address(mapper));
        
        // set messenger and remote sender
        address newMessenger = address(0xDEAD);
        vm.expectEmit(true, false, false, true);
        emit OpL2L2Receiver.MessengerSet(newMessenger);
        receiver.setMessenger(newMessenger);
        
        address newRemote = address(0xBEEF);
        vm.expectEmit(true, false, false, true);
        emit OpL2L2Receiver.RemoteSenderSet(newRemote);
        receiver.setRemoteSender(newRemote);
        
        // set to default messenger
        receiver.setMessengerToDefault();
    }

    function testAccessControlSetters() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        receiver.setBridgeAdapter(address(bridge));
        
        vm.prank(address(0xBAD));
        vm.expectRevert();
        receiver.setAssetMapper(address(mapper));
    }

    function testReplayProtectionOnDeposit() public {
        // wire deps
        receiver.setBridgeAdapter(address(bridge));
        receiver.setAssetMapper(address(mapper));
        // configure mapping
        bytes32 chain = keccak256("dst");
        address sat = address(0xCA7);
        address base = address(0xBEEF);
        mapper.setMapping(chain, sat, base);
        // set messenger xSender to expected remote
        messenger.setXSender(sender);
        // First call as messenger should succeed
        vm.prank(address(messenger));
        receiver.onDepositMessage(address(0xA11CE), sat, 1, keccak256("dep1"), chain);
        // Replay same depositId should revert
        vm.prank(address(messenger));
        vm.expectRevert(bytes("replayed"));
        receiver.onDepositMessage(address(0xA11CE), sat, 1, keccak256("dep1"), chain);
    }

    function testDepositMappingMissingReverts() public {
        receiver.setBridgeAdapter(address(bridge));
        receiver.setAssetMapper(address(mapper));
        bytes32 chain = keccak256("dst");
        address sat = address(0xCA7);
        messenger.setXSender(sender);
        vm.prank(address(messenger));
        vm.expectRevert(bytes("asset mapping missing"));
        receiver.onDepositMessage(address(0xA11CE), sat, 1, keccak256("dep2"), chain);
    }

    function testDepositBadXSenderReverts() public {
        receiver.setBridgeAdapter(address(bridge));
        receiver.setAssetMapper(address(mapper));
        bytes32 chain = keccak256("dst");
        address sat = address(0xCA7);
        // Configure mapping so we pass mapping check if reached
        address base = address(0xBEEF);
        mapper.setMapping(chain, sat, base);
        // Set messenger to wrong xSender
        messenger.setXSender(address(0xBAD));
        vm.prank(address(messenger));
        vm.expectRevert(bytes("bad xSender"));
        receiver.onDepositMessage(address(0xA11CE), sat, 1, keccak256("depBad"), chain);
    }

    function testWithdrawalReplayProtection() public {
        receiver.setEscrowGateway(address(escrow));
        // correct xSender
        messenger.setXSender(sender);
        bytes32 chain = keccak256("dst");
        // use a real ERC20 so escrow.transfer succeeds
        MockERC20 satToken = new MockERC20("SAT","SAT",18);
        address sat = address(satToken);
        // fund escrow so it can transfer out
        satToken.mint(address(escrow), 10 ether);
        bytes32 wdId = keccak256("wd1");
        // First call
        vm.prank(address(messenger));
        receiver.onWithdrawalMessage(address(0xA11CE), sat, 1 ether, wdId, chain);
        // Replay should revert
        vm.prank(address(messenger));
        vm.expectRevert(bytes("replayed"));
        receiver.onWithdrawalMessage(address(0xA11CE), sat, 1 ether, wdId, chain);
    }

    function testOnlyAdminCannotSetters() public {
        address stranger = address(0xBAD);
        vm.prank(stranger); vm.expectRevert(); receiver.setEscrowGateway(address(escrow));
        vm.prank(stranger); vm.expectRevert(); receiver.setMessenger(address(messenger));
        vm.prank(stranger); vm.expectRevert(); receiver.setRemoteSender(sender);
        vm.prank(stranger); vm.expectRevert(); receiver.setMessengerToDefault();
    }

    function testOnlyMessengerGuardOnDeposit() public {
        // call from non-messenger must revert
        vm.expectRevert(bytes("not messenger"));
        receiver.onDepositMessage(address(0xA11CE), address(0xCA7), 1, keccak256("depX"), keccak256("dst"));
    }

    function testOnlyMessengerGuardOnWithdrawal() public {
        // call from non-messenger must revert
        vm.expectRevert(bytes("not messenger"));
        receiver.onWithdrawalMessage(address(0xA11CE), address(0xCA7), 1, keccak256("wdX"), keccak256("dst"));
    }
}