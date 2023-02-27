// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @title Oracle Manager Interface
interface IOracleManager {
    // todo: should have two versions of this function, one view and one state-chaining
    function snapshotRateIndex(uint128 marketId, uint256 maturityTimestamp) external view returns (int256 rateIndex);
}