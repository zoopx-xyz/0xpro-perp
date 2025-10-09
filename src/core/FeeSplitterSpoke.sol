// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../../lib/Constants.sol";

contract FeeSplitterSpoke is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    struct FeesSplit {
        uint16 treasuryBps;
        uint16 insuranceBps;
        uint16 uiBps;
        uint16 referralBps;
    }

    FeesSplit public feeSplit;
    address public zUsdToken;
    address public treasuryRecipient;
    address public insuranceRecipient;
    address public uiRecipient;
    address public referralRecipient;

    event FeeSplitExecuted(uint256 feeZ, uint256 toTreasury, uint256 toInsurance, uint256 toUI, uint256 toReferral);
    /// @custom:oz-upgrades-unsafe-allow constructor

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);

        // Set default MVP split: 80% treasury, 20% insurance, 0% UI, 0% referral
        feeSplit = FeesSplit({treasuryBps: 8000, insuranceBps: 2000, uiBps: 0, referralBps: 0});
    }

    function setZUsdToken(address _zUsdToken) external onlyRole(Constants.DEFAULT_ADMIN) {
        zUsdToken = _zUsdToken;
    }

    function setRecipients(
        address _treasuryRecipient,
        address _insuranceRecipient,
        address _uiRecipient,
        address _referralRecipient
    ) external onlyRole(Constants.DEFAULT_ADMIN) {
        treasuryRecipient = _treasuryRecipient;
        insuranceRecipient = _insuranceRecipient;
        uiRecipient = _uiRecipient;
        referralRecipient = _referralRecipient;
    }

    function setSplit(uint16 treasuryBps, uint16 insuranceBps, uint16 uiBps, uint16 referralBps)
        external
        onlyRole(Constants.DEFAULT_ADMIN)
    {
        require(treasuryBps + insuranceBps + uiBps + referralBps <= 10000, "split exceeds 100%");

        feeSplit =
            FeesSplit({treasuryBps: treasuryBps, insuranceBps: insuranceBps, uiBps: uiBps, referralBps: referralBps});
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function splitFees(uint256 feeZ)
        external
        returns (uint256 toTreasury, uint256 toInsurance, uint256 toUI, uint256 toReferral)
    {
        require(feeZ > 0, "invalid fee amount");
        require(zUsdToken != address(0), "zUSD not set");

        // Calculate splits
        toTreasury = (feeZ * feeSplit.treasuryBps) / 10000;
        toInsurance = (feeZ * feeSplit.insuranceBps) / 10000;
        toUI = (feeZ * feeSplit.uiBps) / 10000;
        toReferral = (feeZ * feeSplit.referralBps) / 10000;

        // Transfer to recipients
        IERC20 token = IERC20(zUsdToken);

        if (toTreasury > 0 && treasuryRecipient != address(0)) {
            token.safeTransfer(treasuryRecipient, toTreasury);
        }
        if (toInsurance > 0 && insuranceRecipient != address(0)) {
            token.safeTransfer(insuranceRecipient, toInsurance);
        }
        if (toUI > 0 && uiRecipient != address(0)) {
            token.safeTransfer(uiRecipient, toUI);
        }
        if (toReferral > 0 && referralRecipient != address(0)) {
            token.safeTransfer(referralRecipient, toReferral);
        }

        emit FeeSplitExecuted(feeZ, toTreasury, toInsurance, toUI, toReferral);
    }

    uint256[50] private __gap;
}
