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
    }

    function recordFill(Fill calldata f) external;
}
