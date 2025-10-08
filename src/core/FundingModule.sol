// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IFundingModule} from "./interfaces/IFundingModule.sol";
import {Constants} from "../../lib/Constants.sol";

contract FundingModule is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IFundingModule {
    mapping(bytes32 => int128) public fundingIndex; // marketId => index

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.KEEPER, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function updateFundingIndex(bytes32 marketId, int128 indexDelta) external override onlyRole(Constants.KEEPER) {
        fundingIndex[marketId] += indexDelta;
    }

    function getFundingIndex(bytes32 marketId) external view override returns (int128) {
        return fundingIndex[marketId];
    }

    uint256[50] private __gap;
}
