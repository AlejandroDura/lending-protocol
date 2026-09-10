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
import {RewardController} from "src/RewardController.sol";
import {StakingRewards} from "src/StakingRewards.sol";

contract LendingPoolTest is Test {
    address user;
    address liquidator;
    address borrower;
    address supplier;

    DeployLendingPool public deployer;

    HelperConfig config;
    LendingPool public lendingPool;
    RewardController public rewardController;
    StakingRewards public staking;
    DepositToken public depositToken;
    PriceOracle public priceOracle;
    ERC20Mock public usdcToken;

    function setUp() public {
        user = makeAddr("user");
        vm.deal(user, 1_000_000 ether);
        liquidator = makeAddr("liquidator");
        vm.deal(liquidator, 1_000_000 ether);
        borrower = makeAddr("borrower");
        vm.deal(borrower, 1_000_000 ether);
        supplier = makeAddr("supplier");
        vm.deal(supplier, 1_000_000 ether);

        deployer = new DeployLendingPool();
        (lendingPool, rewardController, staking, priceOracle, config) = deployer.run();

        usdcToken = ERC20Mock(config.getNetworkConfig().usdc);
        usdcToken.mint(address(lendingPool), 1_000_000e6);
        usdcToken.mint(supplier, 1_000_000e6);
        usdcToken.mint(user, 1_000_000e6);
        usdcToken.mint(borrower, 1_000_000e6);
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

    //////////////////
    //Add liquidity//
    ////////////////

    function test_addLiquidity() public {
        /**
         * We add 10_000 usdc, so:
         * Supplier shares 10000sh
         * Total liquidity 10000usdc
         */

        uint256 expectedLiquidity = 10_000e6;
        _addLiquidity(supplier, 10_000e6);

        assertEq(staking.getLiquidity(), expectedLiquidity);
        assertEq(staking.getUserShare(supplier), expectedLiquidity);
    }

    function test_addLiquidity_both() public {
        /**
         * We add 10_000 usdc, so:
         * supplier shares 10000sh
         * Total liquidity 10000usdc
         * Total shares 10000sh
         *
         * Then user adds 5000usdc
         * userShares = 5000 usdc * 10000sh / 10000usdc = 0.5 * 10000sh -> 5000sh
         * Total shares = 10000sh + 5000sh = 15000sh
         */

        uint256 expectedLiquidity = 15_000e6;
        _addLiquidity(supplier, 10_000e6);
        _addLiquidity(user, 5_000e6);

        assertEq(staking.getLiquidity(), expectedLiquidity);
        assertEq(staking.getUserShare(user), 5_000e6);
    }

    /////////////////////
    //Remove liquidity//
    ///////////////////

    function test_removeLiquidity() public {
        /**
         * We add 10_000 usdc, so:
         * supplier shares 10000sh
         * Total liquidity 10000usdc
         * Total shares 10000sh
         *
         * Then user adds 5000usdc
         * userShares = 5000 usdc * 10000sh / 10000usdc = 0.5 * 10000sh -> 5000sh
         * Total shares = 10000sh + 5000sh = 15000sh
         *
         * Then supplier removes 10_000 shares
         * Total liquidity 5000 usdc
         */

        uint256 expectedLiquidity = 5_000e6;
        _addLiquidity(supplier, 10_000e6);
        _addLiquidity(user, 5_000e6);

        _removeLiquidity(supplier, 10_000e6);

        assertEq(staking.getLiquidity(), expectedLiquidity);
        assertEq(staking.getUserShare(supplier), 0);
    }
    ////////////
    //Deposit//
    //////////

    function test_depositCollateral() public {
        /**
         * We add 10_000usdc of liquidity
         *
         * We add 10 ether of collateral, we apply 3% of fee and send them to the suppliers rewards
         * collateral = 10 ether * (1 - 0.005) = 10 ether * 0.995 = 9950000000000000000 = 9.95 eth
         * rewards = 10 ether - 9.95 ether = 10000000000000000000 - 9950000000000000000 = 50000000000000000 = 0.05 eth/sh
         *
         * accETHRewardsPerShare = 0.05 ether / 10000sh = 50000000000000000 / 10000000000 = 5000000 wei/sh
         */

        uint256 expectedUserCollateral = 9.95 ether;
        uint256 expectedAccETHRewards = 5000000;

        _addLiquidity(supplier, 10_000e6);

        vm.prank(borrower);
        lendingPool.depositCollateral{value: 10 ether}();

        assertEq(lendingPool.getCollateral(borrower), expectedUserCollateral, "User collateral failed!");
        assertEq(staking.getAccTotalETHRewardsPerShare(), expectedAccETHRewards, "Accumulated ETH reward failed!");
    }

    ///////////
    //Borrow//
    /////////

    function test_borrowExceedsMaxToBorrow() public {
        /**
         * Collateral 10 ETH -> 10 ether * (1 - 0.005) = 10 ether * 0.995 = 9950000000000000000 = 9.95 eth
         * ETH price: 2000USD/ETH
         * Collateral value = 2000USD/ETH * 9.95 ETH = 19,900USD
         * Max to lend = 75% of 19,900USD -> 0.75 * 19,900USD = 14,925USD
         */

        _addLiquidity(supplier, 20_000e6);

        _addCollateral(borrower, 10 ether);

        uint256 amountToBorrow = 14_926e6;
        vm.expectRevert(LendingPool.LendingPool__LendingExceedTheMaximum.selector);
        vm.prank(borrower);
        lendingPool.borrow(amountToBorrow);
    }

    function test_borrow() public {
        /**
         * We add 10_000 usdc, so:
         * supplier shares 10000sh
         * Total liquidity 10000usdc
         * Total shares 10000sh
         *
         * Then we add 10 eth of collateral
         * Max to borrow 0.75 * 10 = 7.5 ether -> 15,000 USD max
         * We take borrowed 10,000 usdc
         * We receive 10,000 * (1 - 0.03) = 10,000usdc * 0.97 = 9700 usdc
         * User debt 10,000 usdc
         * Liquidity after borrow/lend in the system 10,000 usdc - 97000 usdc = 300 usdc
         */

        uint256 expectedBorrowed = 9700e6;
        uint256 expectedUserDebt = 10_000e6;
        uint256 expectedLiquidity = 300e6;

        _addLiquidity(supplier, 10_000e6);

        _addCollateral(borrower, 10 ether);

        _borrow(borrower, 10_000e6);

        assertEq(staking.getLiquidity(), expectedLiquidity, "System liquidity does not match!");
        assertEq(lendingPool.getDebt(borrower), expectedUserDebt, "User debt does not match!");
    }

    //////////
    //Repay//
    ////////
    function test_repay() public {
        /**
         * We add 10_000 usdc, so:
         * supplier shares 10000sh
         * Total liquidity 10000usdc
         * Total shares 10000sh
         *
         * Then we add 10 eth of collateral
         * Max to borrow 0.75 * 10 = 7.5 ether -> 15,000 USD max
         * We take borrowed 10,000 usdc
         * We receive 10,000 * (1 - 0.03) = 10,000usdc * 0.97 = 9700 usdc
         * User debt 10,000 usdc
         * Liquidity after borrow/lend in the system 10,000 usdc - 9700 usdc = 300 usdc
         *
         * Then we repay the 10,000 usdc debt
         * User debt 0
         * Liqudity after repay in the system 10.000usdc + 300usdc = 10.300 usdc
         */

        uint256 expectedLiquidity = 10_300e6;

        _addLiquidity(supplier, 10_000e6);
        _addCollateral(borrower, 10 ether);
        _borrow(borrower, 10_000e6);
        _repay(borrower, 10_000e6);

        assertEq(lendingPool.getDebt(borrower), 0);
        assertEq(staking.getLiquidity(), expectedLiquidity);
    }

    //////////////
    //Liquidate//
    ////////////
    function test_liquidate() public {
        /**
         * We add 20,000 usdc of liquidity
         * Collateral 10 ETH -> 10 ether * (1 - 0.005) = 10 ether * 0.995 = 9950000000000000000 = 9.95 eth
         * ETH price 2000usd/eth
         * Max to lend 9.95 eth * 0.75 = 7.4625 eth = 14,925 usd
         * We take borrowed 14,925USDC, but will receive 14,925 * (1 - 0.03) = 14,925usdc * 0.97 = 14,477.25 usdc
         * Liquidity in the system = 20,000 usdc - 14,477.25 usdc = 5,522.75 usdc
         * User debt = 14,925 usdc
         *
         * ETH Price 2000USD/ETH
         * Collateral price = 9.95 ETH * 2000USD/ETH = 19,900USD
         * ETH price drops to 1800USD/ETH, collateral value now: 9.95 ETH * 1800USD/ETH = 17,910USD
         * HF = 0.8 * 17,910USD / 14,925 USD = 0.96
         *
         * Collateral to redeem = 7,462.5 USD in ETH which is: 7,462.5 USD / 1800USD/ETH = 4.1458333333333333333333333333333 ETH -> 4145833333333333333 WEI
         * Bonus = 4145833333333333333 WEI * 0.03 = 124,374,999,999,999,999.99 = 124374999999999999 (0.124374... ETH)
         * Total to redeem = 4145833333333333333 WEI + 124374999999999999 WEI = 4270208333333333332 WEI = 4.27020... ETH
         *
         * After liquidate
         * ETH price = 1800USD/ETH
         * Collateral = 9.95 ETH - 4.27020 ETH = 9950000000000000000 - 4270208333333333332 = 5679791666666666668 WEI = 5.679791666666666668 ETH
         * Collateral value = 5.679791666666666668 ETH * 1800USD/ETH = 10,223.6250000000000024 USD
         * Borrower debt = 7,462.5 USDC
         * HF = 0.8 * 10,223.6250000000000024 USD / 7,462.5 USDC = 1.0960000000000000002572864321608 this HF is better than before OK!
         *
         * Liquidity in the system 5,522.75 usdc + 7,462.5 usdc = 12,985.25 usdc
         */

        uint256 amountToLiquidate = 7462.5e6;
        uint256 expectedToRedeem = 4270208333333333332;
        uint256 expectedBorrowerDebt = 7462.5e6;
        uint256 expectedBorrowerCollateral = 9.95 ether - expectedToRedeem;
        uint256 expectedLiquidity = 12985.25e6;

        _addLiquidity(supplier, 20_000e6);
        _addCollateral(borrower, 10 ether);
        _borrow(borrower, 14_925e6);

        _setPrice(address(0), 1800e8);

        _liquidate(address(usdcToken), liquidator, borrower, amountToLiquidate);

        assertEq(lendingPool.getDebt(borrower), expectedBorrowerDebt, "DEBT ASSERT FAILED!");
        assertEq(lendingPool.getCollateral(borrower), expectedBorrowerCollateral, "COLLATERAL ASSERT FAILED!");
        assertEq(staking.getLiquidity(), expectedLiquidity, "LIQUIDITY FAILED!");
    }

    /////////////
    //Withdraw//
    ///////////

    function test_withdrawCollateral() public {
        /**
         * Collateral 10 ether -> 10 ether * (1 - 0.005) = 10 ether * 0.995 = 9.95 ether
         */
        _addLiquidity(supplier, 10_00e6);
        _addCollateral(borrower, 10 ether);

        vm.prank(borrower);
        lendingPool.withdrawCollateral(9.95 ether);

        assertEq(lendingPool.getCollateral(borrower), 0);
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

    function test_healthFactorNotOK() public {
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

    function test_healthFactorOK() public {
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

    function _addLiquidity(address _user, uint256 _amount) private {
        vm.startPrank(_user);
        usdcToken.approve(address(lendingPool), _amount);
        lendingPool.addLiquidity(_amount);
        vm.stopPrank();
    }

    function _removeLiquidity(address _user, uint256 _shares) private {
        vm.prank(_user);
        lendingPool.removeLiquidity(_shares);
    }

    function _addCollateral(address _user, uint256 _amount) private {
        vm.prank(_user);
        lendingPool.depositCollateral{value: _amount}();
    }

    function _borrow(address _user, uint256 _amount) private {
        vm.prank(_user);
        lendingPool.borrow(_amount);
    }

    function _repay(address _user, uint256 _amount) private {
        vm.startPrank(_user);
        IERC20(usdcToken).approve(address(lendingPool), _amount);
        lendingPool.repay(_amount);
        vm.stopPrank();
    }

    function _setPrice(address _token, uint256 _newPrice) private {
        address ethPriceOracle = priceOracle.getPriceOracle(address(0));
        MockAggregatorV3(ethPriceOracle).updateAnswer(1800e8);
    }

    function _liquidate(address _tokenToLiquidate, address _liquidator, address _borrower, uint256 _amountToLiquidate)
        private
    {
        _mintAndApprove(_liquidator, address(lendingPool), _amountToLiquidate, _tokenToLiquidate);

        vm.prank(_liquidator);
        lendingPool.liquidate(_borrower, _amountToLiquidate);
    }
}
