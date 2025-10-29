// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library StorkStructs {
    // Minimal struct shape based on Stork docs
    struct TemporalNumericValue {
        int256 value; // raw value from Stork
        uint64 timestamp; // unix seconds
    }

    struct TemporalNumericValueInput {
        bytes32 id;
        int256 value;
        uint64 timestamp;
        bytes signature; // not used by our adapter (read-only)
    }
}
