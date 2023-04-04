//SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "../storage/Account.sol";
import "../storage/ProtocolRiskConfiguration.sol";
import "../storage/CollateralConfiguration.sol";
import "@voltz-protocol/util-contracts/src/errors/ParameterError.sol";
import "../interfaces/ILiquidationModule.sol";
import "@voltz-protocol/util-contracts/src/helpers/SafeCast.sol";
import "../storage/Collateral.sol";

import { mulUDxUint } from "@voltz-protocol/util-contracts/src/helpers/PrbMathHelper.sol";

/**
 * @title Module for liquidated accounts
 * @dev See ILiquidationModule
 */

contract LiquidationModule is ILiquidationModule {
    using ProtocolRiskConfiguration for ProtocolRiskConfiguration.Data;
    using CollateralConfiguration for CollateralConfiguration.Data;
    using Account for Account.Data;
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;
    using Collateral for Collateral.Data;

    function extractLiquidatorReward(uint128 liquidatedAccountId, address collateralType, uint256 imPreClose, uint256 imPostClose) 
        private returns (uint256 liquidatorRewardAmount) 
    {
        Account.Data storage account = Account.load(liquidatedAccountId);

        UD60x18 liquidatorRewardParameter = ProtocolRiskConfiguration.load().liquidatorRewardParameter;
        uint256 liquidationBooster = CollateralConfiguration.load(collateralType).liquidationBooster;

        if (mulUDxUint(liquidatorRewardParameter, imPreClose) >= liquidationBooster) {
            liquidatorRewardAmount = mulUDxUint(liquidatorRewardParameter, imPreClose - imPostClose);
            account.collaterals[collateralType].decreaseCollateralBalance(liquidatorRewardAmount);
        } else {
            if (imPostClose != 0) {
                revert PartialLiquidationNotIncentivized(liquidatedAccountId, imPreClose, imPostClose);
            }

            liquidatorRewardAmount = liquidationBooster;
            account.collaterals[collateralType].decreaseLiquidationBoosterBalance(liquidatorRewardAmount);
        }
    }

    /**
     * @inheritdoc ILiquidationModule
     */
    function liquidate(
        uint128 liquidatedAccountId,
        uint128 liquidatorAccountId,
        address collateralType
    )
        external
        returns (uint256 liquidatorRewardAmount)
    {
        Account.Data storage account = Account.exists(liquidatedAccountId);
        (bool liquidatable, uint256 imPreClose,) = account.isLiquidatable(collateralType);

        if (!liquidatable) {
            revert AccountNotLiquidatable(liquidatedAccountId);
        }

        account.closeAccount(collateralType);
        (uint256 imPostClose,) = account.getMarginRequirements(collateralType);

        if (imPreClose <= imPostClose) {
            revert AccountExposureNotReduced(liquidatedAccountId, imPreClose, imPostClose);
        }

        liquidatorRewardAmount = extractLiquidatorReward(liquidatedAccountId, collateralType, imPreClose, imPostClose);

        Account.Data storage liquidatorAccount = Account.exists(liquidatorAccountId);
        liquidatorAccount.collaterals[collateralType].increaseCollateralBalance(liquidatorRewardAmount);
    }
}
