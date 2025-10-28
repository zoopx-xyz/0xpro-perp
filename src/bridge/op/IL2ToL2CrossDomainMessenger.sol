// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IL2ToL2CrossDomainMessenger {
    function sendMessage(address target, bytes calldata message, uint32 minGasLimit) external;
    function xDomainMessageSender() external view returns (address);
}
