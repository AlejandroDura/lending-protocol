// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library HealthFactor {
    function collateralValueInUsd(uint256 _collateralETH, uint256 _ethPrice) internal pure returns (uint256) {
        return _collateralETH * _ethPrice / 1e18;
    }

    function maxToBorrowInUsd(uint256 _collateraValueInUsd, uint256 _ltv) internal pure returns (uint256) {
        return (_collateraValueInUsd * _ltv) / 10_000;
    }

    function calculateHealthFactor(
        uint256 _debtValueInUsd,
        uint256 _collateralValueInUsd,
        uint256 _liquidationThreshold
    ) internal pure returns (uint256) {
        return ((_collateralValueInUsd * _liquidationThreshold) / 10_000) * 1e18 / _debtValueInUsd;

        //o tambien: return (_collateralValueInUsd * _liquidationThreshold * 1e18) / (_debtValueInUsd * 10_000);

        //otra forma LTV_current = debt / collateral
        // HF = liquidationThreshold / LTV_current

        //LTV_current = debtValue * 10_000/ collateralValue;
        // HF = liquidationThreshold * 1e18 / LTV_current;
    }
}
