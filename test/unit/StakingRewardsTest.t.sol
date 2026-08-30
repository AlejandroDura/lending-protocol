// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StakingRewards} from "src/StakingRewards.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DeployLendingPool} from "script/DeployLendingPool.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract LendingPoolTest is Test {
    uint256 private constant EIGHTEEN_PRECISION = 1e18;

    address userA;
    address userB;
    address liquidator;

    DeployLendingPool public deployer;

    HelperConfig config;
    DepositToken public depositToken;
    PriceOracle public priceOracle;
    ERC20Mock public usdcToken;
    StakingRewards public staking;

    function setUp() public {
        userA = makeAddr("usera");
        userB = makeAddr("userb");
        vm.deal(userA, 1_000_000 ether);
        liquidator = makeAddr("liquidator");
        vm.deal(liquidator, 1_000_000 ether);

        vm.deal(address(this), 1_000_000 ether);
        // deployer = new DeployLendingPool();
        // (lendingPool, priceOracle, config) = deployer.run();

        staking = new StakingRewards();

        //usdcToken = ERC20Mock(config.getNetworkConfig().usdc);
    }

    //////////////////
    //Add liquidity//
    ////////////////

    function test_addLiquidityOnce() external {
        /**
         * Add 5000 USDC as liquidity so:
         * totalLiquidity = 5000 USDC
         * nav = 5000USDC;
         * shares = 5000e6
         * totalShares = 5000e6
         * sharePrice = nav / totalShares = 5000USDC / 5000e16 = 1 USDC/share = 1000000000000000000
         */

        uint256 expectedPrice = 1000000000000000000;

        vm.prank(userA);
        staking.addLiquidity(5000e6);

        assertEq(staking.getLiquidity(), 5000e6, "LIQUIDITY FAILED");
        assertEq(staking.getNav(), 5000e6, "NAV FAILED");
        assertEq(staking.getUserShare(userA), 5000e6, "USER SHARE FAILED");
        assertEq(staking.getTotalShares(), 5000e6, "TOTAL SHARES FAILED");
        assertEq(staking.getSharePrice(), expectedPrice, "PRICE FAILED");
    }

    function test_addLiquidityBoth() external {
        /**
         * UserA
         * Add 5000 USDC as liquidity so:
         * totalLiquidity = 5000 USDC
         * nav = 5000USDC;
         * shares = 5000e6
         * totalShares = 5000e6
         * sharePrice = nav / totalShares = 5000USDC / 5000e16 = 1 USDC/share = 1000000000000000000
         *
         *
         * UserB
         * Add 10000 USCD as liquidity so:
         * expectedShare = 10000 usdc * 5000e6 shares / 5000usdc = 10,000 shares = 10000e6
         * totalShares = 5000e6 + 10000e6 = 15000e6
         * userShares = 10000e6
         * totalLiquidity = 5000 usdc + 10000usdc = 15000usdc
         * nav = 5000USDC + 10000usdc = 15000usdc
         * sharePrice = nsv / totalShares = 15000usdc / 15000e6 = 1 usdc/share = 1e18
         *
         */
        _addLiquidity(5000e6, userA);
        _addLiquidity(10000e6, userB);
        uint256 expectedPrice = 1000000000000000000;

        assertEq(staking.getLiquidity(), 15000e6, "LIQUIDITY FAILED");
        assertEq(staking.getNav(), 15000e6, "NAV FAILED");
        assertEq(staking.getUserShare(userB), 10000e6, "USER SHARE FAILED");
        assertEq(staking.getTotalShares(), 15000e6, "TOTAL SHARES FAILED");
        assertEq(staking.getSharePrice(), expectedPrice, "PRICE FAILED");
    }

    /////////////////////
    //Remove liquidity//
    ///////////////////

    function test_removeLiquidity() external {
        /**
         * UserA Add:
         * Add 5000 USDC as liquidity so:
         * totalLiquidity = 5000 USDC
         * nav = 5000USDC;
         * shares = 5000e6
         * totalShares = 5000e6
         * sharePrice = nav / totalShares = 5000USDC / 5000e16 = 1 USDC/share = 1000000000000000000
         *
         *
         * UserA removes 1000sh
         * usdcToRetrieve = 1000sh * 5000usdc / 5000sh = 1000usdc
         * userShares = 5000sh - 1000sh = 4000sh
         * totalShares = 5000sh - 1000sh = 4000sh
         * totalLiquidity = 5000 usdc - 1000 usdc = 4000 usdc
         * nav = 5000usdc - 1000 usdc = 4000 usdc
         * sharePrice = nav / totalShares = 4000 usdc / 4000sh = 1 -> 1e18
         */

        _addLiquidity(5000e6, userA);
        _removeLiquidity(1000e6, userA);

        uint256 expectedPrice = 1000000000000000000;

        assertEq(staking.getLiquidity(), 4000e6, "LIQUIDITY FAILED");
        assertEq(staking.getNav(), 4000e6, "NAV FAILED");
        assertEq(staking.getUserShare(userA), 4000e6, "USER SHARE FAILED");
        assertEq(staking.getTotalShares(), 4000e6, "TOTAL SHARES FAILED");
        assertEq(staking.getSharePrice(), expectedPrice, "PRICE FAILED");
    }

    function test_removeLiquidityTwo() external {
        /**
         * UserA
         * Add 5000 USDC as liquidity so:
         * totalLiquidity = 5000 USDC
         * nav = 5000USDC;
         * userShares = 5000e6
         * totalShares = 5000e6
         * sharePrice = nav / totalShares = 5000USDC / 5000e16 = 1 USDC/share = 1000000000000000000
         *
         *
         * UserB
         * Add 10000 USCD as liquidity so:
         * expectedShare = 10000 usdc * 5000e6 shares / 5000usdc = 10,000 shares = 10000e6
         * totalShares = 5000e6 + 10000e6 = 15000e6
         * userShares = 10000e6
         * totalLiquidity = 5000 usdc + 10000usdc = 15000usdc
         * nav = 5000USDC + 10000usdc = 15000usdc
         * sharePrice = nsv / totalShares = 15000usdc / 15000e6 = 1 usdc/share = 1e18
         *
         * UserA removes 2000sh
         * usdcToRetrieve = 2000sh * 15000usdc / 15000sh = 2000usdc
         * userShares = 5000sh - 2000sh = 3000sh
         * totalShares = 15000sh - 2000sh = 13000sh
         * totalLiquidity = 15000 usdc - 2000 usdc = 13000 usdc
         * nav = 15000usdc - 2000 usdc = 13000 usdc
         * sharePrice = nav / totalShares = 13000 usdc / 13000sh = 1 -> 1e18
         */

        _addLiquidity(5000e6, userA);
        _addLiquidity(10000e6, userB);
        _removeLiquidity(2000e6, userA);

        uint256 expectedPrice = 1000000000000000000;

        assertEq(staking.getLiquidity(), 13000e6, "LIQUIDITY FAILED");
        assertEq(staking.getNav(), 13000e6, "NAV FAILED");
        assertEq(staking.getUserShare(userA), 3000e6, "USER SHARE FAILED");
        assertEq(staking.getTotalShares(), 13000e6, "TOTAL SHARES FAILED");
        assertEq(staking.getSharePrice(), expectedPrice, "PRICE FAILED");
    }

    /////////
    //Lend//
    ///////

    function test_lend() public {
        /**
         * UserA
         * Add 10000 USDC as liquidity so:
         * totalLiquidity = 10000 USDC
         * nav = 10000USDC;
         * userShares = 10000e6
         * totalShares = 10000e6
         * sharePrice = nav / totalShares = 10000USDC / 10000e16 = 1 USDC/share = 1000000000000000000
         *
         * Lend
         * userB takes 5000USDC
         * fee 3%
         * amountWithFee = 5000USDC * (1 - 0.03) = 5000usdc *  0.97 = 4850usdc
         * totalLiquidity = 10000usdc - 4850usdc =  5150 usdc
         * nav = 10000usdc + (5000usdc - 4850usdc) = 10000usdc + 150 usdc = 10150 usdc
         * sharePrice = nav / totalShares = 10150usdc / 10000e6 = 1.015 usdc/share = 1015000000000000000
         */

        uint256 expectedPrice = 1015000000000000000;

        _addLiquidity(10000e6, userA);
        _lend(5000e6, userB);

        assertEq(staking.getLiquidity(), 5150e6, "LIQUIDITY FAILED");
        assertEq(staking.getNav(), 10150e6, "NAV FAILED");
        assertEq(staking.getUserShare(userA), 10000e6, "USER SHARE FAILED");
        assertEq(staking.getTotalShares(), 10000e6, "TOTAL SHARES FAILED");
        assertEq(staking.getSharePrice(), expectedPrice, "PRICE FAILED");
    }

    //////////
    //Repay//
    ////////

    function test_repay() public {
        /**
         * UserA
         * Add 10000 USDC as liquidity so:
         * totalLiquidity = 10000 USDC
         * nav = 10000USDC;
         * userShares = 10000e6
         * totalShares = 10000e6
         * sharePrice = nav / totalShares = 10000USDC / 10000e16 = 1 USDC/share = 1000000000000000000
         *
         * Lend
         * userB takes 5000USDC
         * fee 3%
         * amountWithFee = 5000USDC * (1 - 0.03) = 5000usdc *  0.97 = 4850usdc
         * totalLiquidity = 10000usdc - 4850usdc =  5150 usdc
         * nav = 10000usdc + (5000usdc - 4850usdc) = 10000usdc + 150 usdc = 10150 usdc
         * sharePrice = nav / totalShares = 10150usdc / 10000e6 = 1.015 usdc/share = 1015000000000000000
         *
         * UserB repays 5000USDC
         * totalLiquidity = 5150 usdc + 5000usdc = 10150 usdc
         */

        uint256 expectedPrice = 1015000000000000000;

        _addLiquidity(10000e6, userA);
        _lend(5000e6, userB);
        _repay(5000e6, userB);

        assertEq(staking.getLiquidity(), 10150e6, "LIQUIDITY FAILED");
        assertEq(staking.getNav(), 10150e6, "NAV FAILED");
        assertEq(staking.getUserShare(userA), 10000e6, "USER SHARE FAILED");
        assertEq(staking.getTotalShares(), 10000e6, "TOTAL SHARES FAILED");
        assertEq(staking.getSharePrice(), expectedPrice, "PRICE FAILED");
    }

    ////////////
    //Rewards//
    //////////
    function test_addRewardsWithoutLiquidity() public {
        vm.expectRevert(StakingRewards.StakingRewards__NoLiquidityInTheSystem.selector);
        payable(address(staking)).call{value: 1 ether}(abi.encodeWithSignature("addETHRewards()"));

        assertEq(staking.getAccTotalETHRewardsPerShare(), 0);
        assertEq(staking.getUserAccETHRewardsPerShare(userA), 0);
        assertEq(staking.getUserPendingRewards(userA), 0);
    }

    function test_addRewardsWithLiquidity() public {
        /**
         * UserA
         * Add 10000 USDC as liquidity so:
         * totalLiquidity = 10000 USDC
         * nav = 10000USDC;
         * userShares = 10000e6
         * totalShares = 10000e6
         * sharePrice = nav / totalShares = 10000USDC / 10000e16 = 1 USDC/share = 1000000000000000000
         *
         * Then adds 1ETH of rewards to the system
         * accTotalETHRewardsPerShare = rewards / totalShares = 1 ETH / 10000e6
         * 1000000000000000000 / 10000000000 = 100000000 wei / share
         *
         */

        uint256 totalShares = 10000e6;
        uint256 expectedTotalAccETHRewardsPerShare = 100000000;

        _addLiquidity(10000e6, userA);
        _addETHRewards(1 ether);

        assertEq(staking.getAccTotalETHRewardsPerShare(), expectedTotalAccETHRewardsPerShare);
        assertEq(staking.getUserAccETHRewardsPerShare(userA), 0);
        assertEq(staking.getUserPendingRewards(userA), 0);
        assertEq(expectedTotalAccETHRewardsPerShare * totalShares, 1 ether);
        assertEq(address(staking).balance, 1 ether);
    }

    //////////
    //Claim//
    ////////
    function test_claimBeforeRewardsUpdate() public {
        /**
         * UserA
         * Add 10000 USDC as liquidity so:
         * totalLiquidity = 10000 USDC
         * nav = 10000USDC;
         * userShares = 10000e6
         * totalShares = 10000e6
         * sharePrice = nav / totalShares = 10000USDC / 10000e16 = 1 USDC/share = 1000000000000000000
         *
         * Then adds 1ETH of rewards to the system
         * accTotalETHRewardsPerShare = rewards / totalShares = 1 ETH / 10000e6
         * 1000000000000000000 / 10000000000 = 100000000 wei / share
         *
         * Then userB adds liquidity and try to claim. It should not claim till new rewards update.
         */

        uint256 totalShares = 10000e6;
        uint256 expectedTotalAccETHRewardsPerShare = 100000000;

        _addLiquidity(10000e6, userA);
        _addETHRewards(1 ether);
        _addLiquidity(5000e6, userB);

        vm.prank(userB);
        vm.expectRevert(StakingRewards.StakingRewards__NoRewardsToClaim.selector);
        staking.claim();

        assertEq(staking.getAccTotalETHRewardsPerShare(), expectedTotalAccETHRewardsPerShare);
        assertEq(staking.getUserAccETHRewardsPerShare(userB), expectedTotalAccETHRewardsPerShare);
        assertEq(staking.getUserPendingRewards(userB), 0);
        assertEq(expectedTotalAccETHRewardsPerShare * totalShares, 1 ether);
    }

    function test_claimAfterRewardsUpdate() public {
        /**
         * UserA
         * Add 10000 USDC as liquidity so:
         * totalLiquidity = 10000 USDC
         * nav = 10000USDC;
         * userShares = 10000e6
         * totalShares = 10000e6
         * sharePrice = nav / totalShares = 10000USDC / 10000e16 = 1 USDC/share = 1000000000000000000
         *
         * Then adds 1ETH of rewards to the system
         * accTotalETHRewardsPerShare = rewards / totalShares = 1 ETH / 10000e6
         * 1000000000000000000 / 10000000000 = 100000000 wei / share
         *
         */

        uint256 totalShares = 10000e6;
        uint256 expectedTotalAccETHRewardsPerShare = 100000000;

        _addLiquidity(10000e6, userA);
        _addETHRewards(1 ether);

        vm.prank(userA);
        //vm.expectRevert(StakingRewards.StakingRewards__NoRewardsToClaim.selector);
        staking.claim();

        assertEq(staking.getAccTotalETHRewardsPerShare(), expectedTotalAccETHRewardsPerShare);
        assertEq(staking.getUserAccETHRewardsPerShare(userA), expectedTotalAccETHRewardsPerShare);
        assertEq(staking.getUserPendingRewards(userA), 0);
        assertEq(expectedTotalAccETHRewardsPerShare * totalShares, 1 ether);
    }

    function _addLiquidity(uint256 _amount, address _user) private {
        vm.prank(_user);
        staking.addLiquidity(_amount);
    }

    function _removeLiquidity(uint256 _shares, address _user) private {
        vm.prank(_user);
        staking.removeLiquidity(_shares);
    }

    function _lend(uint256 _amount, address _user) private {
        vm.prank(_user);
        staking.lend(_amount);
    }

    function _repay(uint256 _amount, address _user) private {
        vm.prank(_user);
        staking.repay(_amount);
    }

    function _addETHRewards(uint256 _rewards) private {
        payable(address(staking)).call{value: _rewards}(abi.encodeWithSignature("addETHRewards()"));
    }
}
