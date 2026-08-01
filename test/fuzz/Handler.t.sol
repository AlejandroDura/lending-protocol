// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "src/LendingPool.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract Handler is Test {
    HelperConfig config;
    uint256 constant MAX_DEPOSIT = 1 ether;
    address[] public users;
    LendingPool lendingPool;

    constructor(LendingPool _lendingPool, HelperConfig _config, address[] memory _users) {
        users = _users;
        lendingPool = _lendingPool;
        config = _config;
    }

    function depositCollateral(uint256 _amount, uint256 _userSeed) public {
        address user = _getUserFromSeed(_userSeed);
        uint256 amountBounded = bound(_amount, 1e10, MAX_DEPOSIT);

        vm.prank(user);
        lendingPool.depositCollateral{value: amountBounded}();
    }

    function borrow(uint128 _amount, uint256 _userSeed) public {
        address user = _getUserFromSeed(_userSeed);
        uint256 userCollateral = lendingPool.getCollateral(user);

        if (userCollateral == 0) {
            return;
        }

        uint256 userDebt = lendingPool.getDebt(user);

        address usdcToken = config.getNetworkConfig().usdc;
        uint256 userDebtValueInUsd = lendingPool.getUsdValue(usdcToken, userDebt);
        uint256 maxUsdValueToBorrow = lendingPool.getMaxLending(userCollateral);

        if (userDebtValueInUsd >= maxUsdValueToBorrow) {
            return;
        }
        uint256 amountInUsd = lendingPool.getUsdValue(usdcToken, _amount);
        uint256 amountBounded = amountInUsd % (maxUsdValueToBorrow - userDebtValueInUsd);

        uint256 amountToBorrow = lendingPool.getTokenAmountFromUsd(usdcToken, amountBounded);
        //uint256 amountToBorrow = amountInUsd;

        vm.prank(user);
        lendingPool.borrow(amountToBorrow);

        assertGt(userCollateral, 0);
    }

    function _getUserFromSeed(uint256 _indexSeed) private returns (address) {
        return users[_indexSeed % users.length];
    }
}
