// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceOracle} from "./PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Calculations} from "src/libraries/Calculations.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IRewardController {
    function notifyAddLiquidity(address _supplier, uint256 _amount) external;

    function notifyRemoveLiquidity(address _supplier, uint256 _shares) external returns (uint256);

    function notifyLend(address _borrower, uint256 _amount) external returns (uint256);

    function notifyRepay(address _borrower, uint256 _amount) external;

    function notifyAddETHRewards() external payable;

    function claim(address _supplier) external;
}

contract LendingPool is Ownable {
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    error LendingPool__AmountToWithdrawGreaterThanCollateral();
    error LendingPool__NoLiquidityInTheSystem();
    error LendingPool__TransactionRevert();
    error LendingPool__HealthFactorBroken();
    error LendingPool__LendingExceedTheMaximum();
    error LendingPool__AmountToRepayGreatherThanCurrentDebt();
    error LendingPool__YourLiquidationAmountExceedTheLimits();
    error LendingPool__YouCanNotRedeemMoreThanYouHave();
    error LendingPool__AutoliquidationNotAllowed();
    error LendingPool__HealthFactorNotImproved();
    error LendingPool__HealthFactorOK();
    error LendingPool__NoCollateral();
    error LendingPool__TransferFailed();

    uint256 private constant BPS_PRECISION = 10_000;
    uint256 private constant LTV_BPS = 7500;
    uint256 private constant CLOSE_FACTOR_BPS = 5000;
    uint256 private constant PRICE_ADITIONAL_PRECISION = 1e10;
    uint256 private constant MIN_HEALTHFACTOR = 1e18;
    uint256 private constant LIQUIDATOR_COMMISSION = 300;
    uint256 private constant COLLATERAL_COMMISSION = 50;

    uint256 private liquidationThreshold = 8000;
    mapping(address => uint256) private collateralETH;
    mapping(address => uint256) private debtUSDC;

    PriceOracle private priceOracle;
    DepositToken private depositToken;
    IERC20 private immutable usdcToken;
    IRewardController private rewardController;

    constructor(address _depositToken, address _usdc, address _oracle, address _rewardController) Ownable(msg.sender) {
        depositToken = DepositToken(_depositToken);
        usdcToken = IERC20(_usdc);
        priceOracle = PriceOracle(_oracle);
        rewardController = IRewardController(_rewardController);
    }

    /**
     * Suppliers can add liquidity and stake it into the system.
     * @param _amount Liquidity to stake in the system in USDC.
     */
    function addLiquidity(uint256 _amount) external {
        rewardController.notifyAddLiquidity(msg.sender, _amount);

        bool success = usdcToken.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert LendingPool__TransferFailed();
        }
    }

    /**
     * Suppliers can remove or retrieve its liquidity from the system.
     * @param _shares Shares to retrieve.
     */
    function removeLiquidity(uint256 _shares) external {
        uint256 amountToRemove = rewardController.notifyRemoveLiquidity(msg.sender, _shares);

        bool success = usdcToken.transfer(msg.sender, amountToRemove);
        if (!success) {
            revert LendingPool__TransferFailed();
        }
    }

    /**
     * Used for borrowers to deposit their collateral in ETH.
     */
    function depositCollateral() public payable {
        uint256 collateral = msg.value * (BPS_PRECISION - COLLATERAL_COMMISSION) / BPS_PRECISION;
        uint256 rewards = msg.value - collateral;

        collateralETH[msg.sender] += collateral;
        rewardController.notifyAddETHRewards{value: rewards}();

        emit CollateralDeposited(msg.sender, msg.value);
    }

    /**
     * Used for borrowers to retrieve their collateral
     */
    function withdrawCollateral(uint256 _amount) public {
        //Añadir nonReentrant
        uint256 debt = debtUSDC[msg.sender];
        uint256 collateral = collateralETH[msg.sender];

        if (_amount > collateral) {
            revert LendingPool__AmountToWithdrawGreaterThanCollateral();
        }

        _redeemCollateral(msg.sender, msg.sender, _amount);

        _checkHealthFactor(collateral - _amount, debt);

        emit CollateralWithdrawn(msg.sender, _amount);
    }

    /**
     * Used for borrowers to borrow them USDC
     * @param _amount USDC amount to borrow.
     */
    function borrow(uint256 _amount) public {
        uint256 collateral = collateralETH[msg.sender];
        if (collateral == 0) {
            revert LendingPool__NoCollateral();
        }

        uint256 debt = debtUSDC[msg.sender];

        debt += _amount;
        debtUSDC[msg.sender] = debt;

        _checkMaxLending(collateral, debt);

        _checkHealthFactor(collateral, debt);

        uint256 amountBorrowed = rewardController.notifyLend(msg.sender, _amount);
        bool success = usdcToken.transfer(msg.sender, amountBorrowed);
        if (!success) {
            revert LendingPool__TransferFailed();
        }
    }

    /**
     * This function allows a borrower to return their loan
     * @param _amount Amount to return in USDC
     */
    function repay(uint256 _amount) public {
        if (_amount > debtUSDC[msg.sender]) {
            revert LendingPool__AmountToRepayGreatherThanCurrentDebt();
        }

        debtUSDC[msg.sender] -= _amount;
        rewardController.notifyRepay(msg.sender, _amount);

        bool succeed = IERC20(usdcToken).transferFrom(msg.sender, address(this), _amount);
        if (!succeed) {
            revert LendingPool__TransactionRevert();
        }
    }

    /**
     * This function allows a liquidator to liquidate a target. This only works if the health factor target
     * is lower than 1.
     * @param _borrower Target borrower user to liquidate.
     * @param _debtToCover Amount to liquidate from the target in USDC.
     */
    function liquidate(address _borrower, uint256 _debtToCover) public {
        //Comprobar que el usuario target al que liquidamos tiene deuda para liquidar
        if (msg.sender == _borrower) {
            revert LendingPool__AutoliquidationNotAllowed();
        }

        uint256 collateral = collateralETH[_borrower];
        uint256 debt = debtUSDC[_borrower];
        uint256 prevHealthFactor = _getHealthFactor(collateral, debt);

        if (prevHealthFactor >= MIN_HEALTHFACTOR) {
            revert LendingPool__HealthFactorOK();
        }

        uint256 closeFactor = debt * CLOSE_FACTOR_BPS / BPS_PRECISION;
        if (_debtToCover > closeFactor) {
            revert LendingPool__YourLiquidationAmountExceedTheLimits();
        }

        uint256 debtToCoverInUsd = _getUsdValue(address(usdcToken), _debtToCover);

        uint256 collateralToRedeem = _getTokenAmountFromUsd(address(0), debtToCoverInUsd);
        uint256 bonus = collateralToRedeem * LIQUIDATOR_COMMISSION / BPS_PRECISION;
        collateralToRedeem += bonus;
        debtUSDC[_borrower] -= _debtToCover;
        rewardController.notifyRepay(_borrower, _debtToCover);

        _redeemCollateral(_borrower, msg.sender, collateralToRedeem);

        //Añadir que el liquidador pague al protocolo la deuda en USDC
        bool succeed = IERC20(usdcToken).transferFrom(msg.sender, address(this), _debtToCover);
        if (!succeed) {
            revert LendingPool__TransactionRevert();
        }

        uint256 currentHealthFactor = _getHealthFactor(collateral - collateralToRedeem, debt - _debtToCover);
        if (currentHealthFactor <= prevHealthFactor) {
            revert LendingPool__HealthFactorNotImproved();
        }
    }

    ////////////////
    //public view//
    //////////////

    /**
     * Get user collateral in ETH
     * @param _user user address.
     */
    function getCollateral(address _user) public view returns (uint256) {
        return collateralETH[_user];
    }

    /**
     * Get the user health factor
     * @param _user user address
     */
    function getHealthFactor(address _user) public view returns (uint256) {
        return _getHealthFactor(collateralETH[_user], debtUSDC[_user]);
    }

    //////////////////
    //Configuration//
    ////////////////

    /**
     * Function dedicated to change the reward controller address. It can only be called
     * by the owner.
     * @param _rewardController controller address.
     */
    function config_setRewardController(address _rewardController) external onlyOwner {
        rewardController = IRewardController(_rewardController);
    }

    /**
     * Revoke owner address and finish configuration. Only callable by the owner.
     */
    function config_configurationFinished() external onlyOwner {
        renounceOwnership();
    }

    /**
     * Get the user USDC debt in USDC
     * @param _user user address
     */
    function getDebt(address _user) public view returns (uint256) {
        return debtUSDC[_user];
    }

    /**
     * Get health factor given collateral in ETH and debt in USDC
     * @param _collateralAmount collateral in ETH
     * @param _debtAmount in USDC
     */
    function checkHealthFactor(uint256 _collateralAmount, uint256 _debtAmount) public {
        _checkHealthFactor(_collateralAmount, _debtAmount);
    }

    /**
     * Get the USD value of a token amount.
     * @param _token token address.
     * @param _amount token amount.
     * @return res USD value of that token amount.
     */
    function getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        return _getUsdValue(_token, _amount);
    }

    /**
     * Get token amount from USD value/amount
     * @param _token token address.
     * @param _usdValue USD value/amount to change by the given token.
     * @param res Token amount.
     */
    function getTokenAmountFromUsd(address _token, uint256 _usdValue) public view returns (uint256) {
        return _getTokenAmountFromUsd(_token, _usdValue);
    }

    /**
     * Get the max lending amount in USD.
     * @param _collateral collateral amount in ETH.
     */
    function getMaxLending(uint256 _collateral) public view returns (uint256) {
        return _getMaxLending(_collateral);
    }

    ////////////
    //private//
    //////////
    function _getMaxLending(uint256 _collateral) private view returns (uint256) {
        uint256 collateralValueInUsd = _getUsdValue(address(0), _collateral);
        console.log("Collateral value: ", collateralValueInUsd);
        return Calculations.maxToBorrowInUsd(collateralValueInUsd, LTV_BPS);
    }

    function _checkMaxLending(uint256 _collateral, uint256 _debt) private view {
        uint256 debtValueInUsd = _getUsdValue(address(usdcToken), _debt);

        uint256 maxToBorrowInUsd = _getMaxLending(_collateral);

        console.log("Max to borrow in usd: ", maxToBorrowInUsd);
        console.log("Debt in usd: ", debtValueInUsd);

        if (debtValueInUsd > maxToBorrowInUsd) {
            revert LendingPool__LendingExceedTheMaximum();
        }
    }

    function _getHealthFactor(uint256 _collateralAmount, uint256 _debtAmount) private view returns (uint256) {
        uint256 collateralValueInUsd = _getUsdValue(address(0), _collateralAmount);
        uint256 debtValueInUsd = _getUsdValue(address(usdcToken), _debtAmount);

        return Calculations.calculateHealthFactor(debtValueInUsd, collateralValueInUsd, liquidationThreshold);
    }

    function _checkHealthFactor(uint256 _collateralAmount, uint256 _debtAmount) private view {
        uint256 healthFactor = _getHealthFactor(_collateralAmount, _debtAmount);

        if (healthFactor < MIN_HEALTHFACTOR) {
            revert LendingPool__HealthFactorBroken();
        }
    }

    function _getUsdValue(address _token, uint256 _amount) private view returns (uint256) {
        uint256 tokenPrice = uint256(priceOracle.getPrice(_token)) * PRICE_ADITIONAL_PRECISION;
        uint256 decimals = _getTokenDecimals(_token);
        console.log("Token price: ", tokenPrice);
        console.log("Value usd: ", tokenPrice * _amount * (10 ** (18 - decimals)) / 1e18);
        console.log("Value usd_2", tokenPrice * _amount);
        console.log("Amount: ", _amount);
        return tokenPrice * _amount * (10 ** (18 - decimals)) / 1e18; // Only accepts till 18 decimals.
    }

    function _getTokenAmountFromUsd(address _token, uint256 _usdValue) private view returns (uint256) {
        uint256 tokenPrice = uint256(priceOracle.getPrice(_token)) * PRICE_ADITIONAL_PRECISION;
        uint256 tokenDecimals = _getTokenDecimals(_token);

        return _usdValue * (10 ** tokenDecimals) / tokenPrice;
    }

    function _getTokenDecimals(address _token) private view returns (uint8) {
        if (_token == address(0)) {
            return 18;
        }

        return IERC20Metadata(_token).decimals();
    }

    function _redeemCollateral(address _from, address _to, uint256 _amount) private returns (uint256) {
        uint256 collateral = collateralETH[_from];
        if (_amount > collateral) {
            revert LendingPool__YouCanNotRedeemMoreThanYouHave();
        }

        collateral -= _amount;
        collateralETH[_from] = collateral;
        (bool succeed,) = payable(_to).call{value: _amount}(""); //PROTECT WITH NON REENTRANT!!!, quitar el call de aqui y ponerlo en la funcion publica. Que esta fucnion devuelva el valor a transferir.

        if (!succeed) {
            revert LendingPool__TransactionRevert();
        }
    }
}
