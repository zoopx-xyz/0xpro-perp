// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IL2ToL2CrossDomainMessenger} from "../../bridge/op/IL2ToL2CrossDomainMessenger.sol";

/// @title ExampleL2ToL2Sender
/// @notice Minimal sender per Optimism interop tutorial; sends a ping to a remote receiver on another L2
contract ExampleL2ToL2Sender {
    IL2ToL2CrossDomainMessenger public immutable messenger;
    address public remoteReceiver;
    uint32 public immutable minGasLimit;

    constructor(address messenger_, address remoteReceiver_, uint32 minGasLimit_) {
        messenger = IL2ToL2CrossDomainMessenger(messenger_);
        remoteReceiver = remoteReceiver_;
        minGasLimit = minGasLimit_ == 0 ? 1_000_000 : minGasLimit_;
    }

    function setRemoteReceiver(address remote) external {
        remoteReceiver = remote;
    }

    function sendPing(string calldata message) external {
        bytes memory payload = abi.encodeWithSignature("ping(string)", message);
        messenger.sendMessage(remoteReceiver, payload, minGasLimit);
    }
}
