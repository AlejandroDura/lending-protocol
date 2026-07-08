// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "src/LendingPool.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {MockUSDC} from "src/tokens/MockUSDC.sol";

contract LendingPoolTest is Test {
    address user;

    LendingPool public lendingPool;
    DepositToken public depositToken;
    PriceOracle public priceOracle;
    MockUSDC public usdcToken;

    function setUp() public {
        user = makeAddr("user");
        vm.deal(user, 1_000_000 ether);

        depositToken = new DepositToken();
        priceOracle = new PriceOracle();
        usdcToken = new MockUSDC("USDC", "USDC", address(this), 0);
        lendingPool = new LendingPool(address(depositToken), address(usdcToken), address(priceOracle));

        usdcToken.mint(address(lendingPool), 10_000e6);
    }

    modifier depostiCollateral(address _user, uint256 _amount) {
        vm.prank(_user);
        lendingPool.depositCollateral{value: _amount}();
        _;
    }

    function test_depositCollateral() public {
        vm.prank(user);
        lendingPool.depositCollateral{value: 10 ether}();

        assertEq(lendingPool.getCollateral(user), 10 ether);
    }

    function test_withdrawCollateral() public depostiCollateral(user, 10 ether) {
        vm.prank(user);
        lendingPool.withdrawCollateral(10 ether);

        assertEq(lendingPool.getCollateral(user), 0);
    }
}
