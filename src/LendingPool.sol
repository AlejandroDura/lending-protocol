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

    uint256 private constant BPS_PRECISION = 10_000;
    uint256 private constant LTV_BPS = 7500;
    uint256 private constant PRICE_ADITIONAL_PRECISION = 1e10;
    uint256 private constant MIN_HEALTHFACTOR = 1e18;

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

        depositToken.mint(msg.sender, msg.value); //Añadir control de acceso a depositToken

        emit CollateralDeposited(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 _amount) public {
        //Añadir nonReentrant
        if (_amount > collateralETH[msg.sender]) {
            revert LendingPool__AmountToWithdrawGreaterThanCollateral();
        }

        collateralETH[msg.sender] -= _amount;

        depositToken.burn(msg.sender, _amount);
        (bool succeed,) = payable(msg.sender).call{value: _amount}("");
        if (!succeed) {
            revert LendingPool__TransactionRevert();
        }

        emit CollateralWithdrawn(msg.sender, _amount);
    }

    function borrow(uint256 _amount) public {
        debtUSDC[msg.sender] += _amount;
    }

    function repay(uint256 _amount) public {}

    function liquidate(address _borrower) public {}

    function getCollateral(address _user) public view returns (uint256) {
        return collateralETH[_user];
    }

    function getDebt(address _user) public view returns (uint256) {
        return debtUSDC[_user];
    }

    function checkHealthFactor() public {
        _checkHealthFactor();
    }

    function getUsdValue(address _token, uint256 _amount) public returns (uint256) {
        return _getUsdValue(_token, _amount);
    }

    ////////////
    //private//
    //////////
    function _checkHealthFactor() private {
        uint256 collateralValueInUsd = _getUsdValue(address(0), collateralETH[msg.sender]);
        uint256 debtValueInUsd = _getUsdValue(address(usdcToken), debtUSDC[msg.sender]);

        uint256 healthFactor =
            HealthFactor.calculateHealthFactor(debtValueInUsd, collateralValueInUsd, liquidationThreshold);

        if (healthFactor < MIN_HEALTHFACTOR) {
            revert LendingPool__HealthFactorBroken();
        }
    }

    function _getUsdValue(address _token, uint256 _amount) private returns (uint256) {
        uint256 tokenPrice = uint256(priceOracle.getPrice(_token)) * PRICE_ADITIONAL_PRECISION;
        uint256 decimals = _getTokenDecimals(_token);

        return tokenPrice * _amount * (10 ** (18 - decimals)) / 1e18; // Only accepts till 18 decimals.
    }

    function _getTokenDecimals(address _token) private view returns (uint8) {
        if (_token == address(0)) {
            return 18;
        }

        return IERC20Metadata(_token).decimals();
    }
}
