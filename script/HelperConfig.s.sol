// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockAggregatorV3} from "test/mocks/MockAggregatorV3.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address ethPriceFeed;
        address usdcPriceFeed;
        address eth;
        address usdc;
        address depositToken;
        uint256 deployerKey;
    }

    uint8 public constant PRICE_DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant USDC_USD_PRICE = 1e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public returns (NetworkConfig memory) {
        vm.startBroadcast();
        address _depositToken = address(new DepositToken());
        vm.stopBroadcast();

        return NetworkConfig({
            ethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            usdcPriceFeed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E,
            eth: address(0),
            usdc: 0xf08A50178dfcDe18524640EA6618a1f965821715,
            depositToken: _depositToken,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.ethPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        address _depositToken = address(new DepositToken());
        address _usdcToken = address(new ERC20Mock("USDC", "USDC", address(this), 0, 6));

        address _ethPriceFeed = address(new MockAggregatorV3(8, 2000e8));
        address _usdcPriceFeed = address(new MockAggregatorV3(8, 1e8));
        vm.stopBroadcast();

        return NetworkConfig({
            ethPriceFeed: _ethPriceFeed,
            usdcPriceFeed: _usdcPriceFeed,
            eth: address(0),
            usdc: _usdcToken,
            depositToken: _depositToken,
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }

    function getNetworkConfig() public returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
