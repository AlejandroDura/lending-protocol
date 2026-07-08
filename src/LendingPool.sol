// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {PriceOracle} from "./PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HealthFactor} from "src/libraries/HealthFactor.sol";

contract LendingPool {
    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);

    error LendingPool__AmountToWithdrawGreaterThanCollateral();
    error LendingPool__NoLiquidityInTheSystem();
    error LendingPool__TransactionRevert();

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

    function borrow(uint256 _amount) public {}

    function repay(uint256 _amount) public {}

    function liquidate(address _borrower) public {}

    function getCollateral(address _user) public view returns (uint256) {
        return collateralETH[_user];
    }

    function getDebt(address _user) public view returns (uint256) {
        return debtUSDC[msg.sender];
    }
}
