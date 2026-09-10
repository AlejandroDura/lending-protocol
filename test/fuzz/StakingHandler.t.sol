// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StakingRewards} from "src/StakingRewards.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract StakingHandler is Test {
    HelperConfig config;
    uint256 constant MAX_DEPOSIT = 1 ether;
    uint256 constant MAX_ADD_LIQUIDITY = 1000e6;
    address[] public suppliers;
    address[] public borrowers;
    StakingRewards staking;

    mapping(address => uint256) public ghost_borrowerDebt;
    uint256 public ghost_totalRewards;
    mapping(address => uint256) public ghost_supplierRewardsClaimed;

    constructor(StakingRewards _staking, address[] memory _suppliers, address[] memory _borrowers) {
        suppliers = _suppliers;
        borrowers = _borrowers;
        staking = _staking;
        vm.deal(address(this), 1_000_000_000 ether);
    }

    function addLiquidity(uint256 _amount, uint256 _userSeed) public {
        address supplier = _getSupplier(_userSeed);
        uint256 amountBounded = bound(_amount, 0.1e6, MAX_ADD_LIQUIDITY);

        staking.addLiquidity(supplier, amountBounded);
    }

    function lend(uint256 _amount, uint256 _userSeed) public {
        //Hacer prev y post comprovacion de nav. Debe de incrementar despues del lend
        //COmprobar tambien que el share price incremente despues de hacer el lend, ya que el nav debe subir
        uint256 liquidity = staking.getLiquidity();
        if (liquidity == 0) {
            return;
        }

        uint256 amountBounded = bound(_amount, 0, liquidity / 10);

        if (amountBounded == 0) {
            return;
        }

        uint256 prevNav = staking.getNav();
        uint256 prevPrice = staking.getSharePrice();

        address borrower = _getBorrower(_userSeed);
        staking.lend(borrower, amountBounded);
        ghost_borrowerDebt[borrower] += amountBounded;

        uint256 postNav = staking.getNav();
        uint256 postPrice = staking.getSharePrice();

        assertGt(postNav, prevNav, "Nav increment failed");
        assertGt(postPrice, prevPrice, "Price share increment failed");
    }

    function repay(uint256 _userSeed) public {
        address borrower = _getBorrower(_userSeed);
        uint256 amountRepay = ghost_borrowerDebt[borrower] / 2;

        if (amountRepay == 0) {
            return;
        }

        staking.repay(borrower, amountRepay);
        ghost_borrowerDebt[borrower] -= amountRepay;
    }

    function removeLiquidity(uint256 _userSeed) public {
        address supplier = _getSupplier(_userSeed);

        uint256 shares = staking.getUserShare(supplier) / 2;
        if (shares == 0) {
            return;
        }

        uint256 amount = shares * staking.getNav() / staking.getTotalShares();
        if (amount > staking.getLiquidity()) {
            return;
        }

        staking.removeLiquidity(supplier, shares);
    }

    ////////////////
    //ETH rewards//
    //////////////

    function addETHRewards(uint256 _amount) public {
        if (staking.getLiquidity() == 0) {
            return;
        }

        //uint256 amountBounded = _amount % (1 ether - 1);
        //uint256 amountBounded = 0.05 ether;
        uint256 amountBounded = (_amount % 2 == 0) ? 0.05 ether : 0.02 ether;

        if (amountBounded == 0) {
            return;
        }

        uint256 prevAccRewards = staking.getAccTotalETHRewardsPerShare();
        staking.addETHRewards{value: amountBounded}();
        ghost_totalRewards += amountBounded;
        uint256 postAccRewards = staking.getAccTotalETHRewardsPerShare();

        assertGt(postAccRewards, prevAccRewards, "Accumulated rewards per share increment failed!!!");
    }

    function claim(uint256 _userSeed) public {
        address supplier = _getSupplier(_userSeed);

        uint256 amountToClaim = staking.getUserPendingRewards(supplier) + staking.getUserPendingToClaimRewards(supplier);
        if (amountToClaim == 0) {
            return;
        }

        staking.claim(supplier);
        ghost_supplierRewardsClaimed[supplier] += amountToClaim;
    }

    function _getSupplier(uint256 _seed) private returns (address) {
        return suppliers[_seed % suppliers.length];
    }

    function _getBorrower(uint256 _seed) private returns (address) {
        return borrowers[_seed % borrowers.length];
    }
}
