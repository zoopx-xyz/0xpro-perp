// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ExampleL2ToL2Sender} from "../src/examples/op/ExampleL2ToL2Sender.sol";
import {ExampleL2ToL2Receiver} from "../src/examples/op/ExampleL2ToL2Receiver.sol";
import {IL2ToL2CrossDomainMessenger} from "../src/bridge/op/IL2ToL2CrossDomainMessenger.sol";

contract MockL2ToL2Messenger is IL2ToL2CrossDomainMessenger {
    address private _xSender;

    function setXSender(address s) external { _xSender = s; }

    function sendMessage(address target, bytes calldata message, uint32 /*minGasLimit*/ ) external {
        (bool ok, bytes memory ret) = target.call(message);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    function xDomainMessageSender() external view returns (address) {
        return _xSender;
    }
}

contract OpL2L2MessengerExampleTest is Test {
    MockL2ToL2Messenger messenger;
    ExampleL2ToL2Sender sender;
    ExampleL2ToL2Receiver receiver;

    address user = address(0xBEEF);

    function setUp() public {
    messenger = new MockL2ToL2Messenger();
    // Deploy sender first (remote receiver will be set after receiver is deployed)
    sender = new ExampleL2ToL2Sender(address(messenger), address(0), 1_000_000);
    receiver = new ExampleL2ToL2Receiver(address(messenger), address(sender));
    sender.setRemoteReceiver(address(receiver));
    }

    function testPingSuccess() public {
        // Simulate cross-domain: set xDomainMessageSender to the sender contract address
        messenger.setXSender(address(sender));
        assertEq(receiver.pingCount(), 0);

        // user triggers sending a ping
        vm.prank(user);
        sender.sendPing("hello");

        assertEq(receiver.pingCount(), 1);
        assertEq(receiver.lastMessage(), "hello");
    }

    function testPingRevertsOnSpoofedSender() public {
        // Spoof: set xDomainMessageSender to an address that is not 'sender'
        messenger.setXSender(address(0xBAD));

        vm.expectRevert(bytes("bad xSender"));
        sender.sendPing("spoof");
    }
}
