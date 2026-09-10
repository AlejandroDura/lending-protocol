// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LendingPool} from "src/LendingPool.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {DeployLendingPool} from "script/DeployLendingPool.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Handler} from "test/fuzz/Handler.t.sol";
import {RewardController} from "src/RewardController.sol";
import {StakingRewards} from "src/StakingRewards.sol";

contract Invariants is StdInvariant, Test {
    address[] public users;
    address liquidator;

    address[] public tokens;
    address[] public priceFeeds;

    DeployLendingPool public deployer;
    HelperConfig config;
    LendingPool public lendingPool;
    RewardController public rewardController;
    StakingRewards public staking;
    DepositToken public depositToken;
    PriceOracle public priceOracle;
    ERC20Mock public usdcToken;

    Handler handler;

    function setUp() public {
        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(user, 1_000_000 ether);
            users.push(user);
        }

        liquidator = makeAddr("liquidator");
        vm.deal(liquidator, 1_000_000 ether);

        deployer = new DeployLendingPool();
        (lendingPool, rewardController, staking, priceOracle, config) = deployer.run();

        usdcToken = ERC20Mock(config.getNetworkConfig().usdc);
        usdcToken.mint(address(lendingPool), 1_000_000e6);

        handler = new Handler(lendingPool, config, users);
        targetContract(address(handler));
    }

    function invariant_prueba() public {
        assertTrue(false);
    }
}
