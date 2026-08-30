// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceOracle} from "./PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {HealthFactor} from "src/libraries/HealthFactor.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {console} from "forge-std/console.sol";

contract StakingRewards is ReentrancyGuard {
    struct UserInfo {
        uint256 accETHRewardsPerShare;
        uint256 shares;
        uint256 pending;
    }
    error StakingRewards__InvalidInputs();
    error StakingRewards__InvalidLiquidityToRetrieve();
    error StakingRewards__InvalidNavAmount();
    error StakingRewards__InvalidShareAmount();
    error StakingRewards__InvalidLiquidityToRemove();
    error StakingRewards__NoUsdcLiquidityInTheSystem();
    error StakingRewards__NoLiquidityInTheSystem();
    error StakingRewards__ThereIsNotEnoughLiquidityAvailable();
    error StakingRewards__NoRewardsToClaim();
    error StakingRewards__TransactionRevert();

    uint256 private constant BPS_PRECISION = 10_000;
    uint256 private constant LEND_FEE_BPS = 300;
    uint256 private constant EIGHTEEN_PRECISION = 1e18;

    uint256 private usdcLiquidity;
    uint256 private nav;
    mapping(address => UserInfo) private userInfo;
    uint256 private totalShares;

    uint256 private accTotalETHRewardsPerShare;

    constructor() {}

    function addLiquidity(uint256 _amount) external {
        //Pasa algo si laliquidez cae a 0 y luego se empieza de 0?
        _updateUserRewards();
        uint256 shares = _calculateShares(_amount);

        _updateShares(shares, true);
        _updateLiquidity(_amount, true, true);
    }

    ///////////////
    //USDC STAKE//
    /////////////

    function removeLiquidity(uint256 _shares) external {
        if (totalShares == 0) {
            revert StakingRewards__NoUsdcLiquidityInTheSystem();
        }

        if (_shares > userInfo[msg.sender].shares) {
            revert StakingRewards__InvalidLiquidityToRemove();
        }

        _updateUserRewards();

        //Hacer el claim en una funcion aparte.
        uint256 usdcClaimed = _shares * nav / totalShares;

        if (usdcClaimed > usdcLiquidity) {
            revert StakingRewards__ThereIsNotEnoughLiquidityAvailable();
        }

        _updateShares(_shares, false);
        _updateLiquidity(usdcClaimed, false, true);
    }

    function lend(uint256 _amountToLend) external {
        if (usdcLiquidity == 0) {
            revert StakingRewards__NoLiquidityInTheSystem();
        }

        uint256 amountWithFee = _amountToLend * (BPS_PRECISION - LEND_FEE_BPS) / BPS_PRECISION;
        _updateLiquidity(amountWithFee, false, false);
        _updateNav(_amountToLend - amountWithFee, true);
    }

    function repay(uint256 _amountToRepay) external {
        //COmprabar que el ususario tiene deuda
        _updateLiquidity(_amountToRepay, true, false);
    }

    //////////////
    //ETH STAKE//
    ////////////
    function addETHRewards() external payable {
        _updateRewards(msg.value);
    }

    function claim() external nonReentrant {
        _updateUserRewards();

        uint256 pendingRewards = userInfo[msg.sender].pending;
        if (pendingRewards == 0) {
            revert StakingRewards__NoRewardsToClaim();
        }

        userInfo[msg.sender].pending = 0;
        (bool success,) = payable(msg.sender).call{value: pendingRewards}("");

        if (!success) {
            revert StakingRewards__TransactionRevert();
        }
    }

    ///////////
    //Public//
    /////////

    function getLiquidity() public returns (uint256) {
        return usdcLiquidity;
    }

    function getUserShare(address _user) public returns (uint256) {
        return userInfo[_user].shares;
    }

    function getTotalShares() public returns (uint256) {
        return totalShares;
    }

    function getNav() public returns (uint256) {
        return nav;
    }

    function getSharePrice() public returns (uint256) {
        return _getSharePrice();
    }

    function getAccTotalETHRewardsPerShare() public returns (uint256) {
        return accTotalETHRewardsPerShare / EIGHTEEN_PRECISION;
    }

    function getUserPendingRewards(address _user) public returns (uint256) {
        return userInfo[_user].pending;
    }

    function getUserAccETHRewardsPerShare(address _user) public returns (uint256) {
        return userInfo[_user].accETHRewardsPerShare / EIGHTEEN_PRECISION;
    }

    function getUserPendingToClaimRewards(address _user) public returns (uint256) {
        uint256 accRewardsPerShare = accTotalETHRewardsPerShare - userInfo[_user].accETHRewardsPerShare;
        return accRewardsPerShare * userInfo[_user].shares / EIGHTEEN_PRECISION;
    }

    ////////////
    //private//
    //////////
    function _updateRewards(uint256 _rewards) private {
        if (totalShares == 0) {
            revert StakingRewards__NoLiquidityInTheSystem();
        }

        accTotalETHRewardsPerShare += _rewards * EIGHTEEN_PRECISION / totalShares;
    }

    function _updateUserRewards() private {
        uint256 accRewardsPerShare = accTotalETHRewardsPerShare - userInfo[msg.sender].accETHRewardsPerShare;
        userInfo[msg.sender].pending += accRewardsPerShare * userInfo[msg.sender].shares / EIGHTEEN_PRECISION;
        userInfo[msg.sender].accETHRewardsPerShare = accTotalETHRewardsPerShare;
    }

    function _getSharePrice() private returns (uint256) {
        return nav * 1e18 / totalShares;
    }

    function _calculateShares(uint256 _amount) private returns (uint256) {
        if (nav == 0) {
            return _amount;
        }

        return _amount * totalShares / nav;
    }

    function _updateShares(uint256 _amount, bool add) private {
        uint256 userShares_c = userInfo[msg.sender].shares;
        uint256 totalShares_c = totalShares;

        if (_amount > userShares_c && !add) {
            revert StakingRewards__InvalidShareAmount();
        }

        if (add) {
            userShares_c += _amount;
            totalShares_c += _amount;
        } else {
            userShares_c -= _amount;
            totalShares_c -= _amount;
        }

        userInfo[msg.sender].shares = userShares_c;
        totalShares = totalShares_c;
    }

    function _updateLiquidity(uint256 _amount, bool _add, bool _update_nav) private {
        uint256 liquidity_c = usdcLiquidity;
        if (_amount > liquidity_c && !_add) {
            revert StakingRewards__InvalidLiquidityToRetrieve();
        }

        if (_add) {
            liquidity_c += _amount;
        } else {
            liquidity_c -= _amount;
        }

        usdcLiquidity = liquidity_c;

        if (_update_nav) {
            _updateNav(_amount, _add);
        }
    }

    function _updateNav(uint256 _amount, bool _add) private {
        uint256 nav_c = nav;

        if (_amount > nav_c && !_add) {
            revert StakingRewards__InvalidNavAmount();
        }

        if (_add) {
            nav_c += _amount;
        } else {
            nav_c -= _amount;
        }

        nav = nav_c;
    }
}
