// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract PriceOracle {
    error PriceOracle__TokensAndPriceOraclesSizeMustBeEqual();
    error PriceOracle__InvalidPriceOracle();
    error PriceOracle__InvalidPrice();
    error PriceOracle__StalePrice();
    error PriceOracle__RoundIdMismatch();

    uint256 private constant TIMEOUT = 3 hours;

    mapping(address => address) tokenToPriceOracle;

    constructor(address[] memory _tokens, address[] memory _priceOracles) {
        if (_tokens.length != _priceOracles.length) {
            revert PriceOracle__TokensAndPriceOraclesSizeMustBeEqual();
        }

        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenToPriceOracle[_tokens[i]] = _priceOracles[i];
        }
    }

    /**
     * @dev Returns the token price in 8 decimals
     * @param _token the token address
     */
    function getPrice(address _token) external view returns (int256) {
        address priceOracle = tokenToPriceOracle[_token];

        if (priceOracle == address(0)) {
            revert PriceOracle__InvalidPriceOracle();
        }

        (, int256 answer,,,) = _staleCheck(priceOracle);

        return answer;
    }

    function getPriceOracle(address _token) public view returns (address) {
        return tokenToPriceOracle[_token];
    }

    function _staleCheck(address _priceOracle)
        private
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = AggregatorV3Interface(_priceOracle).latestRoundData();

        if (block.timestamp - updatedAt > TIMEOUT) {
            revert PriceOracle__StalePrice();
        }

        if (answer <= 0) {
            revert PriceOracle__InvalidPrice();
        }

        if (answeredInRound < roundId) {
            revert PriceOracle__RoundIdMismatch();
        }
    }
}
