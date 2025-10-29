// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OpL2L2Receiver} from "../src/bridge/op/OpL2L2Receiver.sol";
import {IL2ToL2CrossDomainMessenger} from "../src/bridge/op/IL2ToL2CrossDomainMessenger.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockL2ToL2MessengerUUPS is IL2ToL2CrossDomainMessenger {
    function sendMessage(address, bytes calldata, uint32) external {}

    function xDomainMessageSender() external view returns (address) {
        return address(0);
    }
}

contract OpL2L2ReceiverUUPSTest is Test {
    OpL2L2Receiver recv;
    OpL2L2Receiver impl;
    MockL2ToL2MessengerUUPS messenger;

    function setUp() public {
        messenger = new MockL2ToL2MessengerUUPS();
        impl = new OpL2L2Receiver();
        bytes memory init =
            abi.encodeWithSelector(OpL2L2Receiver.initialize.selector, address(this), address(messenger), address(0x1));
        recv = OpL2L2Receiver(address(new ERC1967Proxy(address(impl), init)));
    }

    function testUpgradeByAdminSucceeds() public {
        OpL2L2Receiver newImpl = new OpL2L2Receiver();
        recv.upgradeTo(address(newImpl));
        // initializing implementation directly should revert
        vm.expectRevert();
        newImpl.initialize(address(this), address(messenger), address(0x1));
        // also exercise setMessengerToDefault for coverage
        recv.setMessengerToDefault();
    }
}
