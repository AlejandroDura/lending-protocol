// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceOracle} from "./PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Calculations} from "src/libraries/Calculations.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakingRewards is ReentrancyGuard, Ownable {
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

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /**
     * Add liquidity to the system in USDC.
     * @param _supplier user supplier address.
     * @param _amount amount in USDC to stake.
     */
    function addLiquidity(address _supplier, uint256 _amount) external onlyOwner {
        //Pasa algo si laliquidez cae a 0 y luego se empieza de 0?
        _updateUserRewards(_supplier);
        uint256 shares = _calculateShares(_amount);

        _updateShares(_supplier, shares, true);
        _updateLiquidity(_amount, true, true);
    }

    ///////////////
    //USDC STAKE//
    /////////////

    /**
     * Remove/unstake liquidity from the system.
     * @param _supplier user supplier address.
     * @param _shares shares to unstake/remove/retrieve.
     * @return res USDC token amount retrieved/unstaked
     */
    function removeLiquidity(address _supplier, uint256 _shares) external onlyOwner returns (uint256) {
        if (totalShares == 0) {
            revert StakingRewards__NoUsdcLiquidityInTheSystem();
        }

        if (_shares > userInfo[_supplier].shares) {
            revert StakingRewards__InvalidLiquidityToRemove();
        }

        _updateUserRewards(_supplier);

        //Hacer el claim en una funcion aparte.
        uint256 usdcClaimed = _shares * nav / totalShares;

        if (usdcClaimed > usdcLiquidity) {
            revert StakingRewards__ThereIsNotEnoughLiquidityAvailable();
        }

        _updateShares(_supplier, _shares, false);
        _updateLiquidity(usdcClaimed, false, true);

        return usdcClaimed;
    }

    /**
     * Funtion used to borrow USDC. It reduces the liquidity and updates the nav because the fees.
     * The accountability is measured by the usdc liquidity and nav variables. We dont really need
     * the borrower user because we does not track each user debt here and its not necessary.
     * @param _borrower user borrower address.
     * @param _amountToLend amount to borrow/lend.
     */
    function lend(address _borrower, uint256 _amountToLend) external onlyOwner returns (uint256) {
        if (usdcLiquidity == 0) {
            revert StakingRewards__NoLiquidityInTheSystem();
        }

        uint256 amountWithFee = _amountToLend * (BPS_PRECISION - LEND_FEE_BPS) / BPS_PRECISION;
        _updateLiquidity(amountWithFee, false, false);
        _updateNav(_amountToLend - amountWithFee, true);

        return amountWithFee;
    }

    /**
     * Function used to repay or return the lended USDC.
     * @param _borrower user borrower address.
     * @param _amountToRepay USDC amount to return or repay.
     */
    function repay(address _borrower, uint256 _amountToRepay) external onlyOwner {
        //COmprabar que el ususario tiene deuda
        _updateLiquidity(_amountToRepay, true, false);
    }

    //////////////
    //ETH STAKE//
    ////////////

    /**
     * Function used to add ETH rewards in the system.
     */
    function addETHRewards() external payable onlyOwner {
        _updateRewards(msg.value);
    }

    /**
     * Function used to claim accumulated ETH rewards.
     * @param _supplier Supplier user address. The supplier that wants to claim their rewards.
     */
    function claim(address _supplier) external nonReentrant onlyOwner {
        _updateUserRewards(_supplier);

        uint256 pendingRewards = userInfo[_supplier].pending;
        if (pendingRewards == 0) {
            revert StakingRewards__NoRewardsToClaim();
        }

        userInfo[_supplier].pending = 0;
        (bool success,) = payable(_supplier).call{value: pendingRewards}("");

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

    function _updateUserRewards(address _supplier) private {
        uint256 accRewardsPerShare = accTotalETHRewardsPerShare - userInfo[_supplier].accETHRewardsPerShare;
        userInfo[_supplier].pending += accRewardsPerShare * userInfo[_supplier].shares / EIGHTEEN_PRECISION;
        userInfo[_supplier].accETHRewardsPerShare = accTotalETHRewardsPerShare;
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

    function _updateShares(address _supplier, uint256 _amount, bool add) private {
        uint256 userShares_c = userInfo[_supplier].shares;
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

        userInfo[_supplier].shares = userShares_c;
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
