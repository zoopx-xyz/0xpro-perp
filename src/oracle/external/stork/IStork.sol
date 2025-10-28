// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StorkStructs} from "./StorkStructs.sol";

interface IStork {
    function getTemporalNumericValueV1(bytes32 id)
        external
        view
        returns (StorkStructs.TemporalNumericValue memory value);

    function getTemporalNumericValueUnsafeV1(bytes32 id)
        external
        view
        returns (StorkStructs.TemporalNumericValue memory value);
}
