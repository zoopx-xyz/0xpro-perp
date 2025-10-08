// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFundingModule {
    function updateFundingIndex(bytes32 marketId, int128 indexDelta) external;
    function getFundingIndex(bytes32 marketId) external view returns (int128);
}
