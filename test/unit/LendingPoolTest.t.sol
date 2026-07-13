// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "src/LendingPool.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {MockUSDC} from "test/mocks/MockUSDC.sol";
import {MockAggregatorV3Interface} from "test/mocks/MockAggregatorV3Interface.sol";

contract LendingPoolTest is Test {
    address user;

    address[] public tokens;
    address[] public priceFeeds;

    LendingPool public lendingPool;
    DepositToken public depositToken;
    PriceOracle public priceOracle;
    MockUSDC public usdcToken;

    function setUp() public {
        user = makeAddr("user");
        vm.deal(user, 1_000_000 ether);

        usdcToken = new MockUSDC("USDC", "USDC", address(this), 0);

        tokens.push(address(0));
        priceFeeds.push(address(new MockAggregatorV3Interface(8, 2000e8)));

        tokens.push(address(usdcToken));
        priceFeeds.push(address(new MockAggregatorV3Interface(8, 1e8)));

        depositToken = new DepositToken();
        priceOracle = new PriceOracle(tokens, priceFeeds);
        lendingPool = new LendingPool(address(depositToken), address(usdcToken), address(priceOracle));

        usdcToken.mint(address(lendingPool), 1_000_000e6);
    }

    modifier depositCollateral(address _user, uint256 _amount) {
        vm.prank(_user);
        lendingPool.depositCollateral{value: _amount}();
        _;
    }

    function test_depositCollateral() public {
        vm.prank(user);
        lendingPool.depositCollateral{value: 10 ether}();

        assertEq(lendingPool.getCollateral(user), 10 ether);
    }

    function test_borrow() public depositCollateral(user, 10 ether) {
        uint256 amountToBorrow = 200e6;
        vm.prank(user);
        lendingPool.borrow(amountToBorrow);

        assertEq(lendingPool.getDebt(user), amountToBorrow);
    }

    function test_withdrawCollateral() public depositCollateral(user, 10 ether) {
        vm.prank(user);
        lendingPool.withdrawCollateral(10 ether);

        assertEq(lendingPool.getCollateral(user), 0);
    }

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
}
