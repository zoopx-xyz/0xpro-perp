// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library MathUtils {
    // returns notional in 1e18 zUSD given size in raw token units and price in 1e18
    function notionalZFromSize(uint256 sizeRaw, uint8 assetDecimals, uint256 priceX1e18) internal pure returns (uint256) {
        return (sizeRaw * priceX1e18) / (10 ** assetDecimals);
    }

    // convert internal 1e18 zUSD amount to token units (decimals)
    function z18ToToken(uint256 amountZ18, uint8 tokenDecimals) internal pure returns (uint256) {
        if (tokenDecimals == 18) return amountZ18;
        if (tokenDecimals < 18) return amountZ18 / (10 ** (18 - tokenDecimals));
        return amountZ18 * (10 ** (tokenDecimals - 18));
    }

    // convert token units to internal 1e18 zUSD amount when token is priced 1e18 (like zUSD)
    function tokenToZ18(uint256 amountToken, uint8 tokenDecimals) internal pure returns (uint256) {
        if (tokenDecimals == 18) return amountToken;
        if (tokenDecimals < 18) return amountToken * (10 ** (18 - tokenDecimals));
        return amountToken / (10 ** (tokenDecimals - 18));
    }
}
