// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeeSplitterSpoke {
    function splitFees(uint256 feeZ) external returns (uint256 toTreasury, uint256 toInsurance, uint256 toReferral);
}
