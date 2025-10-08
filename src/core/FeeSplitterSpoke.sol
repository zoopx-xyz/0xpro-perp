// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Constants} from "../../lib/Constants.sol";

contract FeeSplitterSpoke is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    event FeeSplit(uint256 feeZ, uint256 toTreasury, uint256 toInsurance, uint256 toReferral);
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function splitFees(uint256 feeZ) external returns (uint256 toTreasury, uint256 toInsurance, uint256 toReferral) {
        // MVP split: 80% treasury, 20% insurance, 0% referral
        toTreasury = (feeZ * 80) / 100;
        toInsurance = feeZ - toTreasury;
        toReferral = 0;
        emit FeeSplit(feeZ, toTreasury, toInsurance, toReferral);
    }

    uint256[50] private __gap;
}
