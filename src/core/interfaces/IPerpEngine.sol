// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPerpEngine {
    struct Fill {
        bytes32 fillId;
        address account;
        bytes32 marketId;
        bool isBuy;
        uint128 size;
        uint128 priceZ;
        uint128 feeZ;
        int128 fundingZ;
        uint64 ts;
        bytes32 orderDigest;
    }

    function recordFill(Fill calldata f) external;

    function getUnrealizedPnlZ(address account) external view returns (int256);

    function getPosition(address account, bytes32 marketId) external view returns (int256);

    function computeAccountMMRZ(address account) external view returns (uint256);
}
