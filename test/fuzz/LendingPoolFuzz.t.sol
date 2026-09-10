// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
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

contract LendingPoolFuzz is Test {
    uint256 constant MAX_COLLATERAL = 1 ether;
    uint256 private constant MIN_HEALTHFACTOR = 1e18;
    uint256 private constant LIQUIDATOR_COMMISSION = 300;

    address[] public users;
    address[] public borrowers;

    address[] public tokens;
    address[] public priceFeeds;

    DeployLendingPool public deployer;
    HelperConfig config;
    LendingPool public lendingPool;
    RewardController public rewardController;
    StakingRewards public staking;
    DepositToken public depositToken;
    PriceOracle public priceOracle;
    ERC20Mock public usdcToken;

    function setUp() public {
        deployer = new DeployLendingPool();
        (lendingPool, rewardController, staking, priceOracle, config) = deployer.run();

        usdcToken = ERC20Mock(config.getNetworkConfig().usdc);
        usdcToken.mint(address(lendingPool), 1_000_000e6);

        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(user, 1_000_000 ether);
            usdcToken.mint(user, 1_000_000e6);
            users.push(user);
        }
    }

    function testFuzz_depositCollateral(uint256 _amount, uint256 _userSeed) public {
        address user = _getUserFromSeed(_userSeed);
        uint256 amountBounded = bound(_amount, 1e10, MAX_COLLATERAL);

        _addLiquidity(user, 10_000e6);

        vm.prank(user);
        lendingPool.depositCollateral{value: amountBounded}();
    }

    function testFuzz_liquidate(uint256 _depositAmount, uint256 _borrowAmount, uint128 _userSeed, uint256 _priceSeed)
        public
    {
        address borrower = _getUserFromSeed(_userSeed);
        address liquidator = _getUserFromSeed(uint256(_userSeed) + 1);
        address supplier = _getUserFromSeed(uint256(_userSeed) + 2);

        _addLiquidity(supplier, 10_000e6);
        _depositCollateral(_depositAmount, borrower);
        _borrow(_borrowAmount, borrower);

        uint256 borrowerDebt = lendingPool.getDebt(borrower);
        uint256 borrowerCollateral = lendingPool.getCollateral(borrower);

        int256 ethPrice = int256(bound(_priceSeed, 1800e8, 100_000e8));
        MockAggregatorV3(config.getNetworkConfig().ethPriceFeed).updateAnswer(ethPrice);
        uint256 amountToLiquidate = lendingPool.getDebt(borrower) * 5_000 / 10_000;
        uint256 expectedLiquidatorRevenue = _getLiquidatorExpectedETHRevenue(borrower, amountToLiquidate);

        _mintAndApprove(liquidator, address(lendingPool), amountToLiquidate, address(usdcToken));

        uint256 hf = lendingPool.getHealthFactor(borrower);
        if (hf < MIN_HEALTHFACTOR) {
            vm.prank(liquidator);
            lendingPool.liquidate(borrower, amountToLiquidate);
            assertEq(lendingPool.getDebt(borrower), borrowerDebt - amountToLiquidate, "FINAL DEBT NOT MATCH");
            assertEq(
                lendingPool.getCollateral(borrower),
                borrowerCollateral - expectedLiquidatorRevenue,
                "FINAL COLLATERAL NOT MATCH"
            );
        } else {
            vm.expectRevert(LendingPool.LendingPool__HealthFactorOK.selector);
            lendingPool.liquidate(borrower, amountToLiquidate);
        }

        assertNotEq(borrower, liquidator, "Liquidator and borrowe are the same!");
    }

    function _depositCollateral(uint256 _amount, address _user) private {
        uint256 amountBounded = bound(_amount, 1e10, MAX_COLLATERAL);

        vm.prank(_user);
        lendingPool.depositCollateral{value: amountBounded}();
    }

    function _borrow(uint256 _amount, address _user) private {
        uint256 userCollateral = lendingPool.getCollateral(_user);
        _amount = bound(_amount, 1e6, 1e30);

        if (userCollateral == 0) {
            return;
        }

        uint256 userDebt = lendingPool.getDebt(_user);

        address usdcToken = config.getNetworkConfig().usdc;
        uint256 userDebtValueInUsd = lendingPool.getUsdValue(usdcToken, userDebt);
        uint256 maxUsdValueToBorrow = lendingPool.getMaxLending(userCollateral);

        if (userDebtValueInUsd >= maxUsdValueToBorrow) {
            return;
        }
        uint256 amountInUsd = lendingPool.getUsdValue(usdcToken, _amount);
        uint256 amountBounded = amountInUsd % (maxUsdValueToBorrow - userDebtValueInUsd);

        uint256 amountToBorrow = lendingPool.getTokenAmountFromUsd(usdcToken, amountBounded);

        vm.prank(_user);
        lendingPool.borrow(amountToBorrow);
    }

    function _getLiquidatorExpectedETHRevenue(address _target, uint256 _debtToLiquidate) private returns (uint256 eth) {
        uint256 targetDebt = lendingPool.getDebt(_target);
        uint256 targetCollateral = lendingPool.getCollateral(_target);

        uint256 debtToLiquidateInUsd = lendingPool.getUsdValue(address(usdcToken), _debtToLiquidate);
        uint256 debtToLiquidateInETH = lendingPool.getTokenAmountFromUsd(address(0), debtToLiquidateInUsd);

        uint256 WAD = 1e18;
        uint256 fee = 0.03e18;
        uint256 base = WAD + fee;
        eth = debtToLiquidateInETH * base / WAD;
    }

    function _getUserFromSeed(uint256 _indexSeed) private returns (address) {
        return users[_indexSeed % users.length];
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
}
