// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {HealthFactor} from "src/libraries/HealthFactor.sol";

contract LendingPoolTest is Test {
    address user;

    function setUp() public {
        user = makeAddr("user");
        vm.deal(user, 1_000_000 ether);
    }

    function test_collateralValueInUsd() public {
        uint256 collateral = 0.5 ether;
        uint256 price = 3000e18;
        assertEq(HealthFactor.collateralValueInUsd(collateral, price), 1500e18);
    }

    function test_maxToBorrowInUsd() public {
        uint256 collateralValue = 5000e18;
        uint256 ltv = 7500; //75%

        uint256 expected = 3750e18;

        assertEq(HealthFactor.maxToBorrowInUsd(collateralValue, ltv), expected);
    }

    function test_calculateHealthFactor() public {
        uint256 collateralValue = 7000e18;
        uint256 debtValue = 2500e18;
        uint256 liquidationThreshold = 8000; //80%

        /**
         * 7500 * 0.8 = 5600
         * HF = 5600 / 2500 = 2.24
         */
        uint256 expectedValue = 2.24e18;
        assertEq(HealthFactor.calculateHealthFactor(debtValue, collateralValue, liquidationThreshold), expectedValue);
    }

    function test_healthFactorPeriodicDecimals() public {
        /**
         * Deposit 10 ether a 2000USD/ETH -> 20_000 USDC en ETH
         * Borrow  12_000 USDC -> 12_000 USD en USDC
         * HF = 0.8 * 20_000 / 12_000 = 16_000 / 12_000 = 1.3333333.... OK!
         */

        uint256 collateralValue = 20_000e18;
        uint256 debtValue = 12_000e18;
        uint256 liquidationThreshold = 8000; //80%

        uint256 expectedValue = 1333333333333333333;
        assertEq(HealthFactor.calculateHealthFactor(debtValue, collateralValue, liquidationThreshold), expectedValue);
    }
}
