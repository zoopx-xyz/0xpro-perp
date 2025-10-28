// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IL2ToL2CrossDomainMessenger} from "../src/bridge/op/IL2ToL2CrossDomainMessenger.sol";
import {OpL2L2Sender} from "../src/bridge/op/OpL2L2Sender.sol";
import {AssetMapper} from "../src/bridge/AssetMapper.sol";
import {Constants} from "../lib/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockL2ToL2Messenger2 is IL2ToL2CrossDomainMessenger {
    address public lastTarget;
    bytes public lastMessage;
    uint32 public lastMinGas;
    function sendMessage(address target, bytes calldata message, uint32 minGasLimit ) external {
        lastTarget = target; lastMessage = message; lastMinGas = minGasLimit;
    }
    function xDomainMessageSender() external view returns (address) { return address(0); }
}

contract OpL2L2SenderMoreTest is Test {
    MockL2ToL2Messenger2 messenger;
    OpL2L2Sender sender;
    AssetMapper mapper;
    address admin = address(this);
    address user = address(0xA11CE);
    address base = address(0xBEEF);
    bytes32 chain = keccak256("dst");

    function setUp() public {
        messenger = new MockL2ToL2Messenger2();
        OpL2L2Sender impl = new OpL2L2Sender();
        bytes memory init = abi.encodeWithSelector(OpL2L2Sender.initialize.selector, admin, address(messenger), address(0x1), 123_456);
        sender = OpL2L2Sender(address(new ERC1967Proxy(address(impl), init)));
        AssetMapper mImpl = new AssetMapper();
        mapper = AssetMapper(address(new ERC1967Proxy(address(mImpl), abi.encodeWithSelector(AssetMapper.initialize.selector, admin))));
    }

    function testSetters() public {
        // set messenger direct and to default
        sender.setMessenger(address(messenger));
        sender.setMessengerToDefault(); // just ensure it doesn't revert
        // set remote, mapper and gas
        sender.setRemoteReceiver(address(0x2));
        sender.setAssetMapper(address(mapper));
        sender.setMinGasLimit(777_777);
    }

    function testSendDepositEmitsMessage() public {
        sender.setRemoteReceiver(address(0xF00D));
        sender.sendDeposit(user, base, 42, keccak256("dep"), chain);
        assertEq(messenger.lastTarget(), address(0xF00D));
        // basic payload sanity
        assertGt(messenger.lastMessage().length, 0);
    }

    function testSendWithdrawalRevertsWhenMappingMissing() public {
        // mapper not set -> asset mapping missing
        // To trigger revert, set mapper but don't configure mapping so lookup returns zero
        sender.setAssetMapper(address(mapper));
        vm.expectRevert(bytes("asset mapping missing"));
        sender.sendWithdrawal(user, base, 1, keccak256("wd"), chain);
    }

    function testSendWithdrawalSuccessWithMapping() public {
        sender.setAssetMapper(address(mapper));
        sender.setRemoteReceiver(address(0xF00D));
        address sat = address(0xCA7);
        mapper.setMapping(chain, sat, base);
        sender.sendWithdrawal(user, base, 100, keccak256("wd2"), chain);
        assertEq(messenger.lastTarget(), address(0xF00D));
        assertGt(messenger.lastMessage().length, 0);
    }

    function testSendWithdrawalWithoutMapperSucceeds() public {
        // No mapper set: satAsset should default to base asset
        sender.setRemoteReceiver(address(0xF00D));
        sender.sendWithdrawal(user, base, 5, keccak256("wdNoMap"), chain);
        assertEq(messenger.lastTarget(), address(0xF00D));
        assertGt(messenger.lastMessage().length, 0);
    }

    function testMinGasApplied() public {
        // set a distinctive min gas and ensure messenger sees it
        sender.setMinGasLimit(777_777);
        sender.setRemoteReceiver(address(0xF00D));
        sender.sendDeposit(user, base, 1, keccak256("depMinGas"), chain);
        assertEq(messenger.lastMinGas(), 777_777);
    }

    function testSetMessengerToDefaultSetsPredeploy() public {
        // switch messenger to the OP predeploy constant address
        sender.setMessengerToDefault();
        // verify the stored messenger address matches the constant
        assertEq(address(sender.messenger()), Constants.OP_L2L2_MESSENGER_PREDEPLOY);
    }

    function testOnlyAdminCannotSetters() public {
        address stranger = address(0xBAD);
        vm.prank(stranger); vm.expectRevert(); sender.setMessenger(address(messenger));
        vm.prank(stranger); vm.expectRevert(); sender.setMessengerToDefault();
        vm.prank(stranger); vm.expectRevert(); sender.setRemoteReceiver(address(0x3));
        vm.prank(stranger); vm.expectRevert(); sender.setAssetMapper(address(mapper));
        vm.prank(stranger); vm.expectRevert(); sender.setMinGasLimit(1);
    }
}
