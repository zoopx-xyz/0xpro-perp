// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Via Labs router interface (locked for audit readiness)
/// Expected semantics: forwards `message` to `target` on `dstChainId` and authenticates the source app.
interface IViaRouter {
    function xcall(uint64 dstChainId, address target, bytes calldata message) external payable;
}
