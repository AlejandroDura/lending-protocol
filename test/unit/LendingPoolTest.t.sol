// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "src/LendingPool.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DeployLendingPool} from "script/DeployLendingPool.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract LendingPoolTest is Test {
    address user;
    address liquidator;

    DeployLendingPool public deployer;

    HelperConfig config;
    LendingPool public lendingPool;
    DepositToken public depositToken;
    PriceOracle public priceOracle;
    ERC20Mock public usdcToken;

    function setUp() public {
        user = makeAddr("user");
        vm.deal(user, 1_000_000 ether);
        liquidator = makeAddr("liquidator");
        vm.deal(liquidator, 1_000_000 ether);

        deployer = new DeployLendingPool();
        (lendingPool, priceOracle, config) = deployer.run();

        usdcToken = ERC20Mock(config.getNetworkConfig().usdc);
        usdcToken.mint(address(lendingPool), 1_000_000e6);
    }

    modifier depositCollateral(address _user, uint256 _amount) {
        vm.prank(_user);
        lendingPool.depositCollateral{value: _amount}();
        _;
    }

    modifier borrow(address _user, uint256 _amount) {
        vm.prank(_user);
        lendingPool.borrow(_amount);
        _;
    }

    ////////////
    //Deposit//
    //////////

    function test_depositCollateral() public {
        vm.prank(user);
        lendingPool.depositCollateral{value: 10 ether}();

        assertEq(lendingPool.getCollateral(user), 10 ether);
    }

    ///////////
    //Borrow//
    /////////

    function test_borrowExceedsMaxToBorrow() public depositCollateral(user, 10 ether) {
        /**
         * Collateral 10 ETH
         * ETH price: 2000USD/ETH
         * Collateral value = 2000USD/ETH * 10 ETH = 20,000USD
         * Max to lend = 75% of 20,000USD -> 0.75 * 20,000USD = 15,000USD
         */

        uint256 amountToBorrow = 15_001e6;
        vm.expectRevert(LendingPool.LendingPool__LendingExceedTheMaximum.selector);
        vm.prank(user);
        lendingPool.borrow(amountToBorrow);
    }

    function test_borrow() public depositCollateral(user, 10 ether) {
        uint256 amountToBorrow = 200e6;
        vm.prank(user);
        lendingPool.borrow(amountToBorrow);

        assertEq(lendingPool.getDebt(user), amountToBorrow);
    }

    //////////
    //Repay//
    ////////
    function test_repay() public depositCollateral(user, 10 ether) borrow(user, 1000e6) {
        vm.startPrank(user);
        IERC20(usdcToken).approve(address(lendingPool), 600e6);
        lendingPool.repay(600e6);
        vm.stopPrank();

        uint256 expectedValue = 400e6;
        assertEq(lendingPool.getDebt(user), expectedValue);
    }

    //////////////
    //Liquidate//
    ////////////
    function test_liquidate() public depositCollateral(user, 10 ether) borrow(user, 15_000e6) {
        /**
         * Colateral 10 ETH
         * Debt 15,000USDC
         * ETH Price 2000USD/ETH
         * Collateral price = 10 ETH * 2000USD/ETH = 20,000USD
         * ETH price drops to 1800USD/ETH, collateral value now: 10 ETH * 1800USD/ETH = 18,000USD
         * HF = 0.8 * 18,000USD / 15,000 USD = 0.96
         *
         * Collateral to redeem = 7_500 USD in ETH which is: 7,500USD / 1800USD/ETH = 4.1666... ETH -> 4166666666666666666 WEI
         * Bonus = 4166666666666666666 * 0.3 = 124,999,999,999,999,999 (0.1249 ETH)
         * Total to redeem = 4166666666666666666 WEI + 124,999,999,999,999,999 WEI = 4291666666666666665 WEI = 4.29166... ETH
         *
         * After liquidate
         * ETH price = 1800USD/ETH
         * Collateral = 10 ETH - 4.291666 ETH = 5.708334 ETH
         * Collateral value = 5.708334 ETH * 1800USD/ETH = 10,275.0012 USD
         * Debt = 7,500USDC
         * HF = 0.8 * 10,275.0012 USD / 7,500USDC = 1.096... this HF is better than before OK!
         */
        uint256 expectedToRedeem = 4291666666666666665;
        uint256 expectedUserDebt = 7_500e6; //15_000e6 - 7_500e6 = 7_500e6
        uint256 expectedUserCollateral = 10 ether - expectedToRedeem;

        address ethPriceOracle = priceOracle.getPriceOracle(address(0));
        MockAggregatorV3(ethPriceOracle).updateAnswer(1800e8);

        _mintAndApprove(liquidator, address(lendingPool), 7_500e6, address(usdcToken));

        vm.prank(liquidator);
        lendingPool.liquidate(user, 7_500e6);

        assertEq(lendingPool.getDebt(user), expectedUserDebt, "DEBT ASSERT FAILED!");
        assertEq(lendingPool.getCollateral(user), expectedUserCollateral, "COLLATERAL ASSERT FAILED!");
    }

    /////////////
    //Withdraw//
    ///////////

    function test_withdrawCollateral() public depositCollateral(user, 10 ether) {
        vm.prank(user);
        lendingPool.withdrawCollateral(10 ether);

        assertEq(lendingPool.getCollateral(user), 0);
    }

    ///////////
    //Others//
    /////////

    function test_getUSDValue() public {
        /**
         * ETH price: 2000USD
         * ETH amount: 10ETH
         * USD value = 2000USD/ETH * 10 ETH = 20,000USD -> 20_000_0000000000_00000000 (amount * price / 1e18;)
         */
        uint256 amount = 10 ether;
        uint256 expectedValue = 20_000_0000000000_00000000;

        assertEq(lendingPool.getUsdValue(address(0), amount), expectedValue);
    }

    function test_getETHAmountFromUsd() public {
        /**
         * ETH Price: 2000USD/ETH
         * Total usd amount: 50,000USD
         * ETH amount = 50,000USD / 2,000USD/ETH = 25 ETH = 25000000000000000000
         */

        uint256 usdValue = 50_000e18;
        uint256 expectedEthAmount = 25e18;

        assertEq(lendingPool.getTokenAmountFromUsd(address(0), usdValue), expectedEthAmount);
    }

    function test_getUSDCAmountFromUsd() public {
        /**
         * USDC Price: 1USD/USDC
         * Total usd amount: 15,000USD
         * USDC amount = 15,000USD / 1USD/USDC = 15_000 USDC = 15000_000_000
         */

        uint256 usdValue = 15_000e18;
        uint256 expectedUsdcAmount = 15000_000_000;

        assertEq(lendingPool.getTokenAmountFromUsd(address(usdcToken), usdValue), expectedUsdcAmount);
    }

    function test_healthFactorNotOK() public depositCollateral(user, 10 ether) {
        /**
         * Deposit 10 ether a 2000USD/ETH -> 20_000 USDC en ETH
         * Borrow  17_000 USDC -> 17_000 USD en USDC
         * HF = 0.8 * 20_000 / 17_000 = 16_000 / 17_000 = 0.941176.... NOT OK!
         */

        //vm.expectRevert(LendingPool.LendingPool__HealthFactorBroken.selector);
        //vm.prank(user);
        //lendingPool.borrow(17_000e6);

        //vm.expectRevert(LendingPool.LendingPool__HealthFactorBroken.selector);
        //vm.prank(user);
        //lendingPool.checkHealthFactor();
    }

    function test_healthFactorOK() public depositCollateral(user, 10 ether) {
        /**
         * Deposit 10 ether a 2000USD/ETH -> 20_000 USDC en ETH
         * Borrow  12_000 USDC -> 12_000 USD en USDC
         * HF = 0.8 * 20_000 / 12_000 = 16_000 / 12_000 = 1.3333333.... OK!
         */

        // vm.prank(user);
        // lendingPool.borrow(12_000e6);

        vm.prank(user);
        lendingPool.checkHealthFactor(20_000e18, 12_000e6);
    }

    function _mintAndApprove(address _user, address _spender, uint256 _amount, address _token) private {
        if (_token == address(0)) {
            return;
        }

        ERC20Mock(_token).mint(_user, _amount);
        vm.prank(_user);
        ERC20Mock(_token).approve(_spender, _amount);
    }
}
