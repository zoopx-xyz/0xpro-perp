// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeeSplitterSpoke {
    function splitFees(uint256 feeZ)
        external
        returns (uint256 toTreasury, uint256 toInsurance, uint256 toUI, uint256 toReferral);
    function setSplit(uint16 treasuryBps, uint16 insuranceBps, uint16 uiBps, uint16 referralBps) external;
}
