//SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "../../src/storage/MarketFeeConfiguration.sol";

import { UD60x18, unwrap } from "@prb/math/UD60x18.sol";

contract ExposedMarketFeeConfiguration {
    // Mock support
    function getMarketFeeConfiguration(
        uint128 productId,
        uint128 marketId
    )
        external
        pure
        returns (MarketFeeConfiguration.Data memory)
    {
        return MarketFeeConfiguration.load(productId, marketId);
    }

    // Exposed functions
    function load(uint128 productId, uint128 marketId) external pure returns (bytes32 s) {
        MarketFeeConfiguration.Data storage data = MarketFeeConfiguration.load(productId, marketId);
        assembly {
            s := data.slot
        }
    }

    function set(MarketFeeConfiguration.Data memory config) external {
        MarketFeeConfiguration.set(config);
    }
}

contract MarketFeeConfigurationTest is Test {
    using { unwrap } for UD60x18;

    ExposedMarketFeeConfiguration internal marketFeeConfiguration;

    function setUp() public {
        marketFeeConfiguration = new ExposedMarketFeeConfiguration();
    }

    function test_Load() public {
        bytes32 s = keccak256(abi.encode("xyz.voltz.MarketFeeConfiguration", 1, 10));
        assertEq(marketFeeConfiguration.load(1, 10), s);
    }

    function test_Set() public {
        marketFeeConfiguration.set(
            MarketFeeConfiguration.Data({
                productId: 1, marketId: 10, feeCollectorAccountId: 13, 
                atomicMakerFee: UD60x18.wrap(1e15), atomicTakerFee: UD60x18.wrap(2e15)
            })
        );

        MarketFeeConfiguration.Data memory data = marketFeeConfiguration.getMarketFeeConfiguration(1, 10);

        assertEq(data.productId, 1);
        assertEq(data.marketId, 10);
        assertEq(data.feeCollectorAccountId, 13);
        assertEq(data.atomicMakerFee.unwrap(), 1e15);
        assertEq(data.atomicTakerFee.unwrap(), 2e15);
    }

    function test_Set_Twice() public {
        marketFeeConfiguration.set(
            MarketFeeConfiguration.Data({
                productId: 1, marketId: 10, feeCollectorAccountId: 13, 
                atomicMakerFee: UD60x18.wrap(1e15), atomicTakerFee: UD60x18.wrap(2e15)
            })
        );

        marketFeeConfiguration.set(
            MarketFeeConfiguration.Data({
                productId: 1, marketId: 10, feeCollectorAccountId: 15, 
                atomicMakerFee: UD60x18.wrap(3e15), atomicTakerFee: UD60x18.wrap(4e15)
            })
        );

        MarketFeeConfiguration.Data memory data = marketFeeConfiguration.getMarketFeeConfiguration(1, 10);

        assertEq(data.productId, 1);
        assertEq(data.marketId, 10);
        assertEq(data.feeCollectorAccountId, 15);
        assertEq(data.atomicMakerFee.unwrap(), 3e15);
        assertEq(data.atomicTakerFee.unwrap(), 4e15);
    }

    function test_Set_MoreConfigurations() public {
        marketFeeConfiguration.set(
            MarketFeeConfiguration.Data({
                productId: 1, marketId: 10, feeCollectorAccountId: 13, 
                atomicMakerFee: UD60x18.wrap(1e15), atomicTakerFee: UD60x18.wrap(2e15)
            })
        );

        marketFeeConfiguration.set(
            MarketFeeConfiguration.Data({
                productId: 2, marketId: 20, feeCollectorAccountId: 14, 
                atomicMakerFee: UD60x18.wrap(2e15), atomicTakerFee: UD60x18.wrap(1e15)
            })
        );

        {
            MarketFeeConfiguration.Data memory data = marketFeeConfiguration.getMarketFeeConfiguration(1, 10);

            assertEq(data.productId, 1);
            assertEq(data.marketId, 10);
            assertEq(data.feeCollectorAccountId, 13);
            assertEq(data.atomicMakerFee.unwrap(), 1e15);
            assertEq(data.atomicTakerFee.unwrap(), 2e15);
        }

        {
            MarketFeeConfiguration.Data memory data = marketFeeConfiguration.getMarketFeeConfiguration(2, 20);

            assertEq(data.productId, 2);
            assertEq(data.marketId, 20);
            assertEq(data.feeCollectorAccountId, 14);
            assertEq(data.atomicMakerFee.unwrap(), 2e15);
            assertEq(data.atomicTakerFee.unwrap(), 1e15);
        }
    }
}