// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Constants {
    // Roles
    bytes32 public constant DEFAULT_ADMIN = 0x00;
    bytes32 public constant ENGINE = keccak256("ENGINE");
    bytes32 public constant KEEPER = keccak256("KEEPER");
    bytes32 public constant RISK_ADMIN = keccak256("RISK_ADMIN");
    bytes32 public constant TREASURER = keccak256("TREASURER");
    bytes32 public constant PRICE_KEEPER = keccak256("PRICE_KEEPER");
    bytes32 public constant ENGINE_ADMIN = keccak256("ENGINE_ADMIN");

    // Fees (in bps)
    uint16 public constant MAKER_FEE_BPS_DEFAULT = 5;   // 0.05%
    uint16 public constant TAKER_FEE_BPS_DEFAULT = 7;   // 0.07%

    // Collateral/LTV defaults
    uint16 public constant LTV_NON_STABLE_BPS = 5000; // 50%
    uint16 public constant LTV_STABLE_BPS = 10000;    // 100%

    // Oracle defaults
    uint256 public constant PRICE_DECIMALS = 1e18; // prices normalized to 1e18 zUSD
    uint256 public constant INTERNAL_DECIMALS = 1e18; // internal zUSD units
    uint64 public constant DEFAULT_MAX_STALE = 300; // 300 seconds
}
