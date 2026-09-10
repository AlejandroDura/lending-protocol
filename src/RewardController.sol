// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IStakingReward {
    function addLiquidity(address _supplier, uint256 _amount) external;
    function removeLiquidity(address _supplier, uint256 _shares) external returns (uint256);
    function lend(address _borrower, uint256 _amountToLend) external returns (uint256);
    function repay(address _borrower, uint256 _amountToRepay) external;
    function addETHRewards() external payable;
    function claim(address _supplier) external;
}

contract RewardController is Ownable {
    IStakingReward public staking;

    constructor(address _initialOwner, address _staking) Ownable(_initialOwner) {
        staking = IStakingReward(_staking);
    }

    function notifyAddLiquidity(address _supplier, uint256 _amount) external onlyOwner {
        staking.addLiquidity(_supplier, _amount);
    }

    function notifyRemoveLiquidity(address _supplier, uint256 _shares) external onlyOwner returns (uint256) {
        return staking.removeLiquidity(_supplier, _shares);
    }

    function notifyLend(address _borrower, uint256 _amount) external onlyOwner returns (uint256) {
        return staking.lend(_borrower, _amount);
    }

    function notifyRepay(address _borrower, uint256 _amount) external onlyOwner {
        staking.repay(_borrower, _amount);
    }

    function notifyAddETHRewards() external payable onlyOwner {
        staking.addETHRewards{value: msg.value}();
    }

    function claim(address _supplier) external onlyOwner {
        staking.claim(_supplier);
    }
}
