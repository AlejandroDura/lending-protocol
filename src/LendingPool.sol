// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceOracle} from "./PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {HealthFactor} from "src/libraries/HealthFactor.sol";

contract LendingPool {
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
    error LendingPool__TransferFailed();
    error LendingPool__YourLiquidationAmountExceedTheLimits();
    error LendingPool__YourCanNotRedeemMoreThanYouHave();
    error LendingPool__AutoliquidationNotAllowed();
    error LendingPool__HealthFactorNotImproved();

    uint256 private constant BPS_PRECISION = 10_000;
    uint256 private constant LTV_BPS = 7500;
    uint256 private constant CLOSE_FACTOR_BPS = 5000;
    uint256 private constant PRICE_ADITIONAL_PRECISION = 1e10;
    uint256 private constant MIN_HEALTHFACTOR = 1e18;
    uint256 private constant LIQUIDATOR_COMMISSION = 300;

    uint256 private liquidationThreshold = 8000;
    mapping(address => uint256) private collateralETH;
    mapping(address => uint256) private debtUSDC;

    PriceOracle private priceOracle;
    DepositToken private depositToken;
    IERC20 private immutable usdcToken;

    constructor(address _depositToken, address _usdc, address _oracle) {
        depositToken = DepositToken(_depositToken);
        usdcToken = IERC20(_usdc);
        priceOracle = PriceOracle(_oracle);
    }

    function depositCollateral() public payable {
        collateralETH[msg.sender] += msg.value;

        //depositToken.mint(msg.sender, msg.value); //Añadir control de acceso a depositToken, esto aqui no, esto rastrea al ususario que ha añadido liquidez en USDC no al que ha depositado collateral.

        emit CollateralDeposited(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 _amount) public {
        //Añadir nonReentrant
        uint256 debt = debtUSDC[msg.sender];
        uint256 collateral = collateralETH[msg.sender];

        if (_amount > collateral) {
            revert LendingPool__AmountToWithdrawGreaterThanCollateral();
        }

        collateral -= _amount;
        collateralETH[msg.sender] = collateral;

        _checkHealthFactor(collateral, debt);

        //depositToken.burn(msg.sender, _amount); //Esto aqui tampoco
        (bool succeed,) = payable(msg.sender).call{value: _amount}("");
        if (!succeed) {
            revert LendingPool__TransactionRevert();
        }

        emit CollateralWithdrawn(msg.sender, _amount);
    }

    function borrow(uint256 _amount) public {
        uint256 collateral = collateralETH[msg.sender];
        uint256 debt = debtUSDC[msg.sender];

        debt += _amount;
        debtUSDC[msg.sender] = debt;

        _checkMaxLending(collateral, debt);

        _checkHealthFactor(collateral, debt);

        IERC20(usdcToken).transfer(msg.sender, _amount);
    }

    function repay(uint256 _amount) public {
        if (_amount > debtUSDC[msg.sender]) {
            revert LendingPool__AmountToRepayGreatherThanCurrentDebt();
        }

        debtUSDC[msg.sender] -= _amount;

        bool succeed = IERC20(usdcToken).transferFrom(msg.sender, address(this), _amount);
        if (!succeed) {
            revert LendingPool__TransferFailed();
        }
    }

    function liquidate(address _borrower, uint256 _debtToCover) public {
        if (msg.sender == _borrower) {
            revert LendingPool__AutoliquidationNotAllowed();
        }

        uint256 collateral = collateralETH[_borrower];
        uint256 debt = debtUSDC[_borrower];
        uint256 prevHealthFactor = _getHealthFactor(collateral, debt);

        uint256 closeFactor = debt * CLOSE_FACTOR_BPS / BPS_PRECISION;
        if (_debtToCover > closeFactor) {
            revert LendingPool__YourLiquidationAmountExceedTheLimits();
        }

        uint256 debtToCoverInUsd = _getUsdValue(address(usdcToken), _debtToCover);

        uint256 collateralToRedeem = _getTokenAmountFromUsd(address(0), debtToCoverInUsd);
        uint256 bonus = collateralToRedeem * LIQUIDATOR_COMMISSION / BPS_PRECISION;
        collateralToRedeem += bonus;
        debtUSDC[_borrower] -= _debtToCover;

        _redeemCollateral(_borrower, msg.sender, collateralToRedeem);
        uint256 currentHealthFactor = _getHealthFactor(collateral - collateralToRedeem, debt - _debtToCover);
        if (currentHealthFactor <= prevHealthFactor) {
            revert LendingPool__HealthFactorNotImproved();
        }
    }

    function getCollateral(address _user) public view returns (uint256) {
        return collateralETH[_user];
    }

    function getDebt(address _user) public view returns (uint256) {
        return debtUSDC[_user];
    }

    function checkHealthFactor(uint256 _collateralAmount, uint256 _debtAmount) public {
        _checkHealthFactor(_collateralAmount, _debtAmount);
    }

    function getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        return _getUsdValue(_token, _amount);
    }

    function getTokenAmountFromUsd(address _token, uint256 _usdValue) public view returns (uint256) {
        return _getTokenAmountFromUsd(_token, _usdValue);
    }

    ////////////
    //private//
    //////////
    function _checkMaxLending(uint256 _collateral, uint256 _debt) private view {
        uint256 collateralValueInUsd = _getUsdValue(address(0), _collateral);
        uint256 debtValueInUsd = _getUsdValue(address(usdcToken), _debt);

        uint256 maxToBorrowInUsd = HealthFactor.maxToBorrowInUsd(collateralValueInUsd, LTV_BPS);

        if (debtValueInUsd > maxToBorrowInUsd) {
            revert LendingPool__LendingExceedTheMaximum();
        }
    }

    function _getHealthFactor(uint256 _collateralAmount, uint256 _debtAmount) private view returns (uint256) {
        uint256 collateralValueInUsd = _getUsdValue(address(0), _collateralAmount);
        uint256 debtValueInUsd = _getUsdValue(address(usdcToken), _debtAmount);

        return HealthFactor.calculateHealthFactor(debtValueInUsd, collateralValueInUsd, liquidationThreshold);
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

    function _redeemCollateral(address _from, address _to, uint256 _amount) private {
        if (_amount > collateralETH[_from]) {
            revert LendingPool__YourCanNotRedeemMoreThanYouHave();
        }

        collateralETH[_from] -= _amount;
        (bool succeed,) = payable(_to).call{value: _amount}(""); //PROTECT WITH NON REENTRANT!!!

        if (!succeed) {
            revert LendingPool__TransferFailed();
        }
    }
}
