// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IL2ToL2CrossDomainMessenger} from "../../bridge/op/IL2ToL2CrossDomainMessenger.sol";

/// @title ExampleL2ToL2Receiver
/// @notice Minimal receiver per Optimism interop tutorial; only messenger can call, and it must originate from the configured remote sender
contract ExampleL2ToL2Receiver {
    IL2ToL2CrossDomainMessenger public immutable messenger;
    address public immutable remoteSender;

    uint256 public pingCount;
    string public lastMessage;

    event PingReceived(address indexed remoteSender, string message, uint256 count);

    constructor(address messenger_, address remoteSender_) {
        messenger = IL2ToL2CrossDomainMessenger(messenger_);
        remoteSender = remoteSender_;
    }

    function ping(string calldata message) external {
        require(msg.sender == address(messenger), "not messenger");
        require(messenger.xDomainMessageSender() == remoteSender, "bad xSender");
        pingCount += 1;
        lastMessage = message;
        emit PingReceived(remoteSender, message, pingCount);
    }
}
