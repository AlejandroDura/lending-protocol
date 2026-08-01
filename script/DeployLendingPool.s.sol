// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {LendingPool} from "src/LendingPool.sol";
import {PriceOracle} from "src/PriceOracle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployLendingPool is Script {
    address[] public tokens;
    address[] public priceFeeds;

    function run() external returns (LendingPool, PriceOracle, HelperConfig) {
        HelperConfig config = new HelperConfig();
        HelperConfig.NetworkConfig memory configInfo = config.getNetworkConfig();

        address ethPriceFeed = configInfo.ethPriceFeed;
        address usdcPriceFeed = configInfo.usdcPriceFeed;
        address eth = configInfo.eth;
        address usdc = configInfo.usdc;
        address depositToken = configInfo.depositToken;
        uint256 deployerKey = configInfo.deployerKey;

        tokens.push(address(0));
        priceFeeds.push(ethPriceFeed);

        tokens.push(usdc);
        priceFeeds.push(usdcPriceFeed);

        vm.startBroadcast(deployerKey);
        PriceOracle priceOracle = new PriceOracle(tokens, priceFeeds);
        LendingPool lendingPool = new LendingPool(depositToken, usdc, address(priceOracle));
        vm.stopBroadcast();

        return (lendingPool, priceOracle, config);
    }
}
