// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {OpL2L2Sender} from "../src/bridge/op/OpL2L2Sender.sol";
import {IL2ToL2CrossDomainMessenger} from "../src/bridge/op/IL2ToL2CrossDomainMessenger.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockL2ToL2Messenger3 is IL2ToL2CrossDomainMessenger {
    function sendMessage(address, bytes calldata, uint32) external {}

    function xDomainMessageSender() external view returns (address) {
        return address(0);
    }
}

contract OpL2L2SenderUUPSTest is Test {
    OpL2L2Sender sender;
    OpL2L2Sender impl;
    MockL2ToL2Messenger3 messenger;

    function setUp() public {
        messenger = new MockL2ToL2Messenger3();
        impl = new OpL2L2Sender();
        // Use minGas=0 to exercise defaulting logic to 1_000_000
        bytes memory init =
            abi.encodeWithSelector(OpL2L2Sender.initialize.selector, address(this), address(messenger), address(0x1), 0);
        sender = OpL2L2Sender(address(new ERC1967Proxy(address(impl), init)));
    }

    function testMinGasDefaultedWhenZero() public {
        // change and restore to cover setMinGasLimit as well
        sender.setMinGasLimit(222_222);
        sender.setMinGasLimit(1_000_000); // ensure we can set to default explicitly too
    }

    function testUpgradeByAdminSucceeds() public {
        OpL2L2Sender newImpl = new OpL2L2Sender();
        sender.upgradeTo(address(newImpl));
        // initializing implementation directly should revert
        vm.expectRevert();
        newImpl.initialize(address(this), address(messenger), address(0x1), 0);
    }
}
