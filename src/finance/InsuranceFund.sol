// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title InsuranceFund
/// @notice ERC4626 vault for segregated reserves/fees; configure FeeSplitter to route a share here.
contract InsuranceFund is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable,
    ERC4626Upgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address asset_, string memory name_, string memory symbol_)
        external
        initializer
    {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ERC20_init(name_, symbol_);
        __ERC4626_init(IERC20Upgradeable(asset_));
        _grantRole(Constants.DEFAULT_ADMIN, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function pause() external onlyRole(Constants.DEFAULT_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(Constants.DEFAULT_ADMIN) {
        _unpause();
    }

    // Resolve multiple inheritance of decimals
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return super.decimals();
    }
}
